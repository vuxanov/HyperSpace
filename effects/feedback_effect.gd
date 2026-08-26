extends EffectLayer
class_name FeedbackEffect

## Color trail overlay drawn after ASCII. Blur > 0: downsampled + mip-blurred
## history (smear). Blur 0: full-resolution 1:1 buffer, no extra blur pass.

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
const BLEND_NAMES := ["Normal", "Brightest", "Darkest", "Edges", "Contrast"]
## Old integer slots before Glow/Shadow were removed: Normal, Glow, Brightest,
## Darkest, Shadow, Edges, Contrast. Glow and Shadow collapse to Normal.
const LEGACY_BLEND_INDEX := [0, 0, 1, 2, 0, 3, 4]
const CAPTURE_EVERY_N := 2
const CAPTURE_MAX_DIM := 640
const SHARP_MAX_DIM := 1280
const SMEAR_ZOOM := 1.04
const SHARP_BLUR_MAX := 0.001


func _ready() -> void:
	effect_id = "feedback"
	# After ASCII (100) so trails sit on the final post-ASCII composite.
	# Own BackBufferCopy so screen_texture is that composite, not a pre-ASCII
	# / pre-FX buffer. Keep the layer mounted so the copy stays valid.
	layer = 110
	visible = true
	set_process(false)
	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(bbc)
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
	_rect.visible = false
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)


func set_active(is_on: bool) -> void:
	enabled = is_on
	visible = true
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
	visible = true
	if _rect:
		_rect.visible = enabled


func apply_audio_state(_state: AudioState) -> void:
	if not enabled:
		if _rect:
			_rect.visible = false
		return
	if _rect:
		_rect.visible = true
	_apply_resolved()


func apply_modulator(_mod01: float) -> void:
	pass


func _sharp() -> bool:
	return _base_blur <= SHARP_BLUR_MAX


func _on_frame_post_draw() -> void:
	if not enabled or not is_inside_tree() or _capture_pending:
		return
	if AsciiCharset.baking:
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
	if _sharp():
		if m > SHARP_MAX_DIM:
			var sc := float(SHARP_MAX_DIM) / float(m)
			img.resize(maxi(1, int(w * sc)), maxi(1, int(h * sc)), Image.INTERPOLATE_NEAREST)
	else:
		if m > CAPTURE_MAX_DIM:
			var sc2 := float(CAPTURE_MAX_DIM) / float(m)
			img.resize(maxi(1, int(w * sc2)), maxi(1, int(h * sc2)), Image.INTERPOLATE_BILINEAR)
		img.generate_mipmaps()
	_store_cpu_history(img)


func _store_cpu_history(img: Image) -> void:
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
	visible = true
	if _rect:
		_rect.visible = enabled


func _apply_resolved() -> void:
	var mat := _mat()
	if mat == null:
		return
	_base_persist = eval_num("persistence", _base_persist)
	_base_mix = eval_num("mix_amount", _base_mix)
	_base_blur = clampf(eval_num("blur", _base_blur, 0.0, 1.0), 0.0, 1.0)
	if has_raw_param("opacity"):
		_base_opacity = eval_num("opacity", _base_opacity)
	else:
		_base_opacity = _base_mix
	_base_zoom = 1.0 if _sharp() else SMEAR_ZOOM
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
	_base_blend = blend_index_from_param(raw_param("blend", null))
	return _base_blend


static func blend_index_from_param(raw: Variant) -> int:
	if raw is String:
		var s := str(raw)
		if s == "Glow" or s == "Shadow":
			return 0
		var idx := BLEND_NAMES.find(s)
		return idx if idx >= 0 else 0
	if raw is float or raw is int:
		var old := int(raw)
		if old >= 0 and old < LEGACY_BLEND_INDEX.size():
			return int(LEGACY_BLEND_INDEX[old])
		return clampi(old, 0, BLEND_NAMES.size() - 1)
	return 0


func _mat() -> ShaderMaterial:
	if _rect and _rect.material is ShaderMaterial:
		return _rect.material as ShaderMaterial
	return null
