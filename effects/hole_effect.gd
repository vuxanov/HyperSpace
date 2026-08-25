extends EffectLayer
class_name HoleEffect

## Screen-space stretch-and-fall-in. Distorts the 3D view under ASCII.

const SHAPES := ["Circular", "Rectangle"]

var _rect: ColorRect
var _time: float = 0.0
var _running: bool = false
var _strength: float = 0.75
var _hole_size: float = 0.20
var _twist: float = 0.0
var _softness: float = 0.30
var _flow: float = 0.50
var _center_x: float = 0.5
var _center_y: float = 0.5
var _shape: float = 0.0


func _ready() -> void:
	effect_id = "hole"
	# After chromatic/glitch, before ASCII so glyphs overlay the warped 3D view.
	layer = 9
	_rect = _make_screen_color_rect("res://effects/hole_effect.gdshader")
	_apply_display()
	visible = false
	set_process(false)


func set_active(is_on: bool) -> void:
	if is_on and not _running:
		_time = 0.0
	_running = is_on
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


func _on_params_changed(_params: Dictionary) -> void:
	_apply_resolved()
	visible = enabled
	set_process(enabled)


func _process(delta: float) -> void:
	if not enabled:
		set_process(false)
		return
	_time += delta
	_apply_display()


func _apply_resolved() -> void:
	if has_raw_param("shape"):
		var raw: Variant = raw_param("shape", "Circular")
		if raw is String:
			_shape = 1.0 if str(raw) == "Rectangle" else 0.0
		else:
			_shape = 1.0 if float(raw) >= 0.5 else 0.0
	_strength = eval_num("strength", _strength, 0.0, 2.0)
	_hole_size = eval_num("hole_size", _hole_size, 0.04, 0.85)
	_twist = eval_num("twist", _twist, 0.0, 8.0)
	_softness = eval_num("softness", _softness, 0.02, 0.8)
	_flow = eval_num("flow", _flow, 0.0, 2.0)
	_center_x = eval_num("center_x", _center_x, 0.0, 1.0)
	_center_y = eval_num("center_y", _center_y, 0.0, 1.0)
	_apply_display()


func _apply_display() -> void:
	var mat := _mat()
	if mat == null or mat.shader == null:
		return
	mat.set_shader_parameter("strength", _strength)
	mat.set_shader_parameter("hole_size", _hole_size)
	mat.set_shader_parameter("twist", _twist)
	mat.set_shader_parameter("softness", _softness)
	mat.set_shader_parameter("flow", _flow)
	mat.set_shader_parameter("center_x", _center_x)
	mat.set_shader_parameter("center_y", _center_y)
	mat.set_shader_parameter("shape", _shape)
	mat.set_shader_parameter("time_sec", _time)


func _mat() -> ShaderMaterial:
	if _rect and _rect.material is ShaderMaterial:
		return _rect.material as ShaderMaterial
	return null
