extends ReactiveEnvironment
class_name TunnelEnvironment

## Animated hyperspace tunnel — environment scrolls; foreground ship reacts separately.

const RH = preload("res://core/reactivity_hub.gd")


var _env: Node3D
var _fg: Node3D
var _ship: MeshInstance3D
var _ship_particles: GPUParticles3D
var _segments: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _scroll: float = 0.0
var _particles_mode: bool = false
var _base_scale := Vector3.ONE
var _accent := Color(0.2, 0.85, 1.0)


func _ready() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.02, 0.05)
	env.glow_enabled = true
	env.glow_intensity = 1.4
	env.fog_enabled = true
	env.fog_density = 0.035
	env.fog_light_color = Color(0.1, 0.3, 0.5)
	world_env.environment = env
	add_child(world_env)
	var camera := Camera3D.new()
	camera.fov = 80.0
	camera.position = Vector3(0, 0, 4)
	add_child(camera)
	_light = OmniLight3D.new()
	_light.light_color = _accent
	_light.omni_range = 20.0
	_light.position = Vector3(0, 0, 2)
	add_child(_light)
	_env = Node3D.new()
	_env.name = "Environment"
	add_child(_env)
	_fg = Node3D.new()
	_fg.name = "Foreground"
	add_child(_fg)
	_build_tunnel()
	_build_ship()


func _build_tunnel() -> void:
	for i in 24:
		var seg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 3.0
		cyl.bottom_radius = 3.0
		cyl.height = 2.2
		cyl.radial_segments = 16
		seg.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(0.04, 0.06, 0.1)
		mat.emission_enabled = true
		var hue := 0.5 + 0.15 * sin(float(i) * 0.7)
		mat.emission = Color.from_hsv(hue, 0.7, 0.5)
		mat.emission_energy_multiplier = 1.2
		seg.material_override = mat
		seg.rotate_x(PI * 0.5)
		seg.position.z = -float(i) * 2.2
		_env.add_child(seg)
		_segments.append(seg)
		# Decorative rib
		if i % 2 == 0:
			var rib := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 2.85
			torus.outer_radius = 3.05
			rib.mesh = torus
			var rmat := StandardMaterial3D.new()
			rmat.albedo_color = _accent
			rmat.emission_enabled = true
			rmat.emission = _accent
			rmat.emission_energy_multiplier = 2.0
			rib.material_override = rmat
			rib.rotate_x(PI * 0.5)
			rib.position.z = seg.position.z
			_env.add_child(rib)


func _build_ship() -> void:
	_ship = MeshInstance3D.new()
	var wedge := PrismMesh.new()
	wedge.size = Vector3(0.8, 0.35, 1.4)
	_ship.mesh = wedge
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.95, 1.0)
	mat.emission_enabled = true
	mat.emission = _accent * 0.6
	_ship.material_override = mat
	_ship.position = Vector3(0, -0.3, 1.5)
	_fg.add_child(_ship)
	_ship_particles = GPUParticles3D.new()
	_ship_particles.emitting = false
	_ship_particles.amount = 350
	_ship_particles.lifetime = 1.2
	_ship_particles.explosiveness = 0.4
	_ship_particles.draw_pass_1 = wedge
	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(0.4, 0.2, 0.7)
	pmat.direction = Vector3(0, 0, 1)
	pmat.spread = 40.0
	pmat.initial_velocity_min = 1.0
	pmat.initial_velocity_max = 4.0
	pmat.gravity = Vector3.ZERO
	pmat.scale_min = 0.05
	pmat.scale_max = 0.15
	pmat.color = Color(_accent.r, _accent.g, _accent.b, 0.9)
	_ship_particles.process_material = pmat
	_ship_particles.position = _ship.position
	_fg.add_child(_ship_particles)


func _process(delta: float) -> void:
	_sync_particles()
	var speed := 8.0
	if RH.enabled() and RH.applies_to("environment"):
		speed += RH.scale_amount() * 1.5
	_scroll += delta * speed
	for i in _segments.size():
		var seg: MeshInstance3D = _segments[i]
		var z := fposmod(float(i) * 2.2 + _scroll, 52.8)
		seg.position.z = 4.0 - z
		seg.rotate_z(delta * (0.3 + float(i % 3) * 0.1))
	if _ship and not _particles_mode:
		_ship.position.x = sin(_scroll * 0.35) * 0.35
		_ship.position.y = -0.3 + cos(_scroll * 0.27) * 0.15


func _sync_particles() -> void:
	var want := ShowDirector.get_effect_enabled("particles")
	if want == _particles_mode:
		return
	_particles_mode = want
	if _ship:
		_ship.visible = not _particles_mode
	if _ship_particles:
		_ship_particles.emitting = _particles_mode
		_ship_particles.visible = _particles_mode
		_ship_particles.position = _ship.position if _ship else Vector3.ZERO


func apply_audio_state(state: AudioState) -> void:
	_sync_particles()
	if not RH.enabled():
		return
	if RH.applies_to("environment"):
		for seg in _segments:
			if seg.material_override is StandardMaterial3D:
				var mat: StandardMaterial3D = seg.material_override
				mat.emission_energy_multiplier = 0.8 + state.bass * 4.0
	if RH.affect_light() and _light:
		_light.light_energy = 1.0 + state.energy * 5.0
	if not RH.applies_to("foreground"):
		return
	var scale_amt := 1.0
	if RH.affect_scale():
		scale_amt = RH.scale_multiplier()
	var scale_vec: Vector3 = RH.scale_vector(scale_amt) if RH.affect_scale() else _base_scale
	if _particles_mode and _ship_particles:
		_ship_particles.scale = scale_vec
		if state.beat:
			_ship_particles.restart()
	elif _ship:
		_ship.scale = scale_vec
		if RH.affect_emission() and _ship.material_override is StandardMaterial3D:
			(_ship.material_override as StandardMaterial3D).emission = _accent * (0.4 + state.mids * 2.0)
