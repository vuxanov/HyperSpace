extends RefCounted
class_name FlythroughCameraRig

## Follows a Curve3D; mouse/gamepad look + shared ModulatorBus rotation offsets.


var fly_speed: float = 12.0
var look_sensitivity: float = 0.0035
var gamepad_look_sensitivity: float = 1.6
var max_pitch_deg: float = 65.0
var loop: bool = true

var _camera: Camera3D
var _curve: Curve3D
var _distance: float = 0.0
var _yaw: float = 0.0
var _pitch: float = 0.0
var _spin_roll: float = 0.0
## Reactive rotation offsets — separate from mouse/gamepad look so disable can snap back.
var _reactive_yaw: float = 0.0
var _reactive_pitch: float = 0.0
var _reactive_roll: float = 0.0
var _mod: ModulatorBus


func setup(camera: Camera3D, curve: Curve3D) -> void:
	_camera = camera
	_curve = curve
	_distance = 0.0
	_yaw = 0.0
	_pitch = 0.0
	_spin_roll = 0.0
	reset_reactive_spin()
	_bind_shared_modulator()
	_apply_transform()


func set_modulator(mod: ModulatorBus) -> void:
	_mod = mod


func get_modulator() -> ModulatorBus:
	_bind_shared_modulator()
	return _mod


func apply_reactive_spin(rate: float, axes: Vector3) -> void:
	## Continuous look spin from Reactivity Rotation (camera target / Camera motion).
	if axes.length_squared() < 0.01:
		return
	var r := maxf(rate, 0.0)
	_reactive_yaw += r * axes.y
	_reactive_pitch += r * axes.x
	_reactive_pitch = clampf(_reactive_pitch, deg_to_rad(-max_pitch_deg), deg_to_rad(max_pitch_deg))
	_reactive_roll += r * axes.z
	# Soft-wrap roll so it doesn't runaway forever without looking wild.
	_reactive_roll = fposmod(_reactive_roll + PI, TAU) - PI


func reset_reactive_spin() -> void:
	## Clear audio/reactivity spin so the camera returns to path + mouse look baseline.
	_reactive_yaw = 0.0
	_reactive_pitch = 0.0
	_reactive_roll = 0.0
	_spin_roll = 0.0
	_apply_transform()


func _bind_shared_modulator() -> void:
	if _mod != null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var rs := tree.root.get_node_or_null("ReactivitySettings")
		if rs and rs.has_method("get_modulator"):
			_mod = rs.call("get_modulator") as ModulatorBus
	if _mod == null:
		_mod = ModulatorBus.new()


func set_curve(curve: Curve3D, reset_progress: bool = false) -> void:
	var frac := 0.0
	if _curve != null and not reset_progress:
		var old_len := _curve.get_baked_length()
		if old_len > 0.01:
			frac = _distance / old_len
	_curve = curve
	if reset_progress or _curve == null:
		_distance = 0.0
	else:
		var new_len := _curve.get_baked_length()
		_distance = frac * new_len if new_len > 0.01 else 0.0
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


func advance(delta: float, _kick: float = 0.0) -> void:
	_apply_gamepad_look(delta)
	_bind_shared_modulator()
	# ModulatorBus is advanced by ReactivitySettings; only apply look here.
	if _curve == null or _camera == null:
		return
	if not _camera.current:
		_camera.current = true
	var length := _curve.get_baked_length()
	if length <= 0.01:
		return
	# fly_speed is world-units/sec scaled by path length so large envs still feel snappy.
	var speed_scale := maxf(length / 35.0, 1.0)
	_distance += fly_speed * speed_scale * delta
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
	var yaw := _yaw + _reactive_yaw
	var pitch := _pitch + _reactive_pitch
	var roll := _spin_roll + _reactive_roll
	if _mod and _mod.preset != ModulatorBus.Preset.OFF:
		yaw += _mod.yaw_offset
		pitch += _mod.pitch_offset
		roll += _mod.roll_offset
	pitch = clampf(pitch, deg_to_rad(-max_pitch_deg), deg_to_rad(max_pitch_deg))
	var look := Basis.from_euler(Vector3(pitch, yaw, roll))
	_camera.global_transform = Transform3D(path_xf.basis * look, path_xf.origin)
