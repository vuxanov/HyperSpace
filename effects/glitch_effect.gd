extends EffectLayer
class_name GlitchEffect

## Screen-space glitch (row shift + RGB split) from ASCII Live Visuals Engine.

var _rect: ColorRect
var _time: float = 0.0


func _ready() -> void:
	effect_id = "glitch"
	layer = 8
	_rect = _make_screen_color_rect("res://effects/glitch_effect.gdshader")
	var mat := _mat()
	if mat:
		mat.set_shader_parameter("intensity", 0.85)
		mat.set_shader_parameter("rate", 1.5)
		mat.set_shader_parameter("h_size", 0.75)
		mat.set_shader_parameter("rgb_split", 0.85)
		mat.set_shader_parameter("slice_chaos", 0.65)
	visible = false
	set_process(true)


func _process(delta: float) -> void:
	if not enabled:
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
		mat.set_shader_parameter("intensity", clampf(_intensity * (0.35 + mod01 * 0.9), 0.0, 1.2))


func _on_params_changed(params: Dictionary) -> void:
	_apply_shader(params)
	visible = enabled


func _apply_shader(params: Dictionary) -> void:
	var mat := _mat()
	if mat == null:
		return
	if params.has("intensity"):
		mat.set_shader_parameter("intensity", float(params["intensity"]))
	if params.has("rate"):
		mat.set_shader_parameter("rate", float(params["rate"]))
	if params.has("h_size"):
		mat.set_shader_parameter("h_size", float(params["h_size"]))
	if params.has("rgb_split"):
		mat.set_shader_parameter("rgb_split", float(params["rgb_split"]))
	if params.has("slice_chaos"):
		mat.set_shader_parameter("slice_chaos", float(params["slice_chaos"]))


func _mat() -> ShaderMaterial:
	if _rect and _rect.material is ShaderMaterial:
		return _rect.material as ShaderMaterial
	return null
