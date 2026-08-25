extends Node

## Central audio analysis pipeline — FFT bands, energy, beat/onset.
##
## Everything analysed here comes from the microphone. Two mic paths exist because the
## Windows capture endpoint on this hardware runs the Realtek/Lenovo AISPEECHAPO
## ("Voice Focus"), which is tuned for speech: it treats music as background noise and
## its AGC lifts the room floor up to music level.
##   • SOURCE_MUSIC — native helper opens the same mic in WASAPI raw processing mode, which
##     bypasses that APO. Measured noise-floor peak 0.021 vs music 0.103.
##   • SOURCE_VOICE — Godot's AudioStreamMicrophone, i.e. the processed stream. Measured
##     noise-floor peak 0.120 vs music 0.142, so music barely stands out — but speech is
##     clean and loud, which is what that APO is for.
## The user picks the source; nothing switches behind their back.
##
## Windows/WASAPI note: output_device invalidation (sleep, USB/BT headset, default-device flip)
## is an engine-side event. We soft-fail, backoff, and reconnect capture without hammering
## AudioServer.input_device / output_device switches.

signal state_updated(state: AudioState)
signal devices_changed(devices: PackedStringArray)
signal capture_status_changed(status: String)
signal audio_sources_changed()

const BUS_NAME := "HyperSpaceAnalysis"
const RAW_MIC_BUS_NAME := "HyperSpaceRawMic"
const SINK_BUS_NAME := "HyperSpaceSink"
const RawMicScript := preload("res://core/raw_mic_capture.gd")
const SOURCE_MUSIC := "music"
const SOURCE_VOICE := "voice"
const RAW_MIC_RETRY_SEC := 8.0
## Raw capture has no noise suppression, so a per-band floor is learned and subtracted.
## Steady hiss/fan cancels to zero (silence stays flat); music rises above it.
## Oversubtracted: the estimate lands between the room's quietest moment and its average,
## so a plain 1.0 leaves the fluctuation behind and that is what paints a fake EQ.
const NOISE_SUB_K := 1.60
## Falls in well under a second, climbs over minutes. The asymmetry is the whole point: a
## quick rise learns the music itself as background and the visualiser goes dead a few
## seconds in — measured, a 24 s rise still swallowed a track. Falling fast costs nothing,
## because it just means the floor tracks the quiet moments between beats, and it recovers
## immediately if the floor was ever learned while something was playing.
const NOISE_FALL := 0.03
const NOISE_RISE := 0.00006
## How far above the room's own level the signal must sit to count as real, and how much of
## that bar is kept once it already counts, so quiet passages do not chatter the gate.
const PRESENT_NOISE_K := 1.8
const PRESENT_RELEASE := 0.62
const BAND_COUNT := 16
const BEAT_THRESHOLD := 1.4
## Music visualizer range (kick/sub through air). Not telephony 300–3400 Hz.
const MIN_HZ := 32.0
const MAX_HZ := 20000.0
## 16 ISO-ish edges so kick (50–80), bass (80–250), and hats (6–16 kHz) each own bins.
## Naive log(20–16k) wasted bins on 20–40 Hz (empty on mics) and packed speech into mids.
## File-level vars — typed Array[float] consts are not constexpr in this Godot build.
var BAND_EDGES_HZ: PackedFloat32Array = PackedFloat32Array([
	32.0, 50.0, 80.0, 125.0, 200.0, 315.0, 500.0, 800.0,
	1250.0, 2000.0, 3150.0, 5000.0, 8000.0, 10000.0, 12500.0, 16000.0, 20000.0,
])
## Boost kick/bass/hats; duck the speech core (~300–3400 Hz, bands 5–9) so talking is not preferred.
var BAND_WEIGHTS: PackedFloat32Array = PackedFloat32Array([
	2.15, 2.40, 2.10, 1.75, 1.15, 0.82, 0.70, 0.68,
	0.72, 0.80, 1.05, 1.35, 1.55, 1.70, 1.80, 1.55,
])
## The body of the kick, not its fundamental. Laptop speakers put out nothing at 40–80 Hz
## and the capture high-pass removes that range anyway, so looking there found silence.
const KICK_HZ_LO := 150.0
const KICK_HZ_HI := 350.0
const RECONNECT_CHECK_INTERVAL := 0.4
const SPECTRUM_RETRY_BASE := 0.35
const DEVICE_SWITCH_COOLDOWN := 1.75
const DEVICE_SETTLE_SEC := 0.4
const DEVICE_POLL_INTERVAL := 1.5
const DEVICE_MISSING_FALLBACK_SEC := 2.5
const FRAME_STARVE_SEC := 0.45
const HOLD_LAST_SEC := 0.16
const MAX_RECONNECT_BACKOFF := 4.0
const ALIVE_PEAK := 1.2e-5
const PCM_ALIVE := 0.0012
## Peak-normalize must not amplify below this or hiss fills the Graphic EQ.
const UI_PEAK_ABS_FLOOR := 0.00035
const SPECTRUM_BUFFER_SEC := 0.85
const CAPTURE_BUFFER_SEC := 0.4
const STATUS_DEVICE_LOST := "device lost — reconnecting…"

var current_state: AudioState = AudioState.new()
## Peak-normalized 16-bin spectrum (Graphic EQ). Bass/mids/highs/bandN are shaped from this.
var ui_bands: PackedFloat32Array = PackedFloat32Array()
## Slow peak-follow so EQ / input meter use the audible range (~1 when loud), not raw FFT crumbs.
var _driver_peak_ema: float = 0.0
## Scales final 0..1 drives (UI Master Intensity). Default 2 → full kick gate.
var master_intensity: float = 2.0
## How easily bands/kick cross into motion (UI Band Sensitivity * 0.35).
var band_sensitivity: float = 1.75
## Noise Floor Gate: raw + post-gain threshold. Higher = ignore more hiss.
var noise_floor: float = 0.018
var agc_enabled: bool = true

var _bus_index: int = -1
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _capture_fx: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _smooth_bands: PackedFloat32Array = PackedFloat32Array()
var _pcm_rms: float = 0.0
var _no_frames_timer: float = 0.0
var _hold_timer: float = 0.0
var _stall_restarts: int = 0
var _energy_history: float = 0.0
var _last_beat_time: float = 0.0
var _kick_env: float = 0.0
var _kick_hold: float = 0.0
var _beat_env: float = 0.0
var _beat_hold: float = 0.0
var _prev_low: float = 0.0
var _prev_bb: float = 0.0
var _flux_ema: float = 0.0
var _bb_flux_ema: float = 0.0
var _bass_avg: float = 0.0
var _mids_avg: float = 0.0
var _highs_avg: float = 0.0
var _energy_avg: float = 0.0
var _volume_drive: float = 0.0
var _pcm_loud_ema: float = 0.0
var _driver_bands: PackedFloat32Array = PackedFloat32Array()
var _beat_flag: bool = false
var _agc_gain: float = 40.0
var _noise_ema: float = 0.0
var _reconnect_timer: float = 0.0
var _spectrum_retry_timer: float = 0.0
var _status: String = "starting"
var _had_signal: bool = false
var _silence_timer: float = 0.0
var _reconnect_backoff: float = SPECTRUM_RETRY_BASE
var _device_cooldown: float = 0.0
var _pending_device: String = ""
var _device_settle_timer: float = -1.0
var _device_phase: int = 0  # 0 idle, 1 stop+wait, 2 set+wait, 3 restart
var _last_applied_device: String = ""
var _preferred_device: String = ""
var _cached_input_devices: PackedStringArray = PackedStringArray()
var _soft_reconnect_lock: float = 0.0
var _capture_started: bool = false
var _device_poll_timer: float = 0.0
var _device_missing_timer: float = 0.0
var _boot_timer: Timer
var _raw_mic: Node = null
var _raw_mic_bus_index: int = -1
var _raw_mic_spectrum: AudioEffectSpectrumAnalyzerInstance
var _raw_mic_capture_fx: AudioEffectCapture
var _use_raw_mic: bool = false
var _raw_mic_pcm: float = 0.0
var _raw_mic_retry_timer: float = 0.0
var _raw_mic_no_frames: float = 0.0
var _selected_source: String = SOURCE_MUSIC
var _band_noise: PackedFloat32Array = PackedFloat32Array()
var _pcm_noise: float = 0.0
var _pcm_signal: float = 0.0
var _kick_noise: float = 0.0
var _was_present: bool = false
var _debug_raw_bands: PackedFloat32Array = PackedFloat32Array()
var _debug_clean_peak: float = 0.0
var _debug_present_floor: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	current_state.bands.resize(BAND_COUNT)
	ui_bands.resize(BAND_COUNT)
	_driver_bands.resize(BAND_COUNT)
	_smooth_bands.resize(BAND_COUNT)
	_band_noise.resize(BAND_COUNT)
	_setup_audio_bus()
	_preferred_device = "Default"
	_last_applied_device = "Default"
	_set_status("starting · microphone")
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
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		push_warning("HyperSpace: audio/driver/enable_input is false — mic capture will be silent.")
		_set_status("enable_input off")
	_start_capture()
	_try_bind_spectrum()
	if not Engine.is_editor_hint():
		_start_raw_mic()
	_use_raw_mic = _selected_source == SOURCE_MUSIC and _raw_mic_ready()
	_set_listening_status()


func _ensure_sink_bus() -> void:
	## Muted sink so analysis never mixes into WASAPI output / speakers.
	var sink_idx := AudioServer.get_bus_index(SINK_BUS_NAME)
	if sink_idx == -1:
		AudioServer.add_bus()
		sink_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(sink_idx, SINK_BUS_NAME)
	AudioServer.set_bus_mute(sink_idx, true)
	AudioServer.set_bus_volume_db(sink_idx, -80.0)
	AudioServer.set_bus_send(sink_idx, &"Master")


func _setup_audio_bus() -> void:
	_ensure_sink_bus()
	_bus_index = AudioServer.get_bus_index(BUS_NAME)
	if _bus_index == -1:
		AudioServer.add_bus()
		_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus_index, BUS_NAME)
	while AudioServer.get_bus_effect_count(_bus_index) > 0:
		AudioServer.remove_bus_effect(_bus_index, 0)
	var spectrum := AudioEffectSpectrumAnalyzer.new()
	# 0.1s starved FFT hops and looked choppy. 0.85s keeps a stable window.
	spectrum.buffer_length = SPECTRUM_BUFFER_SEC
	# 4096 ≈ 12 Hz bins at 48 kHz so kick (40–80 Hz) is several bins, not one smeared cell.
	spectrum.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_4096
	AudioServer.add_bus_effect(_bus_index, spectrum, 0)
	_capture_fx = AudioEffectCapture.new()
	_capture_fx.buffer_length = CAPTURE_BUFFER_SEC
	AudioServer.add_bus_effect(_bus_index, _capture_fx, 1)
	# Full level into SpectrumAnalyzer. Mute starves FFT on some WASAPI setups;
	# sending to a muted sink keeps FFT loud without a Master / output-client mix.
	AudioServer.set_bus_mute(_bus_index, false)
	AudioServer.set_bus_volume_db(_bus_index, 0.0)
	AudioServer.set_bus_send(_bus_index, StringName(SINK_BUS_NAME))
	_spectrum = null


func _setup_raw_mic_bus() -> void:
	## Dedicated muted-sink bus so raw mic PCM never mixes with the processed mic FFT.
	_ensure_sink_bus()
	_raw_mic_bus_index = AudioServer.get_bus_index(RAW_MIC_BUS_NAME)
	if _raw_mic_bus_index == -1:
		AudioServer.add_bus()
		_raw_mic_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_raw_mic_bus_index, RAW_MIC_BUS_NAME)
	while AudioServer.get_bus_effect_count(_raw_mic_bus_index) > 0:
		AudioServer.remove_bus_effect(_raw_mic_bus_index, 0)
	var spectrum := AudioEffectSpectrumAnalyzer.new()
	spectrum.buffer_length = SPECTRUM_BUFFER_SEC
	spectrum.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_4096
	AudioServer.add_bus_effect(_raw_mic_bus_index, spectrum, 0)
	_raw_mic_capture_fx = AudioEffectCapture.new()
	_raw_mic_capture_fx.buffer_length = CAPTURE_BUFFER_SEC
	AudioServer.add_bus_effect(_raw_mic_bus_index, _raw_mic_capture_fx, 1)
	AudioServer.set_bus_mute(_raw_mic_bus_index, false)
	AudioServer.set_bus_volume_db(_raw_mic_bus_index, 0.0)
	AudioServer.set_bus_send(_raw_mic_bus_index, StringName(SINK_BUS_NAME))
	_raw_mic_spectrum = null


func _start_raw_mic() -> void:
	_setup_raw_mic_bus()
	if _raw_mic == null or not is_instance_valid(_raw_mic):
		_raw_mic = RawMicScript.new()
		_raw_mic.name = "RawMicCapture"
		add_child(_raw_mic)
	_raw_mic.start_on_bus(RAW_MIC_BUS_NAME)
	_try_bind_raw_mic_spectrum()
	_raw_mic_retry_timer = RAW_MIC_RETRY_SEC


func _try_bind_raw_mic_spectrum() -> bool:
	if _raw_mic_bus_index < 0:
		return false
	var inst := AudioServer.get_bus_effect_instance(_raw_mic_bus_index, 0)
	_raw_mic_spectrum = inst as AudioEffectSpectrumAnalyzerInstance
	return _raw_mic_spectrum != null


func _raw_mic_ready() -> bool:
	return _raw_mic != null and is_instance_valid(_raw_mic) \
			and _raw_mic.has_method("is_alive") and _raw_mic.is_alive()


func _configure_mic_player() -> void:
	_mic_player.bus = BUS_NAME
	_mic_player.volume_db = 0.0
	_mic_player.autoplay = false
	_mic_player.process_mode = Node.PROCESS_MODE_ALWAYS
	if _mic_player.stream == null or not (_mic_player.stream is AudioStreamMicrophone):
		_mic_player.stream = AudioStreamMicrophone.new()
	if "playback_type" in _mic_player:
		_mic_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM


func _start_capture() -> void:
	if _mic_player == null or not is_instance_valid(_mic_player):
		_mic_player = AudioStreamPlayer.new()
		_mic_player.name = "MicCapture"
		_configure_mic_player()
		add_child(_mic_player)
	else:
		_configure_mic_player()
	if not _mic_player.playing:
		_mic_player.play()
	_capture_started = true
	_no_frames_timer = 0.0


func _try_bind_spectrum() -> bool:
	if _bus_index < 0:
		return false
	var inst := AudioServer.get_bus_effect_instance(_bus_index, 0)
	_spectrum = inst as AudioEffectSpectrumAnalyzerInstance
	return _spectrum != null


func _active_spectrum() -> AudioEffectSpectrumAnalyzerInstance:
	if _use_raw_mic:
		if _raw_mic_spectrum == null:
			_try_bind_raw_mic_spectrum()
		return _raw_mic_spectrum
	if _spectrum == null:
		_try_bind_spectrum()
	return _spectrum


func _ensure_raw_mic_running() -> void:
	if Engine.is_editor_hint():
		return
	_raw_mic_retry_timer = maxf(_raw_mic_retry_timer - get_process_delta_time(), 0.0)
	if _raw_mic != null and is_instance_valid(_raw_mic) and _raw_mic.has_method("is_running") and _raw_mic.is_running():
		if _raw_mic_spectrum == null:
			_try_bind_raw_mic_spectrum()
		return
	if _raw_mic_retry_timer > 0.0:
		return
	_start_raw_mic()


func _tick_source_select() -> void:
	## Follow the user's choice. The only automatic move is falling back to the processed
	## mic if the raw helper is not delivering, so capture never goes dead silently.
	var want := _selected_source == SOURCE_MUSIC and _raw_mic_ready()
	if want != _use_raw_mic:
		_switch_analysis_source(want)


func _switch_analysis_source(to_raw_mic: bool) -> void:
	_use_raw_mic = to_raw_mic
	_reset_analysis_memory()
	if ui_bands.size() != BAND_COUNT:
		ui_bands.resize(BAND_COUNT)
	ui_bands.fill(0.0)
	if _smooth_bands.size() != BAND_COUNT:
		_smooth_bands.resize(BAND_COUNT)
	_smooth_bands.fill(0.0)
	if _band_noise.size() != BAND_COUNT:
		_band_noise.resize(BAND_COUNT)
	_band_noise.fill(0.0)
	_pcm_noise = 0.0
	_pcm_signal = 0.0
	_kick_noise = 0.0
	_was_present = false
	_zero_driver_bands()
	_driver_peak_ema = 0.0
	if _raw_mic != null and is_instance_valid(_raw_mic) and _raw_mic.has_method("flush_zeros"):
		if not to_raw_mic:
			_raw_mic.flush_zeros()
	if to_raw_mic:
		_try_bind_raw_mic_spectrum()
	_set_listening_status()


func get_audio_sources() -> Array:
	## Plain-language labels. The music entry is the raw WASAPI capture that skips the
	## speech APO; the voice entry is what Windows hands every app by default.
	return [
		{"id": SOURCE_MUSIC, "label": "Microphone (music)", "available": _raw_mic_ready()},
		{"id": SOURCE_VOICE, "label": "Microphone (voice)", "available": true},
	]


func get_audio_source() -> String:
	return _selected_source


func set_audio_source(source_id: String) -> void:
	var chosen := source_id.strip_edges().to_lower()
	if chosen != SOURCE_MUSIC and chosen != SOURCE_VOICE:
		chosen = SOURCE_MUSIC
	if chosen == _selected_source:
		return
	_selected_source = chosen
	_had_signal = false
	_agc_gain = 40.0
	_noise_ema = 0.0
	_silence_timer = 0.0
	_switch_analysis_source(chosen == SOURCE_MUSIC and _raw_mic_ready())
	audio_sources_changed.emit()


func refresh_devices() -> PackedStringArray:
	_cached_input_devices = _compose_device_list()
	devices_changed.emit(_cached_input_devices)
	return _cached_input_devices


func get_input_devices() -> PackedStringArray:
	if _cached_input_devices.is_empty():
		_cached_input_devices = _compose_device_list()
	return _cached_input_devices


func get_current_input_device() -> String:
	return String(AudioServer.input_device).strip_edges()


func set_input_device(device_name: String) -> void:
	var chosen := device_name.strip_edges()
	if chosen.is_empty() or chosen.to_lower() == "system audio" or chosen == "system_loopback":
		chosen = "Default"
	_preferred_device = chosen
	# Skip no-op switches — reassigning the same device invalidates WASAPI clients.
	var current := String(AudioServer.input_device).strip_edges()
	if chosen == current and chosen == _last_applied_device and _pending_device.is_empty() and _device_phase == 0:
		_ensure_player_playing()
		_try_bind_spectrum()
		return
	_pending_device = chosen
	_had_signal = false
	_agc_gain = 40.0
	_noise_ema = 0.0
	_driver_peak_ema = 0.0
	_silence_timer = 0.0
	_reset_analysis_memory()
	_set_status("switching device…")
	if _device_cooldown > 0.0 and _device_phase == 0:
		return
	_begin_device_apply()


func get_capture_status() -> String:
	return _status


func describe_input_device(_device_name: String) -> String:
	return "Microphone"


func get_source_kind() -> String:
	return _selected_source


func is_voice_mic_source() -> bool:
	return _selected_source == SOURCE_VOICE


func set_noise_floor(value: float) -> void:
	noise_floor = clampf(value, 0.0, 1.0e6)


func _reset_analysis_memory() -> void:
	_kick_env = 0.0
	_kick_hold = 0.0
	_beat_env = 0.0
	_beat_hold = 0.0
	_prev_low = 0.0
	_prev_bb = 0.0
	_flux_ema = 0.0
	_bb_flux_ema = 0.0
	_bass_avg = 0.0
	_mids_avg = 0.0
	_highs_avg = 0.0
	_energy_avg = 0.0
	_volume_drive = 0.0
	_pcm_loud_ema = 0.0
	_pcm_signal = 0.0
	_beat_flag = false
	if _driver_bands.size() != BAND_COUNT:
		_driver_bands.resize(BAND_COUNT)
	_driver_bands.fill(0.0)


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
			var chosen := _pending_device
			_pending_device = ""
			if not chosen.is_empty() and chosen != String(AudioServer.input_device):
				AudioServer.input_device = chosen
			_last_applied_device = String(AudioServer.input_device)
			_device_phase = 2
			_device_settle_timer = DEVICE_SETTLE_SEC
			_set_status("device: %s" % _last_applied_device)
		2:
			_soft_restart_capture(true)
			_device_phase = 0
			_reconnect_backoff = SPECTRUM_RETRY_BASE
			_set_listening_status()
		_:
			_device_phase = 0


func _soft_restart_capture(force_new_stream: bool) -> void:
	## Restart mic → analysis bus only. Does not touch AudioServer.input_device.
	if _mic_player and is_instance_valid(_mic_player):
		if _mic_player.playing:
			_mic_player.stop()
		if force_new_stream or _mic_player.stream == null or not (_mic_player.stream is AudioStreamMicrophone):
			_mic_player.stream = AudioStreamMicrophone.new()
		_configure_mic_player()
		_mic_player.play()
	else:
		_start_capture()
	_try_bind_spectrum()
	_capture_started = true
	_no_frames_timer = 0.0
	_hold_timer = 0.0


func _restart_capture() -> void:
	_soft_restart_capture(true)


func set_input_bus(bus_name: String) -> void:
	if _mic_player:
		_mic_player.bus = bus_name


func _process(delta: float) -> void:
	_device_cooldown = maxf(_device_cooldown - delta, 0.0)
	_soft_reconnect_lock = maxf(_soft_reconnect_lock - delta, 0.0)
	_device_poll_timer = maxf(_device_poll_timer - delta, 0.0)
	_spectrum_retry_timer -= delta
	_reconnect_timer -= delta

	if not _capture_started:
		_emit_silence()
		return

	_tick_device_apply(delta)
	_ensure_player_playing()
	_ensure_raw_mic_running()
	var mic_pcm := _tick_pcm_capture(delta)
	_raw_mic_pcm = _tick_raw_mic_pcm(delta)
	_tick_source_select()
	# A processed-mic device settle must not blank the raw mic stream.
	if _device_phase != 0 and not _use_raw_mic:
		_hold_or_silence(delta)
		return
	_pcm_rms = _raw_mic_pcm if _use_raw_mic else mic_pcm
	_update_pcm_noise()

	if _active_spectrum() == null:
		if _spectrum_retry_timer <= 0.0:
			_spectrum_retry_timer = _reconnect_backoff
			var bound := _try_bind_spectrum()
			bound = _try_bind_raw_mic_spectrum() or bound
			if bound:
				_reconnect_backoff = SPECTRUM_RETRY_BASE
				_set_listening_status()
			else:
				if _use_raw_mic:
					_rebuild_raw_mic_effects()
				else:
					_rebuild_analysis_effects()
				_reconnect_backoff = minf(_reconnect_backoff * 1.45, MAX_RECONNECT_BACKOFF)
		_hold_or_silence(delta)
		return

	if _reconnect_timer <= 0.0:
		_reconnect_timer = RECONNECT_CHECK_INTERVAL
		_maintain_capture()
	_analyze()


func _notification(what: int) -> void:
	# Sleep / alt-tab / monitor wake often invalidates WASAPI. Do not reopen here —
	# the next watchdog tick will play() or restore the preferred device if needed.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_device_poll_timer = 0.0
		_reconnect_timer = 0.0


func _ensure_player_playing() -> void:
	if _mic_player == null or not is_instance_valid(_mic_player):
		_start_capture()
		return
	_configure_mic_player()
	if not _mic_player.playing:
		_mic_player.play()
	_capture_started = true


func _device_in_list(device_name: String) -> bool:
	if device_name.is_empty() or device_name == "Default":
		return true
	for d in _cached_input_devices:
		if String(d) == device_name:
			return true
	return false


func _poll_input_devices_if_due() -> void:
	if _device_poll_timer > 0.0:
		return
	_device_poll_timer = DEVICE_POLL_INTERVAL
	var devices := _compose_device_list()
	var changed := devices.size() != _cached_input_devices.size()
	if not changed:
		for i in devices.size():
			if String(devices[i]) != String(_cached_input_devices[i]):
				changed = true
				break
	_cached_input_devices = devices
	if changed:
		devices_changed.emit(devices)


func _restore_preferred_or_fallback() -> void:
	if _device_phase != 0 or _soft_reconnect_lock > 0.0:
		return
	var live := String(AudioServer.input_device).strip_edges()
	var preferred := _preferred_device.strip_edges()
	if preferred.is_empty():
		preferred = "Default"
	if live.is_empty():
		_set_status(STATUS_DEVICE_LOST)
		_pending_device = preferred if _device_in_list(preferred) else "Default"
		_begin_device_apply()
		return
	if preferred == "Default":
		_device_missing_timer = 0.0
		return
	if _device_in_list(preferred):
		_device_missing_timer = 0.0
		# Only restore when Godot/Windows dropped to empty or Default — not when
		# the engine reports a different real name for the same endpoint.
		if live != preferred and (live.is_empty() or live == "Default"):
			_pending_device = preferred
			_begin_device_apply()
		return
	_device_missing_timer += RECONNECT_CHECK_INTERVAL
	_set_status(STATUS_DEVICE_LOST)
	if _device_missing_timer >= DEVICE_MISSING_FALLBACK_SEC:
		_device_missing_timer = 0.0
		_pending_device = "Default"
		_begin_device_apply()


func _maintain_capture() -> void:
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		return
	if _device_phase != 0:
		return
	_poll_input_devices_if_due()
	if _soft_reconnect_lock > 0.0:
		_ensure_player_playing()
		_try_bind_spectrum()
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
		return
	_restore_preferred_or_fallback()
	# PCM frames stopped while the player still says "playing" — WASAPI capture died.
	# A quiet room still delivers frames (near-zero PCM); do not treat silence as death.
	if _no_frames_timer >= FRAME_STARVE_SEC and _soft_reconnect_lock <= 0.0:
		_force_capture_restart("capture starved")
		return


func _note_signal_or_silence(input_level: float, peak_raw: float) -> void:
	var pcm_alive := _pcm_signal > PCM_ALIVE
	var real_signal := input_level > 0.04 and (peak_raw > ALIVE_PEAK * 8.0 or _pcm_signal > 0.004)
	if real_signal:
		_had_signal = true
		_silence_timer = 0.0
		_reconnect_backoff = SPECTRUM_RETRY_BASE
		if _status.begins_with("reconnect") or _status == STATUS_DEVICE_LOST \
				or _status == "waiting for FFT" or _status.begins_with("switching") \
				or _status.begins_with("device:") or _status.begins_with("capture starved") \
				or _status.begins_with("starting"):
			_set_listening_status()
		return
	if peak_raw > ALIVE_PEAK or pcm_alive:
		_silence_timer = 0.0
	else:
		_silence_timer += get_process_delta_time()
	if _status.begins_with("signal") and input_level <= 0.02:
		_set_listening_status()


func _emit_silence() -> void:
	if ui_bands.size() != BAND_COUNT:
		ui_bands.resize(BAND_COUNT)
	ui_bands.fill(0.0)
	if _driver_bands.size() != BAND_COUNT:
		_driver_bands.resize(BAND_COUNT)
	_driver_bands.fill(0.0)
	_driver_peak_ema = lerpf(_driver_peak_ema, 0.0, 0.2)
	if _driver_peak_ema < 1e-6:
		_driver_peak_ema = 0.0
	_tick_kick_gate(0.0, 0.0, 0.0)
	_beat_env = 0.0
	_beat_hold = 0.0
	_volume_drive = 0.0
	_pcm_signal = 0.0
	_pcm_loud_ema = lerpf(_pcm_loud_ema, 0.0, 0.28)
	_decay_averages()
	_publish_drives(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false)


func _analyze() -> void:
	# Re-fetch every frame. Anything that rebuilds a bus (device change, effect rebuild,
	# the sink bus being re-created) hands out new effect instances, and a cached one keeps
	# answering zero forever instead of reporting that it went stale.
	if _use_raw_mic:
		_try_bind_raw_mic_spectrum()
	else:
		_try_bind_spectrum()
	if _active_spectrum() == null:
		return
	var raw_bands := PackedFloat32Array()
	raw_bands.resize(BAND_COUNT)
	var peak_raw := 0.0
	for i in BAND_COUNT:
		var from_hz := BAND_EDGES_HZ[i]
		var to_hz := BAND_EDGES_HZ[i + 1]
		var avg_v := _query_magnitude(from_hz, to_hz, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE)
		var max_v := _query_magnitude(from_hz, to_hz, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX)
		# AVERAGE-heavy: sustained music notes, not spoken consonants (MAX peaks).
		var value := max_v * 0.32 + avg_v * 0.68
		var w := BAND_WEIGHTS[i] if i < BAND_WEIGHTS.size() else 1.0
		raw_bands[i] = value * w
		peak_raw = maxf(peak_raw, raw_bands[i])

	raw_bands = _smooth_raw_bands(raw_bands)
	_debug_raw_bands = raw_bands.duplicate()
	raw_bands = _subtract_band_noise(raw_bands)
	peak_raw = 0.0
	for i in BAND_COUNT:
		peak_raw = maxf(peak_raw, raw_bands[i])

	# Tracked on its own rather than reusing _band_noise: those values carry BAND_WEIGHTS,
	# and subtracting them from an unweighted magnitude removed the kick entirely.
	var kick_mag := _query_magnitude(KICK_HZ_LO, KICK_HZ_HI, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX)
	if kick_mag > 0.0:
		if _kick_noise <= 0.0:
			_kick_noise = kick_mag
		elif kick_mag < _kick_noise:
			_kick_noise = lerpf(_kick_noise, kick_mag, NOISE_FALL)
		else:
			_kick_noise = lerpf(_kick_noise, kick_mag, NOISE_RISE)
	# Only the floor is removed here, with no oversubtraction: the onset detector below works
	# on the rise, and this band is continuously energised by the bassline, so taking out
	# more than the floor cancels the transient that is the whole point.
	var kick_raw := maxf(kick_mag - _kick_noise, 0.0) * 2.2

	_hold_timer = 0.0
	var raw_silence := _raw_silence_threshold()
	# Bands are already noise-subtracted, so the bar scales with whatever the room floor
	# turned out to be. Steady hiss lands at ~0 and cannot peak-normalize into a fake EQ,
	# while quiet music through the speakers still clears it.
	# Measured: with nothing playing, whatever survives subtraction lands at roughly the
	# learned noise level itself, while music lands several times above it. So the bar has
	# to scale with the room rather than sit at a fixed number tuned for a different mic.
	var noise_ref := _max_range(_band_noise, 0, BAND_COUNT - 1)
	var present_floor := maxf(UI_PEAK_ABS_FLOOR * 0.85, maxf(raw_silence * 0.28, noise_ref * PRESENT_NOISE_K))
	if _was_present:
		present_floor *= PRESENT_RELEASE
	# The PCM term is scaled to the room too. Left at a fixed threshold it overrode the
	# band decision and reported signal whenever the room was merely not silent.
	var pcm_bar := maxf(PCM_ALIVE, _pcm_noise * 0.9)
	var music_present := peak_raw >= present_floor or _pcm_signal > pcm_bar or kick_raw > present_floor * 0.5
	_was_present = music_present
	_debug_clean_peak = peak_raw
	_debug_present_floor = present_floor
	if not music_present:
		_update_agc(0.0)
		_fill_ui_bands(raw_bands, peak_raw, true)
		_zero_driver_bands()
		_tick_kick_gate(0.0, 0.0, peak_raw)
		_beat_env = 0.0
		_beat_hold = 0.0
		_volume_drive = 0.0
		_pcm_loud_ema = lerpf(_pcm_loud_ema, 0.0, 0.22)
		_decay_averages()
		_note_signal_or_silence(0.0, peak_raw)
		_publish_drives(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false)
		return

	_update_agc(maxf(peak_raw, kick_raw * 2.2))
	_fill_ui_bands(raw_bands, peak_raw, false)
	var gain := _effective_gain()
	var kick_gated := maxf(kick_raw * gain, 0.0)
	var pcm_term := _pcm_signal * gain * 0.055
	_pcm_loud_ema = lerpf(_pcm_loud_ema, pcm_term, 0.28)
	# Same 0–1 bins as the Graphic EQ, grouped to what a laptop mic can actually pick up.
	# Bass starts at 125 Hz: below that is rumble the capture high-pass removes, and the
	# laptop speakers put out nothing usable there either.
	var bass := _group_from_ui(3, 5)
	var mids := _group_from_ui(5, 9)
	var highs := _group_from_ui(10, 15)
	var energy := _shape_ui_drive(_average_range(ui_bands, 0, 15))
	var peak_n := _shape_ui_drive(_max_range(ui_bands, 0, 15))
	var volume := maxf(energy, _to_drive(_pcm_loud_ema))
	_decay_averages()
	if _driver_bands.size() != BAND_COUNT:
		_driver_bands.resize(BAND_COUNT)
	for i in BAND_COUNT:
		_driver_bands[i] = _shape_ui_drive(ui_bands[i])
	var onset := _tick_kick_gate(kick_raw, kick_gated, peak_raw)
	_volume_drive = volume
	_note_signal_or_silence(volume, peak_raw)
	_publish_drives(bass, mids, highs, energy, peak_n, volume, onset)


func _fill_ui_bands(raw_bands: PackedFloat32Array, peak_raw: float, silent: bool) -> void:
	## Graphic EQ + driver source. Flatten on true silence so peak-normalize cannot paint hiss.
	if ui_bands.size() != BAND_COUNT:
		ui_bands.resize(BAND_COUNT)
	# Caller already decided silence. Do not re-gate on a speech-sized raw floor —
	# kick/bass-only music is quieter in FFT units than spoken consonants.
	# Also flatten when the peak is hiss-sized — peak-normalize would paint BAND_WEIGHTS.
	if silent or peak_raw < UI_PEAK_ABS_FLOOR * 0.2:
		for i in BAND_COUNT:
			ui_bands[i] = lerpf(ui_bands[i], 0.0, 0.48)
			if ui_bands[i] < 0.02:
				ui_bands[i] = 0.0
		_driver_peak_ema = lerpf(_driver_peak_ema, 0.0, 0.28)
		if _driver_peak_ema < 1e-6:
			_driver_peak_ema = 0.0
		return
	var disp_scale := _update_display_peak(peak_raw)
	for i in BAND_COUNT:
		var nv := 0.0
		if disp_scale > 0.0:
			nv = clampf(raw_bands[i] * disp_scale, 0.0, 1.0)
		ui_bands[i] = nv


func _subtract_band_noise(raw_bands: PackedFloat32Array) -> PackedFloat32Array:
	## Learn the room's steady floor per band and take it out. A mic in raw mode has no
	## noise suppression, so without this the fan/hiss would peak-normalize into a full
	## Graphic EQ while nothing is playing. The floor only creeps upward while nothing is
	## present, so a long sustained track can never be learned as background.
	if _band_noise.size() != BAND_COUNT:
		_band_noise.resize(BAND_COUNT)
	var out := PackedFloat32Array()
	out.resize(BAND_COUNT)
	for i in BAND_COUNT:
		var v := raw_bands[i]
		var n := _band_noise[i]
		# A dropped FFT read is not a measurement of the room. Letting a zero through here
		# collapses the estimate, and then every later frame looks like signal forever.
		if v > 0.0:
			if n <= 0.0:
				n = v
			elif v < n:
				n = lerpf(n, v, NOISE_FALL)
			else:
				n = lerpf(n, v, NOISE_RISE)
			_band_noise[i] = n
		out[i] = maxf(v - n * NOISE_SUB_K, 0.0)
	return out


func _update_pcm_noise() -> void:
	## Same idea as the per-band floor, for the raw PCM level that feeds volume and onsets.
	if _pcm_rms > 0.0:
		if _pcm_noise <= 0.0:
			_pcm_noise = _pcm_rms
		elif _pcm_rms < _pcm_noise:
			_pcm_noise = lerpf(_pcm_noise, _pcm_rms, NOISE_FALL)
		else:
			_pcm_noise = lerpf(_pcm_noise, _pcm_rms, NOISE_RISE)
	_pcm_signal = maxf(_pcm_rms - _pcm_noise * NOISE_SUB_K, 0.0)


func _zero_driver_bands() -> void:
	if _driver_bands.size() != BAND_COUNT:
		_driver_bands.resize(BAND_COUNT)
	_driver_bands.fill(0.0)


func _publish_drives(bass: float, mids: float, highs: float, energy: float, peak_n: float, input_level: float, beat: bool) -> void:
	var kick_out := _kick_output()
	_beat_flag = beat or _beat_env > 0.25
	current_state.bands = ui_bands
	current_state.energy = energy
	current_state.peak = peak_n
	current_state.input_level = input_level
	current_state.beat = _beat_flag
	current_state.bass = bass
	current_state.mids = mids
	current_state.highs = highs
	current_state.kick = kick_out
	state_updated.emit(current_state)


func _kick_output() -> float:
	## Binary gate scaled by Master Intensity (default 2 → 0 or 1).
	return clampf(_kick_env * clampf(master_intensity * 0.5, 0.0, 1.0), 0.0, 1.0)


func _raw_silence_threshold() -> float:
	## Slightly below the old speech-sized floor so quiet music through speakers still drives.
	return 0.00012 + maxf(noise_floor, 0.0) * 0.040


func _update_band_avg(avg: float, raw: float) -> float:
	if raw <= 0.0:
		return lerpf(avg, 0.0, 0.1)
	return lerpf(avg, raw, 0.07)


func _decay_averages() -> void:
	_bass_avg = lerpf(_bass_avg, 0.0, 0.1)
	_mids_avg = lerpf(_mids_avg, 0.0, 0.1)
	_highs_avg = lerpf(_highs_avg, 0.0, 0.1)
	_energy_avg = lerpf(_energy_avg, 0.0, 0.1)


func _band_drive(raw: float, avg: float) -> float:
	## Music loudness first. Contrast only lifts drops/hits — speech plosives used to win here.
	if raw <= 0.0:
		return 0.0
	var floor_avg := maxf(avg, 0.012)
	var contrast := maxf(raw / floor_avg - 0.70, 0.0)
	var sens := maxf(band_sensitivity, 0.15)
	var mixed := raw * (0.62 + sens * 0.12) + contrast * 0.22
	return _to_drive(mixed)


func _group_from_ui(from_idx: int, to_idx: int) -> float:
	## Max-weighted so empty sub-bins do not dilute a laptop-mic bass group.
	var mx := _max_range(ui_bands, from_idx, to_idx)
	var avg := _average_range(ui_bands, from_idx, to_idx)
	return _shape_ui_drive(mx * 0.78 + avg * 0.22)


func _shape_ui_drive(v: float) -> float:
	## Map the same 0–1 EQ bins through Master Intensity / Band Sensitivity.
	if v <= 0.02:
		return 0.0
	var sens := maxf(band_sensitivity, 0.15)
	var gamma := clampf(1.20 / (0.45 + sens * 0.42), 0.38, 1.20)
	var shaped := pow(v, gamma)
	var inten := clampf(master_intensity * 0.5, 0.0, 2.0)
	return clampf(shaped * inten, 0.0, 1.0)


func _tick_kick_gate(kick_raw: float, kick_gated: float, peak_raw: float) -> bool:
	## Kick = 40–130 Hz transient. Beat = that OR a broadband onset (claps / snare /
	## speech plosives / speaker music on a talk-mic with no real sub).
	var dt := get_process_delta_time()
	var sens := maxf(band_sensitivity, 0.15)

	var level := kick_gated
	var flux := maxf(level - _prev_low, 0.0)
	_prev_low = level
	if level > 1e-8:
		_flux_ema = lerpf(_flux_ema, flux, 0.12)
	else:
		_flux_ema = lerpf(_flux_ema, 0.0, 0.22)
	var kick_thresh := maxf(_flux_ema * (1.55 / sens), 0.00045)
	var kick_loud := level > 0.008 or kick_raw > 8.0e-5
	var kick_onset := flux > kick_thresh and kick_loud

	var bb := maxf(peak_raw * _effective_gain(), _pcm_signal * 14.0)
	var bb_flux := maxf(bb - _prev_bb, 0.0)
	_prev_bb = bb
	if bb > 1e-6:
		_bb_flux_ema = lerpf(_bb_flux_ema, bb_flux, 0.12)
	else:
		_bb_flux_ema = lerpf(_bb_flux_ema, 0.0, 0.22)
	var bb_thresh := maxf(_bb_flux_ema * (1.45 / sens), 0.012)
	var bb_loud := bb > 0.045 or _pcm_signal > 0.008
	var bb_onset := bb_flux > bb_thresh and bb_loud and bb_flux > bb * 0.12

	if kick_onset:
		_kick_hold = 0.10
		_kick_env = 1.0
	elif _kick_hold > 0.0:
		_kick_hold = maxf(_kick_hold - dt, 0.0)
		_kick_env = 1.0
	else:
		_kick_env = 0.0

	var now := Time.get_ticks_msec() / 1000.0
	if (kick_onset or bb_onset) and (now - _last_beat_time) > 0.14:
		_last_beat_time = now
		_beat_hold = 0.16
		_beat_env = 1.0
	elif _beat_hold > 0.0:
		_beat_hold = maxf(_beat_hold - dt, 0.0)
		_beat_env = 1.0
	else:
		_beat_env = lerpf(_beat_env, 0.0, 0.42)
		if _beat_env < 0.04:
			_beat_env = 0.0
	return _beat_env > 0.35


func _update_display_peak(peak_raw: float) -> float:
	## Fast attack / slow decay follower. Returns 1/ema, or 0 when fully silent.
	## Never divide by a hiss-sized ema — that is the fake full-scale EQ.
	if peak_raw < UI_PEAK_ABS_FLOOR * 0.2:
		_driver_peak_ema = lerpf(_driver_peak_ema, 0.0, 0.22)
		if _driver_peak_ema < 1e-6:
			_driver_peak_ema = 0.0
			return 0.0
		return 1.0 / maxf(_driver_peak_ema, UI_PEAK_ABS_FLOOR)
	if peak_raw > 1e-8:
		if peak_raw > _driver_peak_ema:
			_driver_peak_ema = lerpf(_driver_peak_ema, peak_raw, 0.4)
		else:
			_driver_peak_ema = lerpf(_driver_peak_ema, peak_raw, 0.02)
		_driver_peak_ema = maxf(maxf(_driver_peak_ema, peak_raw * 0.9), UI_PEAK_ABS_FLOOR)
		return 1.0 / _driver_peak_ema
	_driver_peak_ema = lerpf(_driver_peak_ema, 0.0, 0.12)
	if _driver_peak_ema < 1e-6:
		_driver_peak_ema = 0.0
		return 0.0
	return 1.0 / maxf(_driver_peak_ema, UI_PEAK_ABS_FLOOR)


func _update_agc(peak_raw: float) -> void:
	if not agc_enabled:
		_agc_gain = 40.0
		return
	var raw_silence := _raw_silence_threshold()
	# Do not climb into the noise floor — that is the phantom-volume path.
	if peak_raw < raw_silence * 1.5:
		_agc_gain = lerpf(_agc_gain, 28.0, 0.03)
		return
	if peak_raw > 1e-7:
		var target := 0.50 / peak_raw
		target = clampf(target, 6.0, 90.0)
		# Slow AGC — music levels stay put; speech pauses used to crank gain then slam.
		var rate := 0.022 if peak_raw * _agc_gain > 0.08 else 0.045
		_agc_gain = lerpf(_agc_gain, target, rate)
	else:
		_agc_gain = lerpf(_agc_gain, 28.0, 0.03)


func _effective_gain() -> float:
	## Sensitivity is applied in _band_drive / _to_drive, not again here.
	return _agc_gain


func _apply_noise_gate(raw_bands: PackedFloat32Array, mean_raw: float, peak_raw: float) -> Dictionary:
	var gain := _effective_gain()
	var scaled_peak := peak_raw * gain
	var raw_silence := _raw_silence_threshold()
	if peak_raw < raw_silence * 1.6:
		_noise_ema = lerpf(_noise_ema, scaled_peak, 0.06)
	else:
		# Real signal — leak the hiss estimate down so a loud room doesn't lock the gate.
		var floor_target := minf(_noise_ema, scaled_peak * 0.18)
		_noise_ema = lerpf(_noise_ema, floor_target, 0.05)
	var floor_thresh := maxf(noise_floor * 1.6, _noise_ema * 1.35 + 0.006)
	# Never gate away a clearly present peak (that was the chop / visualizer-die path).
	if scaled_peak > 0.0:
		floor_thresh = minf(floor_thresh, scaled_peak * 0.42)

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
	# Music splits: bass 32–200, mids 200–3150, highs 3.15–20 kHz. Kick uses MAX of 0–2.
	var bass := _average_range(out, 0, 3) * 0.55 + _max_range(out, 0, 2) * 0.45
	var mids := _average_range(out, 4, 9)
	var highs := _average_range(out, 10, BAND_COUNT - 1) * 0.65 + _max_range(out, 12, 15) * 0.35
	return {
		"bands": out,
		"bass": bass,
		"mids": mids,
		"highs": highs,
		"energy": energy,
		"peak": peak,
		"mean_raw": mean_raw,
	}


func _to_drive(gated_raw: float) -> float:
	## Linear-ish 0..1 so Master Intensity / Band Sensitivity stay obvious.
	if gated_raw <= 0.0:
		return 0.0
	var sens := maxf(band_sensitivity, 0.15)
	var v := gated_raw * maxf(master_intensity, 0.05) * (0.32 + sens * 0.22)
	return clampf(pow(v, 0.82), 0.0, 1.0)


func _query_magnitude(from_hz: float, to_hz: float, mode: int) -> float:
	var spec := _active_spectrum()
	if spec == null:
		return 0.0
	var mag: Vector2 = spec.get_magnitude_for_frequency_range(from_hz, to_hz, mode)
	return (absf(mag.x) + absf(mag.y)) * 0.5


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
	## Same 0–1 bins as the Graphic EQ, shaped by intensity/sensitivity. Beat is a held pulse.
	if _driver_bands.size() != BAND_COUNT:
		_driver_bands.resize(BAND_COUNT)
	return {
		"bass": current_state.bass,
		"mids": current_state.mids,
		"highs": current_state.highs,
		"energy": current_state.energy,
		"peak": current_state.peak,
		"volume": _volume_drive,
		"kick": _kick_output(),
		"beat": clampf(_beat_env, 0.0, 1.0),
		"bands": _driver_bands,
	}


func _max_range(bands: PackedFloat32Array, from_idx: int, to_idx: int) -> float:
	var peak := 0.0
	for i in range(from_idx, mini(to_idx + 1, bands.size())):
		peak = maxf(peak, bands[i])
	return peak


func get_state() -> AudioState:
	return current_state.duplicate_state()


func play_master_tone(duration: float = 1.2, hz: float = 110.0) -> void:
	## Audible on speakers (analysis-bus tones cannot).
	var rate := 48000
	var n: int = maxi(int(float(rate) * duration), 1024)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var s := sin(TAU * hz * float(i) / float(rate))
		var v := int(clampf(s * 0.45, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	var existing := get_node_or_null("MasterTone")
	if existing:
		existing.queue_free()
	var player := AudioStreamPlayer.new()
	player.name = "MasterTone"
	player.bus = &"Master"
	player.stream = wav
	player.volume_db = 0.0
	add_child(player)
	player.play()
	var clearer := get_tree().create_timer(duration + 0.1)
	clearer.timeout.connect(player.queue_free)


func play_verify_tone(duration: float = 0.7, hz: float = 440.0) -> void:
	## Inject a short sine into the analysis bus (not speakers) to prove FFT is alive.
	var rate := 48000
	var n: int = maxi(int(float(rate) * duration), 1024)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var s := sin(TAU * hz * float(i) / float(rate))
		var v := int(clampf(s * 0.35, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	var existing := get_node_or_null("VerifyTone")
	if existing:
		existing.queue_free()
	var player := AudioStreamPlayer.new()
	player.name = "VerifyTone"
	player.bus = BUS_NAME
	player.stream = wav
	player.volume_db = 0.0
	add_child(player)
	player.play()
	var clearer := get_tree().create_timer(duration + 0.1)
	clearer.timeout.connect(player.queue_free)


func _set_listening_status() -> void:
	if _selected_source == SOURCE_MUSIC:
		# Says "voice" only when the raw helper is not delivering and we had to fall back,
		# so the one status line always matches what is actually being analysed.
		_set_status("Microphone (music)" if _use_raw_mic else "Microphone (voice)")
		return
	_set_status("Microphone (voice)")


func _tick_pcm_capture(delta: float) -> float:
	if _capture_fx == null:
		return 0.0
	var avail := _capture_fx.get_frames_available()
	if avail <= 0:
		# Hold the last level. A frame with nothing buffered yet is a dropped read, not
		# silence, and reporting 0 here poisons the noise-floor estimate.
		_no_frames_timer += delta
		return _pcm_rms
	_no_frames_timer = 0.0
	var take := mini(avail, 8192)
	if not _capture_fx.can_get_buffer(take):
		return _pcm_rms
	var frames: PackedVector2Array = _capture_fx.get_buffer(take)
	var leftover := _capture_fx.get_frames_available()
	if leftover > 0 and _capture_fx.can_get_buffer(leftover):
		_capture_fx.get_buffer(leftover)
	var count := frames.size()
	if count <= 0:
		return 0.0
	var acc := 0.0
	for f in frames:
		var s := (absf(f.x) + absf(f.y)) * 0.5
		acc += s * s
	return sqrt(acc / float(count))


func _tick_raw_mic_pcm(delta: float) -> float:
	if _raw_mic_capture_fx == null:
		return 0.0
	var avail := _raw_mic_capture_fx.get_frames_available()
	if avail <= 0:
		_raw_mic_no_frames += delta
		return _raw_mic_pcm
	_raw_mic_no_frames = 0.0
	var take := mini(avail, 8192)
	if not _raw_mic_capture_fx.can_get_buffer(take):
		return _raw_mic_pcm
	var frames: PackedVector2Array = _raw_mic_capture_fx.get_buffer(take)
	var leftover := _raw_mic_capture_fx.get_frames_available()
	if leftover > 0 and _raw_mic_capture_fx.can_get_buffer(leftover):
		_raw_mic_capture_fx.get_buffer(leftover)
	var count := frames.size()
	if count <= 0:
		return 0.0
	var acc := 0.0
	for f in frames:
		var s := (absf(f.x) + absf(f.y)) * 0.5
		acc += s * s
	return sqrt(acc / float(count))


func _smooth_raw_bands(raw_bands: PackedFloat32Array) -> PackedFloat32Array:
	if _smooth_bands.size() != BAND_COUNT:
		_smooth_bands = raw_bands.duplicate()
		return _smooth_bands
	for i in BAND_COUNT:
		var src := raw_bands[i]
		var prev := _smooth_bands[i]
		# Faster attack on kick/bass so drums punch; slower on speech mids.
		var attack := 0.62 if i <= 3 else (0.38 if i <= 9 else 0.50)
		var rate := attack if src >= prev else 0.18
		_smooth_bands[i] = lerpf(prev, src, rate)
	return _smooth_bands


func _hold_or_silence(delta: float) -> void:
	_hold_timer += delta
	if _hold_timer < HOLD_LAST_SEC and _had_signal:
		state_updated.emit(current_state)
		return
	_emit_silence()


func _rebuild_analysis_effects() -> void:
	_setup_audio_bus()
	_try_bind_spectrum()


func _rebuild_raw_mic_effects() -> void:
	_setup_raw_mic_bus()
	if _raw_mic != null and is_instance_valid(_raw_mic) and _raw_mic.has_method("start_on_bus"):
		_raw_mic.start_on_bus(RAW_MIC_BUS_NAME)
	_try_bind_raw_mic_spectrum()


func _force_capture_restart(reason: String) -> void:
	_silence_timer = 0.0
	_no_frames_timer = 0.0
	_stall_restarts += 1
	_set_status(reason)
	_soft_restart_capture(true)
	_rebuild_analysis_effects()
	_soft_reconnect_lock = _reconnect_backoff
	_reconnect_backoff = minf(_reconnect_backoff * 1.5, MAX_RECONNECT_BACKOFF)


func _compose_device_list() -> PackedStringArray:
	var out := PackedStringArray()
	for d in AudioServer.get_input_device_list():
		out.append(String(d))
	return out
