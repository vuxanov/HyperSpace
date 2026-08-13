extends EffectLayer
class_name ChromaticEffect

## Screen-space chromatic aberration post-process.

var _rect: ColorRect
var _base_amount: float = 1.4
var _base_intensity: float = 1.1


func _ready() -> void:
	effect_id = "chromatic"
	layer = 7
	_rect = _make_screen_color_rect("res://effects/chromatic_effect.gdshader")
	var mat := _mat()
	if mat:
		mat.set_shader_parameter("intensity", _base_intensity)
		mat.set_shader_parameter("amount", _base_amount)
		mat.set_shader_parameter("audio_drive", 0.0)
	visible = false


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
	var mat := _mat()
	if mat == null:
		return
	_base_intensity = eval_num("intensity", _base_intensity, 0.0, 8.0)
	_base_amount = eval_num("amount", _base_amount, 0.0, 8.0)
	mat.set_shader_parameter("intensity", _base_intensity)
	mat.set_shader_parameter("amount", _base_amount)
	mat.set_shader_parameter("audio_drive", 0.0)


func _mat() -> ShaderMaterial:
	if _rect and _rect.material is ShaderMaterial:
		return _rect.material as ShaderMaterial
	return null
