extends Node

## Global audio-reactivity routing — choosable drivers per property.

signal settings_changed

var enabled: bool = true
var affect_scale: bool = true
var scale_x: bool = true
var scale_y: bool = true
var scale_z: bool = true
var affect_light: bool = true
## Off by default — emission drive washes authored textures on hero/scatter/env models.
var affect_emission: bool = false
## Off by default — rotation amount is easy to overdrive on hero / env meshes.
var affect_rotation: bool = false
var rotation_x: bool = true
var rotation_y: bool = true
var rotation_z: bool = true
## Peak spin strength (UI: Rotation Amount). Scales reactive angular rate.
var rotation_amount: float = 1.0
var affect_noise: bool = false
var scale_amount: float = 25.0
## World-unit displace strength (UI: Displace Strength).
var noise_amount: float = 28.0
## Spatial feature size of the deform noise (larger = bigger blobs). Not animation speed.
var noise_scale: float = 4.0
var noise_x: bool = true
var noise_y: bool = true
var noise_z: bool = true
var target: String = "all"  # centerpiece | scatter | environment | lights | all
var particles_target: String = "all"
var noise_target: String = "all"
## Which layers reactive rotation influences (independent of global target).
var rotation_target: String = "all"

## Per-property drivers: off | bass | mids | highs | kick | energy | lfo
var scale_source: String = "bass"
var emission_source: String = "mids"
var rotation_source: String = "highs"
var light_source: String = "energy"
var noise_source: String = "bass"

## Camera / shared LFO
var camera_preset: String = "Off"
var camera_rate: float = 1.0
var camera_depth: float = 0.55

## Live modulator value (0..1) written each frame
var lfo_mod01: float = 0.0

var _mod: ModulatorBus


func _ready() -> void:
	_mod = ModulatorBus.new()


func _process(delta: float) -> void:
	if _mod == null:
		_mod = ModulatorBus.new()
	_mod.set_preset_name(camera_preset)
	_mod.rate = camera_rate
	_mod.depth = camera_depth
	var kick := 0.0
	if AudioAnalyzer and AudioAnalyzer.current_state:
		kick = float(AudioAnalyzer.current_state.kick)
	_mod.advance(delta, kick)
	lfo_mod01 = _mod.mod01


func get_modulator() -> ModulatorBus:
	if _mod == null:
		_mod = ModulatorBus.new()
	return _mod


func set_lfo_mod01(value: float) -> void:
	lfo_mod01 = clampf(value, 0.0, 1.0)


func set_enabled(value: bool) -> void:
	enabled = value
	settings_changed.emit()


func set_scale_amount(value: float) -> void:
	scale_amount = maxf(value, 0.0)
	settings_changed.emit()


func set_rotation_amount(value: float) -> void:
	rotation_amount = maxf(value, 0.0)
	settings_changed.emit()


func notify_changed() -> void:
	settings_changed.emit()


func scale_vector(base: float) -> Vector3:
	var amount := base - 1.0
	return Vector3(
		1.0 + amount if scale_x else 1.0,
		1.0 + amount if scale_y else 1.0,
		1.0 + amount if scale_z else 1.0
	)


func rotation_axis_mask() -> Vector3:
	return Vector3(
		1.0 if rotation_x else 0.0,
		1.0 if rotation_y else 0.0,
		1.0 if rotation_z else 0.0
	)
