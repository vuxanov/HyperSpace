extends CanvasLayer
class_name EffectLayer

## Base class for stackable post-process / overlay effects.

@export var effect_id: String = ""
@export var enabled: bool = false
@export var audio_band: int = 0  # which band drives this effect (0=bass-heavy)

## audio | lfo | auto — how intensity is modulated each frame. Legacy "manual" == auto.
var drive_mode: String = "audio"
var _intensity: float = 1.0
var _last_lfo: float = 0.0
var _last_audio_drive: float = 0.0
## Extra 0..1 multiplier for audio drive (feedback / shared sensitivity).
var audio_sensitivity: float = 1.0


func _make_screen_color_rect(shader_path: String) -> ColorRect:
	## Reliable screen-read inside Output SubViewport:
	## BackBufferCopy (viewport) then ColorRect. Transparent rect so a failed
	## sample never paints opaque white over the scene.
	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(bbc)

	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Alpha 0: if the shader fails to bind, scene still shows through.
	rect.color = Color(1, 1, 1, 0)
	var mat := ShaderMaterial.new()
	var shader: Shader = load(shader_path) as Shader
	if shader:
		mat.shader = shader
	rect.material = mat
	add_child(rect)
	return rect


func normalize_drive_mode(mode: String) -> String:
	var m := mode.to_lower()
	if m == "manual":
		return "auto"
	return m


func apply_params(params: Dictionary) -> void:
	if params.has("intensity"):
		_intensity = float(params["intensity"])
	if params.has("enabled"):
		enabled = bool(params["enabled"])
	if params.has("drive_mode"):
		drive_mode = normalize_drive_mode(str(params["drive_mode"]))
	if params.has("audio_sensitivity"):
		audio_sensitivity = clampf(float(params["audio_sensitivity"]), 0.05, 4.0)
	_on_params_changed(params)


func apply_modulator(mod01: float) -> void:
	_last_lfo = clampf(mod01, 0.0, 1.0)


func apply_audio_state(_state: AudioState) -> void:
	pass


func resolve_drive(audio_value: float) -> float:
	## Shared Audio / LFO / Auto mapping (legacy "manual" accepted via normalize).
	var a := clampf(audio_value, 0.0, 1.0)
	a = clampf(pow(a, 0.55) * audio_sensitivity, 0.0, 1.0)
	var mode := normalize_drive_mode(drive_mode)
	match mode:
		"lfo":
			return clampf(_last_lfo * _intensity, 0.0, 3.0)
		"auto", "manual":
			return clampf(_intensity, 0.0, 3.0)
		_:
			# audio (default) — mild LFO bleed kept tiny so sensitivity stays meaningful
			return clampf(a * _intensity * 1.15 + _last_lfo * 0.04, 0.0, 3.0)


func _on_params_changed(_params: Dictionary) -> void:
	pass
