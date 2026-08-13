extends ReactiveEnvironment
class_name CorridorEnvironment

## Simple corridor fly-through: camera moves forward along the tube; mouse/gamepad look around.

const RH = preload("res://core/reactivity_hub.gd")

@export var fly_speed: float = 6.0
@export var look_sensitivity: float = 0.0035
@export var gamepad_look_sensitivity: float = 2.2
@export var max_pitch_deg: float = 70.0

var _camera: Camera3D
var _env_root: Node3D
var _fg_root: Node3D
var _light: OmniLight3D
var _segments: Array[MeshInstance3D] = []
var _fg_orb: MeshInstance3D
var _distance: float = 0.0
var _yaw: float = 0.0
var _pitch: float = 0.0
var _corridor_length: float = 80.0
var _segment_spacing: float = 4.0
var _base_orb_scale := Vector3.ONE
var _accent := Color(0.35, 0.75, 1.0)


func _ready() -> void:
	_build_world()
	_build_corridor()
	_build_foreground()


func _build_world() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.08, 0.1, 0.14)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.08, 0.12)
	env.fog_density = 0.04
	env.glow_enabled = true
	env.glow_intensity = 0.8
	world_env.environment = env
	add_child(world_env)
	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.near = 0.05
	_camera.far = 120.0
	add_child(_camera)
	_light = OmniLight3D.new()
	_light.light_color = _accent
	_light.light_energy = 1.4
	_light.omni_range = 18.0
	add_child(_light)
	_env_root = Node3D.new()
	_env_root.name = "Environment"
	add_child(_env_root)
	_fg_root = Node3D.new()
	_fg_root.name = "Foreground"
	add_child(_fg_root)


func _build_corridor() -> void:
	var count := int(_corridor_length / _segment_spacing) + 4
	for i in count:
		var seg := MeshInstance3D.new()
		var tube := CylinderMesh.new()
		tube.top_radius = 2.4
		tube.bottom_radius = 2.4
		tube.height = _segment_spacing * 1.02
		tube.radial_segments = 16
		tube.rings = 1
		seg.mesh = tube
		var mat := StandardMaterial3D.new()
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(0.07, 0.08, 0.11)
		mat.roughness = 0.85
		mat.emission_enabled = true
		# Alternating soft stripe so motion is readable
		var stripe := (i % 2 == 0)
		mat.emission = _accent * (0.12 if stripe else 0.04)
		mat.emission_energy_multiplier = 1.0
		seg.material_override = mat
		# CylinderMesh is Y-up; rotate to run along Z (corridor axis).
		seg.rotation_degrees = Vector3(90, 0, 0)
		seg.position = Vector3(0, 0, -float(i) * _segment_spacing)
		_env_root.add_child(seg)
		_segments.append(seg)
		# Floor stripe for orientation
		var floor_piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.2, 0.06, _segment_spacing * 0.9)
		floor_piece.mesh = box
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color(0.15, 0.18, 0.22)
		fmat.emission_enabled = true
		fmat.emission = _accent * 0.25
		floor_piece.material_override = fmat
		floor_piece.position = Vector3(0, -2.15, -float(i) * _segment_spacing)
		_env_root.add_child(floor_piece)


func _build_foreground() -> void:
	_fg_orb = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	_fg_orb.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _accent
	mat.emission_enabled = true
	mat.emission = _accent
	mat.emission_energy_multiplier = 2.0
	_fg_orb.material_override = mat
	_fg_orb.position = Vector3(0, 0, -6.0)
	_fg_root.add_child(_fg_orb)


func handle_look_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		# Look while holding right mouse, or whenever motion comes from captured mouse.
		var looking := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
			or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		if looking:
			_yaw -= motion.relative.x * look_sensitivity
			_pitch -= motion.relative.y * look_sensitivity
			_pitch = clampf(_pitch, deg_to_rad(-max_pitch_deg), deg_to_rad(max_pitch_deg))


func _process(delta: float) -> void:
	_apply_gamepad_look(delta)
	var speed := fly_speed
	if RH.enabled() and RH.applies_to("environment"):
		speed += RH.scale_amount() * 0.35
	_distance = fposmod(_distance + speed * delta, _corridor_length)
	_update_camera()
	_update_light()
	_update_foreground(delta)


func _apply_gamepad_look(delta: float) -> void:
	# Right stick (controller) — works even when mouse isn't used.
	var sx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var sy := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(sx) < 0.15:
		sx = 0.0
	if absf(sy) < 0.15:
		sy = 0.0
	_yaw -= sx * gamepad_look_sensitivity * delta
	_pitch -= sy * gamepad_look_sensitivity * delta
	_pitch = clampf(_pitch, deg_to_rad(-max_pitch_deg), deg_to_rad(max_pitch_deg))


func _update_camera() -> void:
	if _camera == null:
		return
	# Path: fly down the corridor along -Z.
	var pos := Vector3(0.0, 0.0, -_distance)
	_camera.position = pos
	# Base facing forward (-Z), then apply look offsets.
	var basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	_camera.transform.basis = basis


func _update_light() -> void:
	if _light and _camera:
		_light.position = _camera.position + Vector3(0, 0.5, -1.5)


func _update_foreground(delta: float) -> void:
	if _fg_orb == null:
		return
	# Keep a simple marker ahead of the camera so there's a readable focal object.
	var ahead := _camera.position + Vector3(0, 0, -8.0)
	_fg_orb.position = ahead + Vector3(sin(_distance * 0.4) * 0.8, cos(_distance * 0.35) * 0.4, 0)
	_fg_orb.rotate_y(delta * 0.8)


func apply_audio_state(state: AudioState) -> void:
	if not RH.enabled():
		if _fg_orb:
			_fg_orb.scale = _base_orb_scale
		return
	if RH.applies_to("environment"):
		for i in _segments.size():
			var seg: MeshInstance3D = _segments[i]
			if seg.material_override is StandardMaterial3D:
				var mat: StandardMaterial3D = seg.material_override
				mat.emission_energy_multiplier = 0.7 + state.bass * 3.0
	if RH.affect_light() and _light:
		_light.light_energy = 1.0 + state.energy * 3.5
	if not RH.applies_to("foreground") or _fg_orb == null:
		return
	if RH.affect_scale():
		var amt := RH.scale_multiplier()
		_fg_orb.scale = RH.scale_vector(amt)
	if RH.affect_emission() and _fg_orb.material_override is StandardMaterial3D:
		(_fg_orb.material_override as StandardMaterial3D).emission_energy_multiplier = 1.5 + state.mids * 4.0


func set_cue_param(key: String, value: Variant) -> void:
	match key:
		"fly_speed":
			fly_speed = float(value)
		"color":
			if value is String:
				_accent = Color.from_string(value, _accent)
			elif value is Color:
				_accent = value
			if _light:
				_light.light_color = _accent
