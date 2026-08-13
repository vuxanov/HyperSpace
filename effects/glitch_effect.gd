extends EffectLayer
class_name GlitchEffect

## Screen-space glitch (row shift + RGB split).

var _rect: ColorRect
var _time: float = 0.0
var _base_intensity: float = 1.2
var _base_rate: float = 2.0
var _base_h_size: float = 0.8
var _base_rgb: float = 0.9
var _base_chaos: float = 0.75


func _ready() -> void:
	effect_id = "glitch"
	layer = 8
	_rect = _make_screen_color_rect("res://effects/glitch_effect.gdshader")
	var mat := _mat()
	if mat:
		mat.set_shader_parameter("intensity", _base_intensity)
		mat.set_shader_parameter("rate", _base_rate)
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
	_base_intensity = eval_num("intensity", _base_intensity, 0.0, 8.0)
	_base_rate = eval_num("rate", _base_rate, 0.0, 64.0)
	_base_h_size = eval_num("h_size", _base_h_size, 0.0, 2.0)
	_base_rgb = eval_num("rgb_split", _base_rgb, 0.0, 2.0)
	_base_chaos = eval_num("slice_chaos", _base_chaos, 0.0, 2.0)
	mat.set_shader_parameter("intensity", _base_intensity)
	mat.set_shader_parameter("rate", _base_rate)
	mat.set_shader_parameter("h_size", _base_h_size)
	mat.set_shader_parameter("rgb_split", _base_rgb)
	mat.set_shader_parameter("slice_chaos", _base_chaos)
	mat.set_shader_parameter("audio_drive", 0.0)


func _mat() -> ShaderMaterial:
	if _rect and _rect.material is ShaderMaterial:
		return _rect.material as ShaderMaterial
	return null
