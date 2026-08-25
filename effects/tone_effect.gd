extends EffectLayer
class_name ToneEffect

## Screen-space image tone: invert + brightness (lightness) + contrast + saturation.

var _rect: ColorRect
var _base_invert: float = 0.0
var _base_brightness: float = 1.0
var _base_contrast: float = 1.0
var _base_saturation: float = 1.0


func _ready() -> void:
	effect_id = "tone"
	# Before chromatic (7) / glitch (8) so those read the toned image.
	layer = 6
	_rect = _make_screen_color_rect("res://effects/tone_effect.gdshader")
	_apply_display()
	visible = false
	set_process(false)


func set_active(is_on: bool) -> void:
	enabled = is_on
	visible = is_on
	if _rect:
		_rect.visible = is_on


func apply_params(params: Dictionary) -> void:
	super.apply_params(params)
	_apply_resolved()
	visible = enabled


func apply_audio_state(_state: AudioState) -> void:
	if not enabled:
		visible = false
		return
	visible = true
	_apply_resolved()


func apply_modulator(_mod01: float) -> void:
	pass


func _on_params_changed(_params: Dictionary) -> void:
	_apply_resolved()
	visible = enabled


func _apply_resolved() -> void:
	_base_invert = eval_num("invert", _base_invert, 0.0, 1.0)
	_base_brightness = eval_num("brightness", _base_brightness, 0.0, 4.0)
	_base_contrast = eval_num("contrast", _base_contrast, 0.0, 4.0)
	_base_saturation = eval_num("saturation", _base_saturation, 0.0, 3.0)
	_apply_display()


func _apply_display() -> void:
	var mat := _mat()
	if mat == null or mat.shader == null:
		return
	mat.set_shader_parameter("invert_amount", clampf(_base_invert, 0.0, 1.0))
	mat.set_shader_parameter("brightness", clampf(_base_brightness, 0.0, 4.0))
	mat.set_shader_parameter("contrast", clampf(_base_contrast, 0.0, 4.0))
	mat.set_shader_parameter("saturation", clampf(_base_saturation, 0.0, 3.0))


func _mat() -> ShaderMaterial:
	if _rect and _rect.material is ShaderMaterial:
		return _rect.material as ShaderMaterial
	return null
