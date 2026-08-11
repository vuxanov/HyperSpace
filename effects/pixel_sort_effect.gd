extends EffectLayer
class_name PixelSortEffect

## Approximate GPU pixel-sort / streak post-process.

var _rect: ColorRect
var _time: float = 0.0


func _ready() -> void:
	effect_id = "pixel_sort"
	layer = 6
	_rect = _make_screen_color_rect("res://effects/pixel_sort_effect.gdshader")
	var mat := _mat()
	if mat:
		mat.set_shader_parameter("intensity", 0.75)
		mat.set_shader_parameter("threshold", 0.45)
		mat.set_shader_parameter("stretch", 0.55)
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
		mat.set_shader_parameter("audio_drive", resolve_drive(state.mids))


func apply_modulator(mod01: float) -> void:
	super.apply_modulator(mod01)
	if not enabled:
		return
	if normalize_drive_mode(drive_mode) == "lfo":
		var mat := _mat()
		if mat:
			mat.set_shader_parameter("audio_drive", resolve_drive(0.0))
			mat.set_shader_parameter("stretch", clampf(0.25 + mod01 * 0.75, 0.05, 1.0))


func _on_params_changed(params: Dictionary) -> void:
	_apply_shader(params)
	visible = enabled


func _apply_shader(params: Dictionary) -> void:
	var mat := _mat()
	if mat == null:
		return
	if params.has("intensity"):
		mat.set_shader_parameter("intensity", float(params["intensity"]))
	if params.has("threshold"):
		mat.set_shader_parameter("threshold", float(params["threshold"]))
	if params.has("stretch"):
		mat.set_shader_parameter("stretch", float(params["stretch"]))


func _mat() -> ShaderMaterial:
	if _rect and _rect.material is ShaderMaterial:
		return _rect.material as ShaderMaterial
	return null
