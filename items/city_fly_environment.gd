extends ReactiveEnvironment
class_name CityFlyEnvironment

## Night city fly-through — buildings scroll as environment; neon orb is foreground.

const RH = preload("res://core/reactivity_hub.gd")


var _env: Node3D
var _fg: Node3D
var _buildings: Array[MeshInstance3D] = []
var _orb: MeshInstance3D
var _orb_particles: GPUParticles3D
var _light: OmniLight3D
var _scroll: float = 0.0
var _particles_mode: bool = false
var _base_scale := Vector3.ONE
var _accent := Color(1.0, 0.35, 0.55)


func _ready() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.05)
	env.glow_enabled = true
	env.glow_intensity = 1.6
	env.fog_enabled = true
	env.fog_density = 0.025
	env.fog_light_color = Color(0.15, 0.05, 0.2)
	world_env.environment = env
	add_child(world_env)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 4.5, 10)
	camera.fov = 70.0
	add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0, 2, 0), Vector3.UP)
	_light = OmniLight3D.new()
	_light.light_color = _accent
	_light.omni_range = 25.0
	_light.position = Vector3(0, 6, 4)
	add_child(_light)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.3, 0.35, 0.55)
	sun.light_energy = 0.4
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	_env = Node3D.new()
	_env.name = "Environment"
	add_child(_env)
	_fg = Node3D.new()
	_fg.name = "Foreground"
	add_child(_fg)
	_build_city()
	_build_orb()


func _build_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 40:
		var b := MeshInstance3D.new()
		var box := BoxMesh.new()
		var h := rng.randf_range(2.0, 12.0)
		box.size = Vector3(rng.randf_range(1.2, 2.8), h, rng.randf_range(1.2, 2.8))
		b.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.08, 0.09, 0.12)
		mat.emission_enabled = true
		mat.emission = Color(rng.randf_range(0.2, 1.0), rng.randf_range(0.2, 0.8), 1.0) * 0.35
		mat.emission_energy_multiplier = 1.5
		b.material_override = mat
		var lane := -1.0 if i % 2 == 0 else 1.0
		b.position = Vector3(lane * rng.randf_range(3.5, 7.0), h * 0.5, -float(i) * 3.5)
		_env.add_child(b)
		_buildings.append(b)
	var ground := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(40, 0.2, 200)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.03, 0.03, 0.04)
	ground.material_override = gmat
	ground.position = Vector3(0, -0.1, -40)
	_env.add_child(ground)


func _build_orb() -> void:
	_orb = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 1.1
	_orb.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _accent
	mat.emission_enabled = true
	mat.emission = _accent
	mat.emission_energy_multiplier = 2.5
	_orb.material_override = mat
	_orb.position = Vector3(0, 2.2, 3.0)
	_fg.add_child(_orb)
	_orb_particles = GPUParticles3D.new()
	_orb_particles.emitting = false
	_orb_particles.amount = 400
	_orb_particles.lifetime = 1.3
	_orb_particles.explosiveness = 0.5
	_orb_particles.draw_pass_1 = sphere
	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pmat.emission_sphere_radius = 0.55
	pmat.spread = 180.0
	pmat.initial_velocity_min = 0.5
	pmat.initial_velocity_max = 3.5
	pmat.gravity = Vector3(0, -0.5, 0)
	pmat.scale_min = 0.06
	pmat.scale_max = 0.18
	pmat.color = Color(_accent.r, _accent.g, _accent.b, 0.95)
	_orb_particles.process_material = pmat
	_orb_particles.position = _orb.position
	_fg.add_child(_orb_particles)


func _process(delta: float) -> void:
	_sync_particles()
	var speed := 6.0
	if RH.enabled() and RH.applies_to("environment"):
		speed += RH.scale_amount()
	_scroll += delta * speed
	for i in _buildings.size():
		var b: MeshInstance3D = _buildings[i]
		var z := fposmod(b.position.z + _scroll + float(i) * 3.5, 140.0)
		b.position.z = 10.0 - z
	if _orb and not _particles_mode:
		_orb.position.x = sin(_scroll * 0.4) * 1.2
		_orb.position.y = 2.2 + cos(_scroll * 0.55) * 0.6
		_orb.rotate_y(delta * 1.2)


func _sync_particles() -> void:
	var want := ShowDirector.get_effect_enabled("particles")
	if want == _particles_mode:
		return
	_particles_mode = want
	if _orb:
		_orb.visible = not _particles_mode
	if _orb_particles:
		_orb_particles.emitting = _particles_mode
		_orb_particles.visible = _particles_mode
		if _orb:
			_orb_particles.position = _orb.position


func apply_audio_state(state: AudioState) -> void:
	_sync_particles()
	if not RH.enabled():
		return
	if RH.applies_to("environment"):
		for b in _buildings:
			if b.material_override is StandardMaterial3D:
				(b.material_override as StandardMaterial3D).emission_energy_multiplier = 1.0 + state.highs * 5.0
	if RH.affect_light() and _light:
		_light.light_energy = 0.8 + state.bass * 6.0
	if not RH.applies_to("foreground"):
		return
	var scale_amt := 1.0
	if RH.affect_scale():
		var reactive := state.bass * 2.2 + state.energy
		if state.beat:
			reactive *= 1.7
		scale_amt = clampf(1.0 + reactive * RH.scale_amount(), 0.3, 25.0)
	var scale_vec: Vector3 = RH.scale_vector(scale_amt) if RH.affect_scale() else _base_scale
	if _particles_mode and _orb_particles:
		_orb_particles.scale = scale_vec
		_orb_particles.position = _orb.position if _orb else _orb_particles.position
		if state.beat:
			_orb_particles.restart()
	elif _orb:
		_orb.scale = scale_vec
		if RH.affect_emission() and _orb.material_override is StandardMaterial3D:
			(_orb.material_override as StandardMaterial3D).emission_energy_multiplier = 1.5 + state.mids * 4.0
