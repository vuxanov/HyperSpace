extends ReactiveEnvironment
class_name DemoEnvironment

## Simple dual-layer stage: scrolling environment + reactive foreground object.

const RH = preload("res://core/reactivity_hub.gd")

@export var base_color: Color = Color(0.1, 0.3, 0.8)

var _env_root: Node3D
var _fg_root: Node3D
var _mesh: MeshInstance3D
var _light: OmniLight3D
var _particles: GPUParticles3D
var _env_rings: Array[MeshInstance3D] = []
var _rotation_speed: float = 0.3
var _base_scale: Vector3 = Vector3.ONE
var _particles_mode: bool = false
var _scroll: float = 0.0


func _ready() -> void:
	_build_world()
	_build_environment_layer()
	_build_foreground_layer()


func _build_world() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.06)
	env.glow_enabled = true
	env.glow_intensity = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.08, 0.16)
	env.fog_density = 0.02
	world_env.environment = env
	add_child(world_env)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.2, 5.5)
	add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0, 0.5, 0), Vector3.UP)
	_light = OmniLight3D.new()
	_light.light_color = base_color
	_light.omni_range = 14.0
	_light.light_energy = 1.2
	_light.position = Vector3(2, 3, 2)
	add_child(_light)


func _build_environment_layer() -> void:
	_env_root = Node3D.new()
	_env_root.name = "Environment"
	add_child(_env_root)
	for i in 8:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 3.2
		torus.outer_radius = 3.5
		ring.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.08, 0.12, 0.22)
		mat.emission_enabled = true
		mat.emission = base_color * 0.15
		mat.emission_energy_multiplier = 0.8
		ring.material_override = mat
		ring.position = Vector3(0, 0, -i * 4.0)
		ring.rotate_x(PI * 0.5)
		_env_root.add_child(ring)
		_env_rings.append(ring)


func _build_foreground_layer() -> void:
	_fg_root = Node3D.new()
	_fg_root.name = "Foreground"
	add_child(_fg_root)
	_mesh = MeshInstance3D.new()
	_mesh.name = "ForegroundMesh"
	var box := BoxMesh.new()
	box.size = Vector3(1.4, 1.4, 1.4)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.emission_enabled = true
	mat.emission = base_color * 0.5
	_mesh.material_override = mat
	_fg_root.add_child(_mesh)
	_particles = GPUParticles3D.new()
	_particles.emitting = false
	_particles.amount = 400
	_particles.lifetime = 1.4
	_particles.explosiveness = 0.35
	_particles.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	_particles.draw_pass_1 = box
	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(0.7, 0.7, 0.7)
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 180.0
	pmat.initial_velocity_min = 0.4
	pmat.initial_velocity_max = 2.5
	pmat.gravity = Vector3(0, -1.5, 0)
	pmat.scale_min = 0.08
	pmat.scale_max = 0.22
	pmat.color = Color(base_color.r, base_color.g, base_color.b, 0.95)
	_particles.process_material = pmat
	_fg_root.add_child(_particles)


func _process(delta: float) -> void:
	_sync_particles_mode()
	_scroll += delta * (2.5 + (4.0 if RH.enabled() else 0.0))
	for i in _env_rings.size():
		var ring: MeshInstance3D = _env_rings[i]
		var z := fposmod(-i * 4.0 + _scroll, 32.0) - 4.0
		ring.position.z = -z
		ring.rotate_z(delta * 0.4)
	if _particles_mode:
		if _particles and RH.applies_to("foreground") and RH.affect_rotation():
			_particles.rotate_y(delta * _rotation_speed)
		elif _particles:
			_particles.rotate_y(delta * 0.25)
	elif _mesh:
		if RH.applies_to("foreground") and RH.affect_rotation():
			_mesh.rotate_y(delta * _rotation_speed)
		else:
			_mesh.rotate_y(delta * 0.25)


func _sync_particles_mode() -> void:
	var want := RH.particles_applies_to("centerpiece") or RH.particles_applies_to("foreground")
	if want == _particles_mode:
		return
	_particles_mode = want
	if _mesh:
		_mesh.visible = not _particles_mode
	if _particles:
		_particles.emitting = _particles_mode
		_particles.visible = _particles_mode


func apply_audio_state(state: AudioState) -> void:
	_sync_particles_mode()
	if not RH.enabled():
		_reset_non_reactive()
		return
	# Environment reacts lightly to energy (fog rings emission).
	if RH.applies_to("environment"):
		for ring in _env_rings:
			if ring.material_override is StandardMaterial3D:
				var mat: StandardMaterial3D = ring.material_override
				mat.emission_energy_multiplier = 0.5 + state.energy * 3.0 * RH.scale_amount() * 0.15
	if RH.affect_light() and _light:
		_light.light_energy = 1.0 + state.bass * 4.0
		_light.omni_range = 8.0 + state.energy * 10.0
		_light.light_color = Color.from_hsv(fposmod(0.55 + state.mids * 0.4, 1.0), 0.5, 1.0)
	if not RH.applies_to("foreground"):
		return
	var scale_amt := 1.0
	if RH.affect_scale():
		var reactive := state.bass * 2.0 + state.energy * 1.5
		if state.beat:
			reactive *= 1.6
		scale_amt = 1.0 + reactive * maxf(RH.scale_amount(), 0.0)
		scale_amt = clampf(scale_amt, 0.2, 40.0)
	var scale_vec: Vector3 = RH.scale_vector(scale_amt) if RH.affect_scale() else _base_scale
	if _particles_mode and _particles:
		_particles.scale = scale_vec
		_particles.amount = clampi(int(120 + state.bass * 500 * RH.scale_amount()), 80, 1200)
		if _particles.process_material is ParticleProcessMaterial:
			var pmat: ParticleProcessMaterial = _particles.process_material
			pmat.initial_velocity_max = 1.0 + state.energy * 6.0 * RH.scale_amount()
		if state.beat:
			_particles.restart()
	elif _mesh:
		_mesh.scale = scale_vec
		if RH.affect_emission() and _mesh.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = _mesh.material_override
			var hue := fposmod(state.mids * 0.7, 1.0)
			mat.emission = Color.from_hsv(hue, 0.7, 1.0)
			mat.emission_energy_multiplier = 1.0 + state.mids * 5.0
			mat.albedo_color = base_color.lerp(mat.emission, 0.35)
	if RH.affect_rotation():
		_rotation_speed = 0.2 + state.highs * 1.5


func _reset_non_reactive() -> void:
	if _mesh:
		_mesh.scale = _base_scale
	if _particles:
		_particles.scale = _base_scale
	if _light:
		_light.light_energy = 1.2
		_light.omni_range = 14.0
	_rotation_speed = 0.3


func set_cue_param(key: String, value: Variant) -> void:
	match key:
		"color":
			base_color = _parse_color(value)
			if _light:
				_light.light_color = base_color
			if _mesh and _mesh.material_override is StandardMaterial3D:
				var mat: StandardMaterial3D = _mesh.material_override
				mat.albedo_color = base_color
				mat.emission = base_color * 0.5


func _parse_color(value: Variant) -> Color:
	if value is Color:
		return value
	if value is String:
		return Color.from_string(value, Color.WHITE)
	return Color.WHITE
