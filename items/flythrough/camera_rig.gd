extends RefCounted
class_name FlythroughCameraRig

## Follows a Curve3D; mouse/gamepad look + shared ModulatorBus rotation offsets.
## Orientation uses look-ahead + basis slerp so corners (square) and loop seams stay smooth.
## Path speed is dampened in high-curvature sections so square corners don't rush.

const RH = preload("res://core/reactivity_hub.gd")


var fly_speed: float = 12.0
var look_sensitivity: float = 0.0035
var gamepad_look_sensitivity: float = 1.6
var max_pitch_deg: float = 65.0
var loop: bool = true
## How far ahead (world units) to sample for facing; scaled up on long paths.
var look_ahead: float = 5.5
## Higher = snappier orientation follow; lower = softer turns.
var orient_smooth: float = 4.5
## Cap path-facing rotation speed (deg/sec) so square corners never snap.
var max_turn_deg_per_sec: float = 72.0
## How strongly high curvature slows travel (square corners).
var curvature_brake: float = 18.0
## Floor for curvature speed multiplier (never stop completely in a corner).
var min_corner_speed_mul: float = 0.18

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
var _smooth_basis: Basis = Basis.IDENTITY
var _has_smooth_basis: bool = false


func apply_camera_fx(on: bool, params: Dictionary = {}) -> void:
	SceneMeshFx.apply_camera_fx(_camera, on, params)


func setup(camera: Camera3D, curve: Curve3D) -> void:
	_camera = camera
	_curve = curve
	_distance = 0.0
	_yaw = 0.0
	_pitch = 0.0
	_spin_roll = 0.0
	_has_smooth_basis = false
	reset_reactive_spin()
	_bind_shared_modulator()
	_apply_transform()


func set_modulator(mod: ModulatorBus) -> void:
	_mod = mod


func get_modulator() -> ModulatorBus:
	_bind_shared_modulator()
	return _mod


func apply_reactive_spin(rate: float, axes: Vector3) -> void:
	## Continuous look spin from Reactivity Rotation (camera target).
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
		var rs: Node = tree.root.get_node_or_null("ReactivitySettings")
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
	_has_smooth_basis = false
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
	if _camera == null:
		return
	# Claim current even when the curve is briefly missing (env swap / loop).
	if not _camera.current:
		_camera.current = true
	if _curve == null:
		return
	var length := _curve.get_baked_length()
	if length <= 0.01:
		return
	# fly_speed is world-units/sec, lightly scaled by path length.
	# Divisor ~100 so fly_speed=1 is a slow cruise (was ~35 → too fast).
	var speed_scale := maxf(length / 100.0, 0.35)
	var base_speed := fly_speed * speed_scale
	# Slow through high-curvature sections (square corners / dive elbows).
	var corner_mul := _curvature_speed_mul(_distance, length)
	_distance += base_speed * corner_mul * delta
	if loop:
		_distance = fposmod(_distance, length)
	else:
		_distance = clampf(_distance, 0.0, length)
	_apply_transform(delta)


func get_path_progress() -> float:
	var length := get_path_length()
	if length <= 0.01:
		return 0.0
	return clampf(_distance / length, 0.0, 1.0)


func get_distance() -> float:
	return _distance


func get_path_length() -> float:
	if _curve == null:
		return 0.0
	return _curve.get_baked_length()


func sample_transform(distance: float) -> Transform3D:
	if _curve == null or _curve.get_baked_length() <= 0.01:
		return Transform3D(Basis.IDENTITY, Vector3.ZERO)
	return _path_transform_at(fposmod(distance, _curve.get_baked_length()), false)


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


func _apply_transform(delta: float = 1.0 / 60.0) -> void:
	if _camera == null or _curve == null:
		return
	var length := _curve.get_baked_length()
	if length <= 0.01:
		return
	var path_xf := _path_transform_at(_distance, true, delta)
	var yaw := _yaw + _reactive_yaw
	var pitch := _pitch + _reactive_pitch
	var roll := _spin_roll + _reactive_roll
	if _mod and RH.property_active("camera"):
		yaw += _mod.yaw_offset
		pitch += _mod.pitch_offset
		roll += _mod.roll_offset
	else:
		pitch = clampf(pitch, deg_to_rad(-max_pitch_deg), deg_to_rad(max_pitch_deg))
	var look := Basis.from_euler(Vector3(pitch, yaw, roll))
	_camera.global_transform = Transform3D(path_xf.basis * look, path_xf.origin)


func _path_transform_at(distance: float, smooth: bool = false, delta: float = 1.0 / 60.0) -> Transform3D:
	var length := _curve.get_baked_length()
	var dist := fposmod(distance, length) if length > 0.01 else 0.0
	var origin := _curve.sample_baked(dist)
	var ahead := clampf(look_ahead, 0.5, maxf(length * 0.08, 0.5))
	# Speed-aware look-ahead so slow flies still anticipate corners a bit.
	ahead = maxf(ahead, fly_speed * 0.35)
	ahead = minf(ahead, length * 0.18)
	var target := _curve.sample_baked(fposmod(dist + ahead, length))
	var forward := target - origin
	var basis: Basis
	if forward.length_squared() < 1e-6:
		basis = _curve.sample_baked_with_rotation(dist, false).basis
	else:
		var up := Vector3.UP
		var f := forward.normalized()
		if absf(f.dot(up)) > 0.92:
			up = Vector3.FORWARD
		# Camera looks along -Z; align -Z with forward travel.
		basis = Basis.looking_at(f, up)
	if smooth:
		if not _has_smooth_basis:
			_smooth_basis = basis
			_has_smooth_basis = true
		else:
			var t := clampf(orient_smooth * maxf(delta, 0.0001), 0.0, 1.0)
			var candidate := _smooth_basis.slerp(basis, t).orthonormalized()
			var ang := _smooth_basis.get_rotation_quaternion().angle_to(candidate.get_rotation_quaternion())
			var max_ang := deg_to_rad(max_turn_deg_per_sec) * maxf(delta, 0.0001)
			if ang > max_ang and ang > 0.0001:
				var lim_t := clampf(max_ang / ang, 0.0, 1.0)
				candidate = _smooth_basis.slerp(candidate, lim_t).orthonormalized()
			_smooth_basis = candidate
		basis = _smooth_basis
	return Transform3D(basis, origin)


func _curvature_speed_mul(distance: float, length: float) -> float:
	## Estimate path curvature from heading change over a short chord; brake in corners.
	if _curve == null or length <= 0.01:
		return 1.0
	var sample := clampf(length * 0.012, 0.6, 3.5)
	var d0 := fposmod(distance, length)
	var d1 := fposmod(distance + sample, length)
	var d2 := fposmod(distance + sample * 2.0, length)
	var p0 := _curve.sample_baked(d0)
	var p1 := _curve.sample_baked(d1)
	var p2 := _curve.sample_baked(d2)
	var v0 := p1 - p0
	var v1 := p2 - p1
	if v0.length_squared() < 1e-8 or v1.length_squared() < 1e-8:
		return 1.0
	var ang := v0.normalized().angle_to(v1.normalized())
	# ang/sample ≈ rad per world-unit; scale into a soft brake curve.
	var curv := ang / maxf(sample, 0.001)
	return clampf(1.0 / (1.0 + curv * curvature_brake), min_corner_speed_mul, 1.0)

