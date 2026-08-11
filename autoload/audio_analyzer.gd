extends Node

## Central audio analysis pipeline — FFT bands, energy, beat/onset detection.

signal state_updated(state: AudioState)

const BAND_COUNT := 16
const BEAT_DECAY := 0.98
const BEAT_THRESHOLD := 1.4

var current_state: AudioState = AudioState.new()
var master_intensity: float = 1.0
var band_sensitivity: float = 1.75

var _bus_index: int = -1
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _mic_player: AudioStreamPlayer
var _energy_history: float = 0.0
var _last_beat_time: float = 0.0
var _beat_intervals: Array[float] = []
var _kick_env: float = 0.0


func _ready() -> void:
	current_state.bands.resize(BAND_COUNT)
	_setup_audio_bus()
	_start_capture()


func _setup_audio_bus() -> void:
	var bus_name := "HyperSpaceAnalysis"
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		bus_name = "HyperSpaceAnalysis"
	_bus_index = AudioServer.get_bus_index(bus_name)
	if _bus_index == -1:
		_bus_index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_bus_index, "HyperSpaceAnalysis")
	# Clear existing effects on this bus
	while AudioServer.get_bus_effect_count(_bus_index) > 0:
		AudioServer.remove_bus_effect(_bus_index, 0)
	var spectrum := AudioEffectSpectrumAnalyzer.new()
	spectrum.buffer_length = 2.0
	spectrum.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
	AudioServer.add_bus_effect(_bus_index, spectrum)
	# Analyze only — never play mic/input through speakers.
	AudioServer.set_bus_mute(_bus_index, true)
	_spectrum = AudioServer.get_bus_effect_instance(_bus_index, 0) as AudioEffectSpectrumAnalyzerInstance


func _start_capture() -> void:
	_mic_player = AudioStreamPlayer.new()
	_mic_player.name = "MicCapture"
	_mic_player.bus = "HyperSpaceAnalysis"
	var mic := AudioStreamMicrophone.new()
	_mic_player.stream = mic
	add_child(_mic_player)
	_mic_player.play()


func set_input_bus(bus_name: String) -> void:
	if _mic_player:
		_mic_player.bus = bus_name


func _process(delta: float) -> void:
	_kick_env = maxf(_kick_env - delta * 4.0, 0.0)
	_analyze()


func _analyze() -> void:
	if _spectrum == null:
		return
	var bands := PackedFloat32Array()
	bands.resize(BAND_COUNT)
	var total_energy := 0.0
	var peak := 0.0
	var min_hz := 20.0
	var max_hz := 20000.0
	for i in BAND_COUNT:
		var t0 := float(i) / float(BAND_COUNT)
		var t1 := float(i + 1) / float(BAND_COUNT)
		var from_hz := min_hz * pow(max_hz / min_hz, t0)
		var to_hz := min_hz * pow(max_hz / min_hz, t1)
		var mag: Vector2 = _spectrum.get_magnitude_for_frequency_range(from_hz, to_hz)
		var value := mag.length() * band_sensitivity * master_intensity
		bands[i] = value
		total_energy += value
		peak = maxf(peak, value)
	total_energy /= float(BAND_COUNT)
	# Spectrum magnitudes are tiny — lift into a usable 0..1 envelope for UI + reactivity.
	var bass := _perceptual(_average_range(bands, 0, 3))
	var mids := _perceptual(_average_range(bands, 4, 9))
	var highs := _perceptual(_average_range(bands, 10, BAND_COUNT - 1))
	var energy := _perceptual(total_energy)
	var peak_n := _perceptual(peak)
	var beat := _detect_beat(energy)
	if beat:
		_kick_env = maxf(_kick_env, clampf(bass * 1.8 + energy, 0.45, 1.0))
	current_state.bands = bands
	current_state.energy = energy
	current_state.peak = peak_n
	current_state.beat = beat
	current_state.bass = bass
	current_state.mids = mids
	current_state.highs = highs
	current_state.kick = _kick_env
	current_state.bpm_estimate = _estimate_bpm()
	state_updated.emit(current_state)


func _perceptual(raw: float) -> float:
	## Map quiet mic/FFT levels into punchy 0..1 meters and drives.
	var v := maxf(raw, 0.0) * 14.0 * maxf(band_sensitivity, 0.15)
	return clampf(pow(v, 0.48), 0.0, 1.0)


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
			var interval := now - _last_beat_time
			if _last_beat_time > 0.0:
				_beat_intervals.append(interval)
				if _beat_intervals.size() > 8:
					_beat_intervals.pop_front()
			_last_beat_time = now
			return true
	return false


func _estimate_bpm() -> float:
	if _beat_intervals.is_empty():
		return 120.0
	var total := 0.0
	for interval in _beat_intervals:
		total += interval
	var avg := total / float(_beat_intervals.size())
	if avg <= 0.0:
		return 120.0
	return clampf(60.0 / avg, 60.0, 200.0)


func get_state() -> AudioState:
	return current_state.duplicate_state()
