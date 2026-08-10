extends CanvasLayer
class_name EffectLayer

## Base class for stackable post-process / overlay effects.

@export var effect_id: String = ""
@export var enabled: bool = false
@export var audio_band: int = 0  # which band drives this effect (0=bass-heavy)

var _intensity: float = 1.0


func _make_screen_color_rect(shader_path: String) -> ColorRect:
	## BackBufferCopy must draw before the ColorRect so hint_screen_texture is valid.
	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(bbc)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color(1, 1, 1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	rect.material = mat
	add_child(rect)
	return rect


func apply_params(params: Dictionary) -> void:
	if params.has("intensity"):
		_intensity = float(params["intensity"])
	if params.has("enabled"):
		enabled = bool(params["enabled"])
	_on_params_changed(params)


func apply_modulator(_mod01: float) -> void:
	pass


func apply_audio_state(_state: AudioState) -> void:
	pass


func _on_params_changed(_params: Dictionary) -> void:
	pass
