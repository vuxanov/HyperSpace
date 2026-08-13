extends Node

## Central audio analysis pipeline — mic/loopback capture, FFT bands, energy, beat/onset.
## Godot cannot open WASAPI render-loopback natively; pick Stereo Mix / VB-Cable / VoiceMeeter
## as the input device to analyze system output, or use a normal microphone.
##
## Windows/WASAPI note: output_device invalidation (sleep, USB/BT headset, default-device flip)
## is an engine-side event. We soft-fail, backoff, and reconnect capture without hammering
## AudioServer.input_device / output_device switches.

signal state_updated(state: AudioState)
signal devices_changed(devices: PackedStringArray)
signal capture_status_changed(status: String)

const BUS_NAME := "HyperSpaceAnalysis"
const BAND_COUNT := 16
const BEAT_THRESHOLD := 1.4
const MIN_HZ := 20.0
const MAX_HZ := 16000.0
const RECONNECT_CHECK_INTERVAL := 1.5
const SPECTRUM_RETRY_BASE := 0.6
const DEVICE_SWITCH_COOLDOWN := 1.75
const DEVICE_SETTLE_SEC := 0.4
const SILENCE_BEFORE_RECONNECT := 2.75
const MAX_RECONNECT_BACKOFF := 8.0
const STATUS_DEVICE_LOST := "device lost — reconnecting…"
const LOOPBACK_HINTS: Array[String] = [
	"stereo mix",
	"what u hear",
	"wave out mix",
	"loopback",
	"cable output",
	"cable input",
	"vb-audio",
	"voicemeeter",
	"output (",
]

var current_state: AudioState = AudioState.new()
## Pre-gate peak-normalized spectrum (same 16 bins the Effects EQ graph draws). Drivers read this, not gated bass/energy.
var ui_bands: PackedFloat32Array = PackedFloat32Array()
## Slow peak-follow so EQ / input meter use the audible range (~1 when loud), not raw FFT crumbs.
var _driver_peak_ema: float = 0.0
## Scales final 0..1 drives (UI Master Intensity).
var master_intensity: float = 2.0
## Extra gain into perceptual mapping (UI Band Sensitivity maps into this).
var band_sensitivity: float = 1.75
## Raw magnitude below this (post-AGC) is treated as silence. Tunable 0..0.15.
var noise_floor: float = 0.018
var agc_enabled: bool = true

var _bus_index: int = -1
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _mic_player: AudioStreamPlayer
var _energy_history: float = 0.0
var _last_beat_time: float = 0.0
var _kick_env: float = 0.0
var _beat_flag: bool = false
var _agc_gain: float = 55.0
var _noise_ema: float = 0.0
var _reconnect_timer: float = 0.0
var _spectrum_retry_timer: float = 0.0
var _status: String = "starting"
var _had_signal: bool = false
var _auto_picked_loopback: bool = false
var _silence_timer: float = 0.0
var _reconnect_backoff: float = SPECTRUM_RETRY_BASE
var _device_cooldown: float = 0.0
var _pending_device: String = ""
var _device_settle_timer: float = -1.0
var _device_phase: int = 0  # 0 idle, 1 stop+wait, 2 set+wait, 3 restart
var _last_applied_device: String = ""
var _soft_reconnect_lock: float = 0.0
var _capture_started: bool = false
var _boot_timer: Timer


func _ready() -> void:
	current_state.bands.resize(BAND_COUNT)
	ui_bands.resize(BAND_COUNT)
	_setup_audio_bus()
	_prefer_loopback_device_once()
	_last_applied_device = AudioServer.input_device
	_set_status("starting · settling WASAPI")
	# Defer capture so an early input_device assign does not race the output client.
	_boot_timer = Timer.new()
	_boot_timer.one_shot = true
	_boot_timer.wait_time = 0.4
	_boot_timer.timeout.connect(_on_boot_settle_done)
	add_child(_boot_timer)
	_boot_timer.start()
	call_deferred("refresh_devices")


func _on_boot_settle_done() -> void:
	if _capture_started:
		return
	_start_capture()
	_try_bind_spectrum()
	_set_status("listening · %s" % AudioServer.input_device)


func _setup_audio_bus() -> void:
	_bus_index = AudioServer.get_bus_index(BUS_NAME)
	if _bus_index == -1:
		AudioServer.add_bus()
		_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus_index, BUS_NAME)
	while AudioServer.get_bus_effect_count(_bus_index) > 0:
		AudioServer.remove_bus_effect(_bus_index, 0)
	var spectrum := AudioEffectSpectrumAnalyzer.new()
	spectrum.buffer_length = 0.1
	spectrum.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
	AudioServer.add_bus_effect(_bus_index, spectrum, 0)
	# Keep the bus unmuted so SpectrumAnalyzer still sees the graph (mute can starve FFT
	# on some WASAPI setups) but crush send volume so mic never leaks to speakers.
	AudioServer.set_bus_mute(_bus_index, false)
	AudioServer.set_bus_volume_db(_bus_index, -80.0)
	AudioServer.set_bus_send(_bus_index, &"Master")


func _prefer_loopback_device_once() -> void:
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		push_warning("HyperSpace: audio/driver/enable_input is false — mic capture will be silent.")
		_set_status("enable_input off")
		return
	if _auto_picked_loopback:
		return
	_auto_picked_loopback = true
	# Only nudge once while still on Default — avoid unnecessary WASAPI churn.
	var current := String(AudioServer.input_device).strip_edges()
	if not current.is_empty() and current != "Default":
		return
	var loopback := _find_preferred_loopback_device()
	if loopback.is_empty():
		return
	AudioServer.input_device = loopback
	_last_applied_device = loopback
	_device_cooldown = DEVICE_SWITCH_COOLDOWN


func _find_preferred_loopback_device() -> String:
	var devices := AudioServer.get_input_device_list()
	for device in devices:
		var lower := String(device).to_lower()
		for hint in LOOPBACK_HINTS:
			if lower.contains(hint):
				return String(device)
	return ""


func _start_capture() -> void:
	if _mic_player == null or not is_instance_valid(_mic_player):
		_mic_player = AudioStreamPlayer.new()
		_mic_player.name = "MicCapture"
		_mic_player.bus = BUS_NAME
		_mic_player.stream = AudioStreamMicrophone.new()
		_mic_player.autoplay = false
		# Unity into the analysis bus so FFT sees real magnitudes. Leak guard is bus volume (-80 dB).
		_mic_player.volume_db = 0.0
		add_child(_mic_player)
	else:
		_mic_player.bus = BUS_NAME
		_mic_player.volume_db = 0.0
		if _mic_player.stream == null or not (_mic_player.stream is AudioStreamMicrophone):
			_mic_player.stream = AudioStreamMicrophone.new()
	if not _mic_player.playing:
		_mic_player.play()
	_capture_started = true


func _try_bind_spectrum() -> bool:
	if _bus_index < 0:
		return false
	var inst := AudioServer.get_bus_effect_instance(_bus_index, 0)
	_spectrum = inst as AudioEffectSpectrumAnalyzerInstance
	return _spectrum != null


func refresh_devices() -> PackedStringArray:
	var devices := AudioServer.get_input_device_list()
	devices_changed.emit(devices)
	return devices


func get_input_devices() -> PackedStringArray:
	return AudioServer.get_input_device_list()


func get_current_input_device() -> String:
	return AudioServer.input_device


func set_input_device(device_name: String) -> void:
	var name := device_name.strip_edges()
	if name.is_empty():
		name = "Default"
	# Skip no-op switches — reassigning the same device still invalidates WASAPI clients.
	var current := String(AudioServer.input_device).strip_edges()
	if name == current and name == _last_applied_device and _pending_device.is_empty() and _device_phase == 0:
		_soft_restart_capture(false)
		_set_status("listening · %s" % current)
		return
	_pending_device = name
	_had_signal = false
	_agc_gain = 55.0
	_noise_ema = 0.0
	_driver_peak_ema = 0.0
	_silence_timer = 0.0
	_set_status("switching device…")
	if _device_cooldown > 0.0 and _device_phase == 0:
		# Wait for cooldown; _process will apply.
		return
	_begin_device_apply()


func get_capture_status() -> String:
	return _status


func set_noise_floor(value: float) -> void:
	noise_floor = clampf(value, 0.0, 1.0e6)


func _begin_device_apply() -> void:
	if _pending_device.is_empty():
		return
	_device_phase = 1
	_device_settle_timer = DEVICE_SETTLE_SEC
	_device_cooldown = DEVICE_SWITCH_COOLDOWN
	_soft_reconnect_lock = DEVICE_SWITCH_COOLDOWN
	if _mic_player and is_instance_valid(_mic_player) and _mic_player.playing:
		_mic_player.stop()
	_spectrum = null


func _tick_device_apply(delta: float) -> void:
	if _device_phase == 0:
		if not _pending_device.is_empty() and _device_cooldown <= 0.0:
			_begin_device_apply()
		return
	_device_settle_timer -= delta
	if _device_settle_timer > 0.0:
		return
	match _device_phase:
		1:
			# Apply input device once, then settle before reopening capture.
			var name := _pending_device
			_pending_device = ""
			if not name.is_empty() and name != String(AudioServer.input_device):
				AudioServer.input_device = name
			_last_applied_device = String(AudioServer.input_device)
			_device_phase = 2
			_device_settle_timer = DEVICE_SETTLE_SEC
			_set_status("device: %s" % _last_applied_device)
		2:
			_soft_restart_capture(true)
			_device_phase = 0
			_reconnect_backoff = SPECTRUM_RETRY_BASE
			_set_status("listening · %s" % AudioServer.input_device)
		_:
			_device_phase = 0


func _soft_restart_capture(force_new_stream: bool) -> void:
	## Restart mic → analysis bus only. Does not touch AudioServer.input_device.
	if _mic_player and is_instance_valid(_mic_player):
		if _mic_player.playing:
			_mic_player.stop()
		if force_new_stream or _mic_player.stream == null or not (_mic_player.stream is AudioStreamMicrophone):
			_mic_player.stream = AudioStreamMicrophone.new()
		_mic_player.bus = BUS_NAME
		_mic_player.volume_db = 0.0
		_mic_player.play()
	else:
		_start_capture()
	_try_bind_spectrum()
	_capture_started = true


func _restart_capture() -> void:
	_soft_restart_capture(true)


func set_input_bus(bus_name: String) -> void:
	if _mic_player:
		_mic_player.bus = bus_name


func _process(delta: float) -> void:
	_kick_env = maxf(_kick_env - delta * 4.0, 0.0)
	_device_cooldown = maxf(_device_cooldown - delta, 0.0)
	_soft_reconnect_lock = maxf(_soft_reconnect_lock - delta, 0.0)
	_spectrum_retry_timer -= delta
	_reconnect_timer -= delta

	if not _capture_started:
		_emit_silence()
		return

	_tick_device_apply(delta)
	if _device_phase != 0:
		_emit_silence()
		return

	if _spectrum == null:
		if _spectrum_retry_timer <= 0.0:
			_spectrum_retry_timer = _reconnect_backoff
			_reconnect_backoff = minf(_reconnect_backoff * 1.45, MAX_RECONNECT_BACKOFF)
			if _soft_reconnect_lock <= 0.0:
				_set_status(STATUS_DEVICE_LOST)
				_soft_restart_capture(true)
				_soft_reconnect_lock = _reconnect_backoff
			if _try_bind_spectrum():
				_reconnect_backoff = SPECTRUM_RETRY_BASE
				_set_status("listening · %s" % AudioServer.input_device)
			else:
				_set_status("waiting for FFT")
		_emit_silence()
		return

	if _reconnect_timer <= 0.0:
		_reconnect_timer = RECONNECT_CHECK_INTERVAL
		_maintain_capture()
	_analyze()


func _maintain_capture() -> void:
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		return
	if _soft_reconnect_lock > 0.0 or _device_phase != 0:
		return
	if _mic_player == null or not is_instance_valid(_mic_player):
		_set_status(STATUS_DEVICE_LOST)
		_start_capture()
		_try_bind_spectrum()
		_soft_reconnect_lock = _reconnect_backoff
		return
	if not _mic_player.playing:
		_set_status(STATUS_DEVICE_LOST)
		_mic_player.play()
		_try_bind_spectrum()
		_soft_reconnect_lock = _reconnect_backoff
		_reconnect_backoff = minf(_reconnect_backoff * 1.35, MAX_RECONNECT_BACKOFF)


func _note_signal_or_silence(input_level: float, peak_raw: float) -> void:
	if input_level > 0.04:
		_had_signal = true
		_silence_timer = 0.0
		_reconnect_backoff = SPECTRUM_RETRY_BASE
		if _status.begins_with("reconnect") or _status == STATUS_DEVICE_LOST \
				or _status == "waiting for FFT" or _status == "listening" \
				or _status.begins_with("listening") or _status.begins_with("switching") \
				or _status.begins_with("device:"):
			_set_status("signal OK · %s" % AudioServer.input_device)
		return
	if not _had_signal:
		if _status.begins_with("signal"):
			_set_status("listening · %s" % AudioServer.input_device)
		return
	# Quiet music is fine. Only treat *dead* capture (near-zero raw magnitudes) as device loss.
	# AGC-normalized input_level can sit low during soft passages without the stream dying.
	if peak_raw > 1e-8:
		_silence_timer = 0.0
		return
	_silence_timer += get_process_delta_time()
	if _silence_timer >= SILENCE_BEFORE_RECONNECT and _soft_reconnect_lock <= 0.0 and _device_phase == 0:
		_silence_timer = 0.0
		_set_status(STATUS_DEVICE_LOST)
		_spectrum = null
		_soft_restart_capture(true)
		_soft_reconnect_lock = _reconnect_backoff
		_reconnect_backoff = minf(_reconnect_backoff * 1.5, MAX_RECONNECT_BACKOFF)


func _emit_silence() -> void:
	if ui_bands.size() != BAND_COUNT:
		ui_bands.resize(BAND_COUNT)
	ui_bands.fill(0.0)
	_driver_peak_ema = lerpf(_driver_peak_ema, 0.0, 0.12)
	if _driver_peak_ema < 1e-6:
		_driver_peak_ema = 0.0
	_beat_flag = false
	current_state.bands = ui_bands
	current_state.energy = 0.0
	current_state.peak = 0.0
	current_state.input_level = 0.0
	current_state.beat = false
	current_state.bass = 0.0
	current_state.mids = 0.0
	current_state.highs = 0.0
	current_state.kick = _kick_env
	state_updated.emit(current_state)


func _analyze() -> void:
	if _spectrum == null:
		return
	var raw_bands := PackedFloat32Array()
	raw_bands.resize(BAND_COUNT)
	var total_raw := 0.0
	var peak_raw := 0.0
	for i in BAND_COUNT:
		var t0 := float(i) / float(BAND_COUNT)
		var t1 := float(i + 1) / float(BAND_COUNT)
		var from_hz := MIN_HZ * pow(MAX_HZ / MIN_HZ, t0)
		var to_hz := MIN_HZ * pow(MAX_HZ / MIN_HZ, t1)
		var mag: Vector2 = _spectrum.get_magnitude_for_frequency_range(
			from_hz,
			to_hz,
			AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX
		)
		# Stereo energy (linear). Magnitudes are typically tiny (~1e-3..1e-1).
		var value := (absf(mag.x) + absf(mag.y)) * 0.5
		raw_bands[i] = value
		total_raw += value
		peak_raw = maxf(peak_raw, value)

	var mean_raw := total_raw / float(BAND_COUNT)
	_update_agc(peak_raw)
	var gated := _apply_noise_gate(raw_bands, mean_raw, peak_raw)
	var bass_raw: float = float(gated["bass"])
	var mids_raw: float = float(gated["mids"])
	var highs_raw: float = float(gated["highs"])
	var energy_raw: float = float(gated["energy"])
	var peak_g: float = float(gated["peak"])

	var bass := _to_drive(bass_raw)
	var mids := _to_drive(mids_raw)
	var highs := _to_drive(highs_raw)
	var energy := _to_drive(energy_raw)
	var peak_n := _to_drive(peak_g)

	# Peak-follow the raw FFT so EQ / input meter fill the audible range (loud ≈ 1).
	# Shape is real spectrum; we only rescale. Silence decays the follower to 0.
	var disp_scale := _update_display_peak(peak_raw)
	if ui_bands.size() != BAND_COUNT:
		ui_bands.resize(BAND_COUNT)
	var band_sum := 0.0
	for i in BAND_COUNT:
		var nv := 0.0
		if disp_scale > 0.0:
			nv = clampf(raw_bands[i] * disp_scale, 0.0, 1.0)
		ui_bands[i] = nv
		band_sum += nv
	# Mean vs peak: typical music sits mid-scale and still moves; a single loud bin still registers.
	var input_level := 0.0
	if disp_scale > 0.0:
		var mean_n := band_sum / float(BAND_COUNT)
		input_level = clampf(maxf(mean_n * 2.2, peak_raw * disp_scale * 0.55), 0.0, 1.0)

	_note_signal_or_silence(input_level, peak_raw)

	var beat := _detect_beat(energy)
	if beat:
		_kick_env = maxf(_kick_env, clampf(bass * 1.8 + energy * 0.6, 0.45, 1.0))

	_beat_flag = beat
	current_state.bands = ui_bands
	current_state.energy = energy
	current_state.peak = peak_n
	current_state.input_level = input_level
	current_state.beat = beat
	current_state.bass = bass
	current_state.mids = mids
	current_state.highs = highs
	current_state.kick = _kick_env
	state_updated.emit(current_state)


func _update_display_peak(peak_raw: float) -> float:
	## Fast attack / slow decay follower. Returns 1/ema, or 0 when fully silent.
	if peak_raw > 1e-8:
		if peak_raw > _driver_peak_ema:
			_driver_peak_ema = lerpf(_driver_peak_ema, peak_raw, 0.4)
		else:
			_driver_peak_ema = lerpf(_driver_peak_ema, peak_raw, 0.02)
		_driver_peak_ema = maxf(maxf(_driver_peak_ema, peak_raw * 0.9), 1e-8)
		return 1.0 / _driver_peak_ema
	_driver_peak_ema = lerpf(_driver_peak_ema, 0.0, 0.12)
	if _driver_peak_ema < 1e-6:
		_driver_peak_ema = 0.0
		return 0.0
	return 1.0 / _driver_peak_ema


func _update_agc(peak_raw: float) -> void:
	if not agc_enabled:
		_agc_gain = 55.0
		return
	# Adapt slowly toward a comfortable peak (~0.55 after base gain).
	if peak_raw > 1e-7:
		var target := 0.55 / peak_raw
		target = clampf(target, 8.0, 400.0)
		var rate := 0.04 if peak_raw * _agc_gain > 0.08 else 0.12
		_agc_gain = lerpf(_agc_gain, target, rate)
	else:
		_agc_gain = lerpf(_agc_gain, 80.0, 0.02)


func _effective_gain() -> float:
	## Sensitivity is applied once here (not again in _to_drive).
	return _agc_gain * maxf(band_sensitivity, 0.15)


func _apply_noise_gate(raw_bands: PackedFloat32Array, mean_raw: float, peak_raw: float) -> Dictionary:
	var gain := _effective_gain()
	# Track quiet-floor EMA when signal is soft.
	var scaled_peak := peak_raw * gain
	if scaled_peak < 0.12:
		_noise_ema = lerpf(_noise_ema, scaled_peak, 0.05)
	var floor_thresh := maxf(noise_floor, _noise_ema * 1.35 + 0.004)

	var out := PackedFloat32Array()
	out.resize(BAND_COUNT)
	var total := 0.0
	var peak := 0.0
	for i in BAND_COUNT:
		var v := maxf(raw_bands[i] * gain - floor_thresh, 0.0)
		out[i] = v
		total += v
		peak = maxf(peak, v)
	var energy := total / float(BAND_COUNT)
	return {
		"bands": out,
		"bass": _average_range(out, 0, 3),
		"mids": _average_range(out, 4, 9),
		"highs": _average_range(out, 10, BAND_COUNT - 1),
		"energy": energy,
		"peak": peak,
		"mean_raw": mean_raw,
	}


func _to_drive(gated_raw: float) -> float:
	## Map gated linear magnitudes into punchy 0..1 drives. Sensitivity already in gain.
	var v := maxf(gated_raw, 0.0) * maxf(master_intensity, 0.05)
	return clampf(pow(v, 0.55), 0.0, 1.0)


func _average_range(bands: PackedFloat32Array, from_idx: int, to_idx: int) -> float:
	var total := 0.0
	var count := 0
	for i in range(from_idx, mini(to_idx + 1, bands.size())):
		total += bands[i]
		count += 1
	return total / maxf(float(count), 1.0)


func _detect_beat(energy: float) -> bool:
	var threshold := _energy_history * BEAT_THRESHOLD + 0.04
	var is_beat := energy > threshold and energy > 0.08
	_energy_history = lerpf(_energy_history, energy, 0.18)
	if is_beat:
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_beat_time > 0.25:
			_last_beat_time = now
			return true
	return false


func _set_status(text: String) -> void:
	if _status == text:
		return
	_status = text
	capture_status_changed.emit(_status)


func get_driver_audio() -> Dictionary:
	## Same 0–1 bins the EQ graph draws (peak-followed). 0 = silence, ~1 = loud.
	if ui_bands.size() != BAND_COUNT:
		ui_bands.resize(BAND_COUNT)
	var peak_ui := 0.0
	for i in ui_bands.size():
		peak_ui = maxf(peak_ui, ui_bands[i])
	var bass_ui := clampf(_max_range(ui_bands, 0, 3), 0.0, 2.0)
	var mids_ui := clampf(_max_range(ui_bands, 4, 9), 0.0, 2.0)
	var highs_ui := clampf(_max_range(ui_bands, 10, BAND_COUNT - 1), 0.0, 2.0)
	var energy_ui := clampf(_average_range(ui_bands, 0, BAND_COUNT - 1), 0.0, 2.0)
	var peak_n := clampf(peak_ui, 0.0, 2.0)
	return {
		"bass": bass_ui,
		"mids": mids_ui,
		"highs": highs_ui,
		"energy": energy_ui,
		"peak": peak_n,
		"volume": maxf(energy_ui, peak_n),
		"kick": clampf(maxf(_kick_env, bass_ui), 0.0, 2.0),
		"beat": 1.0 if _beat_flag else 0.0,
		"bands": ui_bands,
	}


func _max_range(bands: PackedFloat32Array, from_idx: int, to_idx: int) -> float:
	var peak := 0.0
	for i in range(from_idx, mini(to_idx + 1, bands.size())):
		peak = maxf(peak, bands[i])
	return peak


func get_state() -> AudioState:
	return current_state.duplicate_state()
