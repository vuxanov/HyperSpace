extends EffectLayer
class_name FeedbackEffect

## Real feedback trail via history texture captured from the output viewport.

var _rect: ColorRect
var _history: ImageTexture
var _has_history: bool = false
var _capture_pending: bool = false


func _ready() -> void:
	effect_id = "feedback"
	layer = 2
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://effects/feedback_effect.gdshader")
	mat.set_shader_parameter("mix_amount", 0.78)
	mat.set_shader_parameter("persistence", 0.9)
	mat.set_shader_parameter("has_history", 0.0)
	_rect.material = mat
	add_child(_rect)
	visible = false
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)


func set_active(is_on: bool) -> void:
	enabled = is_on
	visible = is_on
	if _rect:
		_rect.visible = is_on
	if not is_on:
		_has_history = false
		var mat := _mat()
		if mat:
			mat.set_shader_parameter("has_history", 0.0)


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
		mat.set_shader_parameter("mix_amount", clampf(0.72 + state.mids * 0.2, 0.65, 0.95))
		mat.set_shader_parameter("persistence", clampf(0.86 + state.bass * 0.08, 0.75, 0.96))


func apply_modulator(mod01: float) -> void:
	if not enabled:
		return
	var mat := _mat()
	if mat:
		mat.set_shader_parameter("zoom", 1.02 + mod01 * 0.06)


func _on_frame_post_draw() -> void:
	if not enabled or not is_inside_tree() or _capture_pending:
		return
	_capture_pending = true
	_capture_history()
	_capture_pending = false


func _capture_history() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vt := vp.get_texture()
	if vt == null:
		return
	var img := vt.get_image()
	if img == null:
		return
	if _history == null:
		_history = ImageTexture.create_from_image(img)
	else:
		_history.update(img)
	_has_history = true
	var mat := _mat()
	if mat:
		mat.set_shader_parameter("history_tex", _history)
		mat.set_shader_parameter("has_history", 1.0)


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
