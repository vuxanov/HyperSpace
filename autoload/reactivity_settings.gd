extends Node

## Global audio-reactivity routing — choosable drivers per property.

signal settings_changed

## Defaults: everything OFF on first open / new install (session may restore later).
var enabled: bool = false
var affect_scale: bool = false
var scale_x: bool = true
var scale_y: bool = true
var scale_z: bool = true
var affect_light: bool = false
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
## When true, Camera motion section also drives camera look via rotation amount/axes.
var affect_camera_rotation: bool = false
var scale_amount: float = 25.0
## World-unit displace strength (UI: Displace Strength).
var noise_amount: float = 28.0
## Spatial feature size of the deform noise (larger = bigger blobs). Not animation speed.
var noise_scale: float = 4.0
var noise_x: bool = true
var noise_y: bool = true
var noise_z: bool = true
## Multi-select "What reacts" layers (everything = all checked; default none).
var target_main: bool = false
var target_scatter: bool = false
var target_environment: bool = false
var target_lights: bool = false
## Particles affect (independent of global What reacts).
var particles_target_main: bool = false
var particles_target_scatter: bool = false
var particles_target_environment: bool = false
var particles_target_lights: bool = false
var particles_target_media: bool = false
## Noise displace affect (independent of global What reacts).
var noise_target_main: bool = false
var noise_target_scatter: bool = false
var noise_target_environment: bool = false
var noise_target_lights: bool = false
## Which layers reactive rotation influences (independent of global What reacts).
var rotation_target_main: bool = false
var rotation_target_scatter: bool = false
var rotation_target_environment: bool = false
var rotation_target_lights: bool = false
var rotation_target_camera: bool = false

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
	scale_amount = clampf(value, -1.0e6, 1.0e6)
	settings_changed.emit()


func set_rotation_amount(value: float) -> void:
	rotation_amount = clampf(value, -1.0e6, 1.0e6)
	settings_changed.emit()


func reset_to_defaults() -> void:
	## True factory defaults for Deform + reactivity (left Effects column).
	enabled = false
	affect_scale = false
	scale_x = true
	scale_y = true
	scale_z = true
	affect_light = false
	affect_emission = false
	affect_rotation = false
	rotation_x = true
	rotation_y = true
	rotation_z = true
	rotation_amount = 1.0
	affect_noise = false
	affect_camera_rotation = false
	scale_amount = 25.0
	noise_amount = 28.0
	noise_scale = 4.0
	noise_x = true
	noise_y = true
	noise_z = true
	target_main = false
	target_scatter = false
	target_environment = false
	target_lights = false
	particles_target_main = false
	particles_target_scatter = false
	particles_target_environment = false
	particles_target_lights = false
	particles_target_media = false
	noise_target_main = false
	noise_target_scatter = false
	noise_target_environment = false
	noise_target_lights = false
	rotation_target_main = false
	rotation_target_scatter = false
	rotation_target_environment = false
	rotation_target_lights = false
	rotation_target_camera = false
	scale_source = "bass"
	emission_source = "mids"
	rotation_source = "highs"
	light_source = "energy"
	noise_source = "bass"
	camera_preset = "Off"
	camera_rate = 1.0
	camera_depth = 0.55
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
