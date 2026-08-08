extends EffectLayer
class_name FeedbackEffect

## Screen-space feedback trail — works on any content (3D, video, image).

var _rect: ColorRect


func _ready() -> void:
	effect_id = "feedback"
	layer = 2
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://effects/feedback_effect.gdshader")
	_rect.material = mat
	add_child(_rect)
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
		mat.set_shader_parameter("audio_drive", state.energy * _intensity)
		mat.set_shader_parameter("mix_amount", clampf(0.45 + state.mids * 0.4, 0.2, 0.95))
		mat.set_shader_parameter("persistence", clampf(0.8 + state.bass * 0.12, 0.6, 0.96))


func _on_params_changed(params: Dictionary) -> void:
	_apply_shader(params)
	visible = enabled


func _apply_shader(params: Dictionary) -> void:
	var mat := _mat()
	if mat == null:
		return
	if params.has("persistence"):
		mat.set_shader_parameter("persistence", float(params["persistence"]))
	if params.has("zoom"):
		mat.set_shader_parameter("zoom", float(params["zoom"]))
	if params.has("mix_amount"):
		mat.set_shader_parameter("mix_amount", float(params["mix_amount"]))


func _mat() -> ShaderMaterial:
	if _rect and _rect.material is ShaderMaterial:
		return _rect.material as ShaderMaterial
	return null
