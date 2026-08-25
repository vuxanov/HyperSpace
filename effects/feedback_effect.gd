extends EffectLayer
class_name FeedbackEffect

## Color trail overlay drawn after ASCII. History is previous output; black
## glyph gaps are alpha-gated so they cannot darken the live image.

var _rect: ColorRect
var _history: ImageTexture
var _has_history: bool = false
var _capture_pending: bool = false
var _base_mix: float = 0.78
var _base_opacity: float = 0.7
var _base_persist: float = 0.9
var _base_zoom: float = 1.04
var _base_blur: float = 0.35
var _base_blend: int = 0
var _frame_skip: int = 0
## Plain-language blend names, same order as the shader's BLEND_* constants.
const BLEND_NAMES := ["Normal", "Glow", "Brightest", "Darkest", "Shadow", "Edges", "Contrast"]
const CAPTURE_EVERY_N := 2
const CAPTURE_MAX_DIM := 640
## A near-zero Blur means "crisp duplicate", so the history has to keep real detail.
const CAPTURE_MAX_DIM_SHARP := 1280
const SHARP_BLUR_MAX := 0.06


func _ready() -> void:
	effect_id = "feedback"
	# After ASCII (10) so trails sit on top. Do not BackBufferCopy here:
	# ASCII's copy leaves screen_texture as the pre-ASCII color scene.
	layer = 12
	set_process(false)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color(1, 1, 1, 0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://effects/feedback_effect.gdshader")
	mat.set_shader_parameter("mix_amount", _base_mix)
	mat.set_shader_parameter("opacity", _base_opacity)
	mat.set_shader_parameter("persistence", _base_persist)
	mat.set_shader_parameter("zoom", _base_zoom)
	mat.set_shader_parameter("blur", _base_blur)
	mat.set_shader_parameter("blend_mode", _base_blend)
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


func _on_frame_post_draw() -> void:
	if not enabled or not is_inside_tree() or _capture_pending:
		return
	_frame_skip += 1
	if _frame_skip < CAPTURE_EVERY_N:
		return
	_frame_skip = 0
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
	if img == null or img.is_empty():
		return
	var w := img.get_width()
	var h := img.get_height()
	var m := maxi(w, h)
	var cap := CAPTURE_MAX_DIM_SHARP if _base_blur <= SHARP_BLUR_MAX else CAPTURE_MAX_DIM
	if m > cap:
		var sc := float(cap) / float(m)
		img.resize(maxi(1, int(w * sc)), maxi(1, int(h * sc)), Image.INTERPOLATE_BILINEAR)
	# filter_linear_mipmap only has levels to read if the image carries them; without this
	# the shader's Blur LOD silently collapses to level 0.
	img.generate_mipmaps()
	if _history == null:
		_history = ImageTexture.create_from_image(img)
	else:
		var prev := Vector2i(_history.get_size())
		var cur := img.get_size()
		if prev != cur:
			_history.set_image(img)
		else:
			_history.update(img)
	_has_history = true
	var mat := _mat()
	if mat:
		mat.set_shader_parameter("history_tex", _history)
		mat.set_shader_parameter("has_history", 1.0)


func _on_params_changed(_params: Dictionary) -> void:
	_apply_resolved()
	visible = enabled


func _apply_resolved() -> void:
	var mat := _mat()
	if mat == null:
		return
	_base_persist = eval_num("persistence", _base_persist)
	_base_zoom = eval_num("zoom", _base_zoom)
	_base_mix = eval_num("mix_amount", _base_mix)
	_base_blur = clampf(eval_num("blur", _base_blur, 0.0, 1.0), 0.0, 1.0)
	if has_raw_param("opacity"):
		_base_opacity = eval_num("opacity", _base_opacity)
	else:
		_base_opacity = _base_mix
	mat.set_shader_parameter("persistence", clampf(_base_persist, 0.0, 1.0))
	mat.set_shader_parameter("zoom", _base_zoom)
	mat.set_shader_parameter("mix_amount", clampf(_base_mix, 0.0, 1.0))
	mat.set_shader_parameter("opacity", clampf(_base_opacity, 0.0, 1.0))
	mat.set_shader_parameter("blur", _base_blur)
	mat.set_shader_parameter("blend_mode", _resolve_blend())
	mat.set_shader_parameter("audio_drive", 0.0)


func _resolve_blend() -> int:
	## Discrete choice, so it is a name rather than a driven number. Presets written before
	## the selector existed have no "blend" key and stay on Normal.
	var raw: Variant = raw_param("blend", null)
	if raw is String:
		var idx := BLEND_NAMES.find(str(raw))
		if idx >= 0:
			_base_blend = idx
	elif raw is float or raw is int:
		_base_blend = clampi(int(raw), 0, BLEND_NAMES.size() - 1)
	return _base_blend


func _mat() -> ShaderMaterial:
	if _rect and _rect.material is ShaderMaterial:
		return _rect.material as ShaderMaterial
	return null
