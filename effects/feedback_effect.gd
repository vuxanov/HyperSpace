extends EffectLayer
class_name FeedbackEffect

## Real feedback trail via history texture captured from the output viewport.

var _rect: ColorRect
var _history: ImageTexture
var _has_history: bool = false
var _capture_pending: bool = false
var _base_mix: float = 0.78
var _base_persist: float = 0.9
var _base_zoom: float = 1.04


func _ready() -> void:
	effect_id = "feedback"
	layer = 2
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color(1, 1, 1, 0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://effects/feedback_effect.gdshader")
	mat.set_shader_parameter("mix_amount", _base_mix)
	mat.set_shader_parameter("persistence", _base_persist)
	mat.set_shader_parameter("zoom", _base_zoom)
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
	if mat == null:
		return
	match drive_mode:
		"auto", "manual":
			mat.set_shader_parameter("audio_drive", 0.0)
			mat.set_shader_parameter("mix_amount", _base_mix)
			mat.set_shader_parameter("persistence", _base_persist)
			mat.set_shader_parameter("zoom", _base_zoom)
		"lfo":
			var d := resolve_drive(0.0)
			mat.set_shader_parameter("audio_drive", d * 0.35)
			mat.set_shader_parameter("mix_amount", clampf(_base_mix * (0.85 + _last_lfo * 0.3), 0.05, 0.98))
			mat.set_shader_parameter("persistence", clampf(_base_persist * (0.9 + _last_lfo * 0.12), 0.5, 0.98))
			mat.set_shader_parameter("zoom", _base_zoom + _last_lfo * 0.06)
		_:
			# audio — sensitivity tames oversensitivity
			var drive := resolve_drive(state.energy)
			mat.set_shader_parameter("audio_drive", drive * 0.45)
			var boost := drive * 0.12 * audio_sensitivity
			mat.set_shader_parameter("mix_amount", clampf(_base_mix + boost, 0.05, 0.98))
			mat.set_shader_parameter("persistence", clampf(_base_persist + boost * 0.35, 0.5, 0.98))
			mat.set_shader_parameter("zoom", _base_zoom + drive * 0.03)


func apply_modulator(mod01: float) -> void:
	super.apply_modulator(mod01)
	if not enabled or normalize_drive_mode(drive_mode) != "lfo":
		return
	var mat := _mat()
	if mat:
		mat.set_shader_parameter("audio_drive", resolve_drive(0.0) * 0.35)
		mat.set_shader_parameter("mix_amount", clampf(_base_mix * (0.85 + mod01 * 0.3), 0.05, 0.98))
		mat.set_shader_parameter("persistence", clampf(_base_persist * (0.9 + mod01 * 0.12), 0.5, 0.98))
		mat.set_shader_parameter("zoom", _base_zoom + mod01 * 0.06)


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
		_base_persist = clampf(float(params["persistence"]), 0.5, 0.98)
		mat.set_shader_parameter("persistence", _base_persist)
	if params.has("zoom"):
		_base_zoom = float(params["zoom"])
		mat.set_shader_parameter("zoom", _base_zoom)
	if params.has("mix_amount"):
		_base_mix = clampf(float(params["mix_amount"]), 0.0, 1.0)
		mat.set_shader_parameter("mix_amount", _base_mix)


func _mat() -> ShaderMaterial:
	if _rect and _rect.material is ShaderMaterial:
		return _rect.material as ShaderMaterial
	return null
