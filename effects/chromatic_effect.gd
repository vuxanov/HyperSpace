extends EffectLayer
class_name ChromaticEffect

## Screen-space chromatic aberration post-process.

var _rect: ColorRect


func _ready() -> void:
	effect_id = "chromatic"
	layer = 7
	_rect = _make_screen_color_rect("res://effects/chromatic_effect.gdshader")
	var mat := _mat()
	if mat:
		mat.set_shader_parameter("intensity", 0.85)
		mat.set_shader_parameter("amount", 1.0)
	visible = false


func set_active(is_on: bool) -> void:
	enabled = is_on
	visible = is_on
	if _rect:
		_rect.visible = is_on


func apply_params(params: Dictionary) -> void:
	super.apply_params(params)
	_apply_shader(params)
	visible = enabled


func apply_audio_state(state: AudioState) -> void:
	if not enabled:
		visible = false
		return
	visible = true
	var mat := _mat()
	if mat:
		mat.set_shader_parameter("audio_drive", state.highs * _intensity)


func apply_modulator(mod01: float) -> void:
	if not enabled:
		return
	var mat := _mat()
	if mat:
		mat.set_shader_parameter("amount", clampf(0.35 + mod01 * 0.7, 0.0, 1.0))


func _on_params_changed(params: Dictionary) -> void:
	_apply_shader(params)
	visible = enabled


func _apply_shader(params: Dictionary) -> void:
	var mat := _mat()
	if mat == null:
		return
	if params.has("intensity"):
		mat.set_shader_parameter("intensity", float(params["intensity"]))
	if params.has("amount"):
		mat.set_shader_parameter("amount", float(params["amount"]))


func _mat() -> ShaderMaterial:
	if _rect and _rect.material is ShaderMaterial:
		return _rect.material as ShaderMaterial
	return null
