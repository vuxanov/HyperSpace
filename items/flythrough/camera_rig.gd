extends RefCounted
class_name FlythroughCameraRig

## Follows a Curve3D at a calm speed; yaw/pitch look offsets on top.


var fly_speed: float = 2.0
var look_sensitivity: float = 0.0035
var gamepad_look_sensitivity: float = 1.6
var max_pitch_deg: float = 65.0
var loop: bool = true

var _camera: Camera3D
var _curve: Curve3D
var _distance: float = 0.0
var _yaw: float = 0.0
var _pitch: float = 0.0


func setup(camera: Camera3D, curve: Curve3D) -> void:
	_camera = camera
	_curve = curve
	_distance = 0.0
	_yaw = 0.0
	_pitch = 0.0
	_apply_transform()


func set_curve(curve: Curve3D, reset_progress: bool = false) -> void:
	_curve = curve
	if reset_progress:
		_distance = 0.0
	_apply_transform()


func handle_look_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var looking := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
			or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		if looking:
			_yaw -= motion.relative.x * look_sensitivity
			_pitch -= motion.relative.y * look_sensitivity
			_pitch = clampf(_pitch, deg_to_rad(-max_pitch_deg), deg_to_rad(max_pitch_deg))


func advance(delta: float) -> void:
	_apply_gamepad_look(delta)
	if _curve == null or _camera == null:
		return
	var length := _curve.get_baked_length()
	if length <= 0.01:
		return
	_distance += fly_speed * delta
	if loop:
		_distance = fposmod(_distance, length)
	else:
		_distance = clampf(_distance, 0.0, length)
	_apply_transform()


func get_distance() -> float:
	return _distance


func get_path_length() -> float:
	if _curve == null:
		return 0.0
	return _curve.get_baked_length()


func sample_transform(distance: float) -> Transform3D:
	if _curve == null or _curve.get_baked_length() <= 0.01:
		return Transform3D(Basis.IDENTITY, Vector3.ZERO)
	return _curve.sample_baked_with_rotation(fposmod(distance, _curve.get_baked_length()), false)


func _apply_gamepad_look(delta: float) -> void:
	var sx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var sy := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(sx) < 0.15:
		sx = 0.0
	if absf(sy) < 0.15:
		sy = 0.0
	_yaw -= sx * gamepad_look_sensitivity * delta
	_pitch -= sy * gamepad_look_sensitivity * delta
	_pitch = clampf(_pitch, deg_to_rad(-max_pitch_deg), deg_to_rad(max_pitch_deg))


func _apply_transform() -> void:
	if _camera == null or _curve == null:
		return
	var length := _curve.get_baked_length()
	if length <= 0.01:
		return
	var path_xf := _curve.sample_baked_with_rotation(_distance, false)
	# Path forward in Godot baked rotation; apply look offsets in camera local space.
	var look := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	_camera.global_transform = Transform3D(path_xf.basis * look, path_xf.origin)
