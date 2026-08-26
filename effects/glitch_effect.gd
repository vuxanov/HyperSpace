extends EffectLayer
class_name GlitchEffect

## Screen-space glitch (pixel slices + RGB split).

var _rect: ColorRect
var _time: float = 0.0
var _base_intensity: float = 1.2
var _base_rate: float = 2.0
var _base_v_size: float = 24.0
var _base_h_size: float = 48.0
var _base_rgb: float = 0.9
var _base_chaos: float = 0.4


func _ready() -> void:
	effect_id = "glitch"
	layer = 8
	_rect = _make_screen_color_rect("res://effects/glitch_effect.gdshader")
	var mat := _mat()
	if mat:
		mat.set_shader_parameter("intensity", _base_intensity)
		mat.set_shader_parameter("rate", _base_rate)
		mat.set_shader_parameter("v_size", _base_v_size)
		mat.set_shader_parameter("h_size", _base_h_size)
		mat.set_shader_parameter("rgb_split", _base_rgb)
		mat.set_shader_parameter("slice_chaos", _base_chaos)
		mat.set_shader_parameter("audio_drive", 0.0)
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if not enabled:
		set_process(false)
		return
	_time += delta
	var mat := _mat()
	if mat:
		mat.set_shader_parameter("time_sec", _time)


func set_active(is_on: bool) -> void:
	enabled = is_on
	visible = is_on
	if _rect:
		_rect.visible = is_on
	set_process(is_on)


func apply_params(params: Dictionary) -> void:
	super.apply_params(params)
	_apply_resolved()
	visible = enabled
	set_process(enabled)


func apply_audio_state(_state: AudioState) -> void:
	if not enabled:
		visible = false
		set_process(false)
		return
	visible = true
	set_process(true)
	_apply_resolved()


func apply_modulator(_mod01: float) -> void:
	pass


func _on_params_changed(_params: Dictionary) -> void:
	_apply_resolved()
	visible = enabled
	set_process(enabled)


func _apply_resolved() -> void:
	var mat := _mat()
	if mat == null:
		return
	_base_intensity = eval_num("intensity", _base_intensity)
	_base_rate = eval_num("rate", _base_rate)
	_base_rgb = eval_num("rgb_split", _base_rgb)
	_base_chaos = eval_num("slice_chaos", _base_chaos)
	if has_raw_param("v_size"):
		_base_v_size = clampf(eval_num("v_size", _base_v_size), 1.0, 512.0)
		_base_h_size = clampf(eval_num("h_size", _base_h_size), 1.0, 512.0)
	else:
		_base_v_size = _legacy_density_to_pixels(eval_num("h_size", 0.8))
		_base_h_size = 48.0
	mat.set_shader_parameter("intensity", _base_intensity)
	mat.set_shader_parameter("rate", _base_rate)
	mat.set_shader_parameter("v_size", _base_v_size)
	mat.set_shader_parameter("h_size", _base_h_size)
	mat.set_shader_parameter("rgb_split", _base_rgb)
	mat.set_shader_parameter("slice_chaos", _base_chaos)
	mat.set_shader_parameter("audio_drive", 0.0)


static func resolve_slice_pixels(params: Dictionary, fallback_v: float = 24.0, fallback_h: float = 48.0) -> Vector2:
	## New sessions store v_size + h_size in pixels. Old sessions only had
	## normalized h_size (0–1 band density) and no v_size.
	var v := fallback_v
	var h := fallback_h
	if params.has("v_size"):
		v = _plain_or_fallback(params.get("v_size"), fallback_v)
		h = _plain_or_fallback(params.get("h_size"), fallback_h)
	else:
		var old_h := _plain_or_fallback(params.get("h_size"), 0.8)
		v = _legacy_density_to_pixels(old_h)
	return Vector2(clampf(v, 1.0, 512.0), clampf(h, 1.0, 512.0))


static func _legacy_density_to_pixels(old_h: float) -> float:
	var bands := 6.0 + clampf(old_h, 0.0, 1.0) * 24.0
	return clampf(roundf(1080.0 / max(bands, 1.0)), 1.0, 512.0)


static func _plain_or_fallback(raw: Variant, fallback: float) -> float:
	if raw is float or raw is int:
		return float(raw)
	if raw is String:
		var s := (raw as String).strip_edges()
		if s.is_valid_float():
			return s.to_float()
		return fallback
	return fallback


func _mat() -> ShaderMaterial:
	if _rect and _rect.material is ShaderMaterial:
		return _rect.material as ShaderMaterial
	return null
