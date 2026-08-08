extends ReactiveEnvironment
class_name FlythroughEnvironment

## Shared fly-through: path + camera + three uploadable layers (environment, scatter, centerpiece).

const RH = preload("res://core/reactivity_hub.gd")

var fly_speed: float = 2.0

var _camera: Camera3D
var _light: OmniLight3D
var _env_root: Node3D
var _scatter_root: Node3D
var _center_root: Node3D
var _rig: FlythroughCameraRig
var _curve: Curve3D
var _layer_configs: Dictionary = {
	"environment": {"source": "primitive:box_corridor"},
	"scatter": {"source": "primitive:cubes", "count": 36},
	"centerpiece": {"source": "primitive:torus"},
}
var _centerpiece_mesh: MeshInstance3D
var _scatter_meshes: Array[MeshInstance3D] = []
var _center_base_scale := Vector3.ONE
var _scatter_base_scales: Array[Vector3] = []
## Keep centerpiece locked in the middle of the camera view (not flying along the path).
var _centerpiece_locked: bool = true
var _center_distance: float = 4.0
var _idle_t: float = 0.0
var _center_particles: GPUParticles3D
var _env_particles: GPUParticles3D
var _center_particles_on: bool = false
var _env_particles_on: bool = false
var _accent := Color(0.45, 0.75, 1.0)


func _ready() -> void:
	_build_world()
	_rig = FlythroughCameraRig.new()
	_rig.fly_speed = fly_speed
	_rebuild_all()


func configure_from_params(params: Dictionary) -> void:
	if params.has("speed"):
		fly_speed = float(params["speed"])
	elif params.has("fly_speed"):
		fly_speed = float(params["fly_speed"])
	if params.has("environment") and params["environment"] is Dictionary:
		_layer_configs["environment"] = (params["environment"] as Dictionary).duplicate(true)
	if params.has("scatter") and params["scatter"] is Dictionary:
		_layer_configs["scatter"] = (params["scatter"] as Dictionary).duplicate(true)
	if params.has("centerpiece") and params["centerpiece"] is Dictionary:
		_layer_configs["centerpiece"] = (params["centerpiece"] as Dictionary).duplicate(true)
	if params.has("follow_centerpiece"):
		_centerpiece_locked = bool(params["follow_centerpiece"])
	if params.has("centerpiece_locked"):
		_centerpiece_locked = bool(params["centerpiece_locked"])
	if params.has("center_distance"):
		_center_distance = float(params["center_distance"])
	if is_inside_tree():
		if _rig:
			_rig.fly_speed = fly_speed
		_rebuild_all()


func set_layer_source(layer_id: String, config: Dictionary) -> void:
	if layer_id not in ["environment", "scatter", "centerpiece"]:
		push_warning("FlythroughEnvironment: unknown layer %s" % layer_id)
		return
	_layer_configs[layer_id] = config.duplicate(true)
	if not is_inside_tree():
		return
	match layer_id:
		"environment":
			_rebuild_environment()
			_rebuild_path_from_environment()
			_rebuild_scatter()
			_place_centerpiece()
		"scatter":
			_rebuild_scatter()
		"centerpiece":
			_rebuild_centerpiece()
			_place_centerpiece()


func get_layer_config(layer_id: String) -> Dictionary:
	return (_layer_configs.get(layer_id, {}) as Dictionary).duplicate(true)


func handle_look_input(event: InputEvent) -> void:
	if _rig:
		_rig.handle_look_input(event)


func _build_world() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.42)
	env.ambient_light_energy = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.09, 0.11)
	env.fog_density = 0.015
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.35
	world_env.environment = env
	add_child(world_env)

	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.near = 0.05
	_camera.far = 200.0
	add_child(_camera)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.95, 0.95, 1.0)
	_light.light_energy = 1.0
	_light.omni_range = 24.0
	add_child(_light)

	_env_root = Node3D.new()
	_env_root.name = "Environment"
	add_child(_env_root)
	_scatter_root = Node3D.new()
	_scatter_root.name = "Scatter"
	add_child(_scatter_root)
	_center_root = Node3D.new()
	_center_root.name = "Centerpiece"
	add_child(_center_root)
	_setup_particle_systems()


func _setup_particle_systems() -> void:
	_center_particles = GPUParticles3D.new()
	_center_particles.emitting = false
	_center_particles.amount = 320
	_center_particles.lifetime = 1.2
	_center_particles.explosiveness = 0.35
	_center_particles.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	var cmesh := SphereMesh.new()
	cmesh.radius = 0.06
	cmesh.height = 0.12
	_center_particles.draw_pass_1 = cmesh
	var cmat := ParticleProcessMaterial.new()
	cmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	cmat.emission_sphere_radius = 0.7
	cmat.direction = Vector3(0, 1, 0)
	cmat.spread = 180.0
	cmat.initial_velocity_min = 0.4
	cmat.initial_velocity_max = 2.5
	cmat.gravity = Vector3(0, -0.2, 0)
	cmat.scale_min = 0.5
	cmat.scale_max = 1.4
	_center_particles.process_material = cmat
	_center_root.add_child(_center_particles)

	_env_particles = GPUParticles3D.new()
	_env_particles.emitting = false
	_env_particles.amount = 500
	_env_particles.lifetime = 2.0
	_env_particles.explosiveness = 0.05
	_env_particles.visibility_aabb = AABB(Vector3(-20, -10, -40), Vector3(40, 20, 80))
	var emesh := BoxMesh.new()
	emesh.size = Vector3(0.08, 0.08, 0.08)
	_env_particles.draw_pass_1 = emesh
	var emat := ParticleProcessMaterial.new()
	emat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	emat.emission_box_extents = Vector3(2.0, 1.6, 8.0)
	emat.direction = Vector3(0, 0, 1)
	emat.spread = 25.0
	emat.initial_velocity_min = 0.2
	emat.initial_velocity_max = 1.5
	emat.gravity = Vector3(0, 0, 0)
	emat.scale_min = 0.4
	emat.scale_max = 1.2
	_env_particles.process_material = emat
	# Follow camera so particles fill the view, not a fixed wall.
	add_child(_env_particles)


func _rebuild_all() -> void:
	_rebuild_environment()
	_rebuild_path_from_environment()
	_rebuild_scatter()
	_rebuild_centerpiece()
	_place_centerpiece()
	if _rig and _camera and _curve:
		_rig.fly_speed = fly_speed
		_rig.setup(_camera, _curve)


func _rebuild_environment() -> void:
	for child in _env_root.get_children():
		_env_root.remove_child(child)
		child.free()
	var config: Dictionary = _layer_configs.get("environment", {})
	var source := FlythroughLayerSlot.resolve_source_string(config)
	if source.is_empty():
		source = "primitive:box_corridor"
	if FlythroughLayerSlot.is_file_path(source):
		FlythroughLayerSlot.load_asset_into(_env_root, source)
	elif FlythroughLayerSlot.is_primitive_source(source):
		var kind := FlythroughLayerSlot.normalize_primitive(source)
		FlythroughPrimitives.spawn_environment(kind, _env_root)
	else:
		FlythroughPrimitives.spawn_environment("box_corridor", _env_root)


func _rebuild_path_from_environment() -> void:
	var config: Dictionary = _layer_configs.get("environment", {})
	var source := FlythroughLayerSlot.resolve_source_string(config)
	var kind := FlythroughLayerSlot.normalize_primitive(source) if FlythroughLayerSlot.is_primitive_source(source) else ""
	if kind == "flat_plane":
		_curve = FlythroughPathBuilder.overland(80.0, 8.0)
	elif FlythroughLayerSlot.is_file_path(source):
		var aabb := FlythroughLayerSlot.compute_aabb(_env_root)
		_curve = FlythroughPathBuilder.from_aabb(aabb)
	else:
		_curve = FlythroughPathBuilder.straight(60.0, 0.0)
	if _rig and _camera:
		_rig.set_curve(_curve, true)


func _rebuild_centerpiece() -> void:
	for child in _center_root.get_children():
		if child == _center_particles:
			continue
		_center_root.remove_child(child)
		child.free()
	_centerpiece_mesh = null
	var config: Dictionary = _layer_configs.get("centerpiece", {})
	var source := FlythroughLayerSlot.resolve_source_string(config)
	if source.is_empty():
		source = "primitive:torus"
	if FlythroughLayerSlot.is_file_path(source):
		var node := FlythroughLayerSlot.load_asset_into(_center_root, source)
		if node:
			_center_base_scale = node.scale
	elif FlythroughLayerSlot.is_primitive_source(source):
		var kind := FlythroughLayerSlot.normalize_primitive(source)
		_centerpiece_mesh = FlythroughPrimitives.spawn_centerpiece(kind, _center_root)
		_center_base_scale = Vector3.ONE
	else:
		_centerpiece_mesh = FlythroughPrimitives.spawn_centerpiece("torus", _center_root)
		_center_base_scale = Vector3.ONE
	_center_particles_on = false  # force resync
	_sync_particles()


func _place_centerpiece() -> void:
	# Initial pose; _process keeps it camera-centered when locked.
	_update_centerpiece_transform(0.0)


func _update_centerpiece_transform(delta: float) -> void:
	if _center_root.get_child_count() == 0 or _camera == null:
		return
	if not _centerpiece_locked:
		return
	_idle_t += delta
	var bob := sin(_idle_t * 1.15) * 0.06
	var sway := cos(_idle_t * 0.85) * 0.04
	# Stay in the middle of the screen: fixed offset in camera space.
	var local_offset := Vector3(sway, bob, -_center_distance)
	_center_root.global_position = _camera.to_global(local_offset)
	_center_root.global_basis = _camera.global_transform.basis
	# Slow idle spin on the mesh itself (independent of camera).
	if delta > 0.0 and _center_root.get_child_count() > 0:
		var child := _center_root.get_child(0)
		if child is Node3D:
			(child as Node3D).rotate_y(delta * 0.4)


func _rebuild_scatter() -> void:
	for child in _scatter_root.get_children():
		_scatter_root.remove_child(child)
		child.free()
	_scatter_meshes.clear()
	_scatter_base_scales.clear()
	if _curve == null:
		return
	var config: Dictionary = _layer_configs.get("scatter", {})
	var source := FlythroughLayerSlot.resolve_source_string(config)
	if source.is_empty():
		source = "primitive:cubes"
	var count := int(config.get("count", 36))
	count = clampi(count, 0, 200)
	var length := _curve.get_baked_length()
	if length <= 0.01 or count <= 0:
		return

	var template_mesh: Mesh = null
	var template_mat: Material = null
	var use_file := FlythroughLayerSlot.is_file_path(source)

	if use_file:
		# Instance the loaded asset multiple times.
		pass
	elif FlythroughLayerSlot.is_primitive_source(source):
		var kind := FlythroughLayerSlot.normalize_primitive(source)
		var proto := FlythroughPrimitives.spawn_scatter_template(kind)
		template_mesh = proto.mesh
		template_mat = proto.material_override
		proto.free()
	else:
		var proto2 := FlythroughPrimitives.spawn_scatter_template("cubes")
		template_mesh = proto2.mesh
		template_mat = proto2.material_override
		proto2.free()

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in count:
		var dist := (float(i) + 0.5) / float(count) * length
		var path_xf := _curve.sample_baked_with_rotation(dist, false)
		var side := Vector3(path_xf.basis.x.normalized())
		var up := Vector3(path_xf.basis.y.normalized())
		var offset := side * rng.randf_range(-1.6, 1.6) + up * rng.randf_range(-0.8, 0.9)
		var inst: Node3D
		if use_file:
			inst = FlythroughLayerSlot.load_asset_into(_scatter_root, source)
			if inst == null:
				continue
		else:
			var mesh_inst := MeshInstance3D.new()
			mesh_inst.mesh = template_mesh
			mesh_inst.material_override = template_mat
			_scatter_root.add_child(mesh_inst)
			inst = mesh_inst
			_scatter_meshes.append(mesh_inst)
		inst.position = path_xf.origin + offset
		inst.scale = Vector3.ONE * rng.randf_range(0.7, 1.3)
		_scatter_base_scales.append(inst.scale)


func _process(delta: float) -> void:
	if _rig:
		_rig.fly_speed = fly_speed
		_rig.advance(delta)
	if _camera and _light:
		_light.global_position = _camera.global_position + Vector3(0, 1.2, 0)
	_update_centerpiece_transform(delta)
	_sync_particles()
	# Keep environment particles as a volume just ahead of the camera.
	if _env_particles and _camera:
		_env_particles.global_transform = Transform3D(
			_camera.global_transform.basis,
			_camera.to_global(Vector3(0, 0, -6.0))
		)


func _sync_particles() -> void:
	var want_center := RH.particles_applies_to("centerpiece")
	var want_env := RH.particles_applies_to("environment")
	if want_center != _center_particles_on:
		_center_particles_on = want_center
		if _center_particles:
			_center_particles.emitting = want_center
			_center_particles.visible = want_center
		_set_centerpiece_mesh_visible(not want_center)
	if want_env != _env_particles_on:
		_env_particles_on = want_env
		if _env_particles:
			_env_particles.emitting = want_env
			_env_particles.visible = want_env


func _set_centerpiece_mesh_visible(vis: bool) -> void:
	for child in _center_root.get_children():
		if child == _center_particles:
			continue
		if child is Node3D:
			(child as Node3D).visible = vis


func apply_audio_state(state: AudioState) -> void:
	_sync_particles()
	if not RH.enabled():
		_reset_reactive_scales()
		return

	# Lights — strong, visible color + energy shifts when enabled.
	if RH.affect_light() and _light:
		var drive := state.bass * 1.2 + state.energy
		_light.light_energy = 0.7 + drive * 3.5
		_light.omni_range = 16.0 + state.energy * 18.0
		var hue := fposmod(0.55 + state.mids * 0.35 + state.highs * 0.25, 1.0)
		_light.light_color = Color.from_hsv(hue, 0.55 + state.mids * 0.35, 1.0)
	elif _light:
		_light.light_energy = 1.0
		_light.light_color = Color(0.95, 0.95, 1.0)

	if RH.applies_to("environment") and RH.affect_emission():
		_tint_environment_emission(state)

	if RH.applies_to("scatter"):
		_apply_scatter_audio(state)
	else:
		_reset_scatter_scales()

	if RH.applies_to("centerpiece"):
		_apply_centerpiece_audio(state)
	else:
		_reset_centerpiece_scale()

	if _center_particles_on and _center_particles:
		_center_particles.amount = clampi(int(160 + state.bass * 500), 80, 900)
		if _center_particles.process_material is ParticleProcessMaterial:
			var pm: ParticleProcessMaterial = _center_particles.process_material
			pm.initial_velocity_max = 1.0 + state.energy * 5.0
			pm.color = Color.from_hsv(fposmod(state.mids, 1.0), 0.7, 1.0)
		if state.beat:
			_center_particles.restart()
	if _env_particles_on and _env_particles:
		_env_particles.amount = clampi(int(200 + state.energy * 600), 100, 1200)
		if _env_particles.process_material is ParticleProcessMaterial:
			var epm: ParticleProcessMaterial = _env_particles.process_material
			epm.initial_velocity_max = 0.8 + state.highs * 4.0
			epm.color = Color.from_hsv(fposmod(0.4 + state.highs * 0.5, 1.0), 0.6, 1.0)


func _tint_environment_emission(state: AudioState) -> void:
	var hue := fposmod(0.5 + state.bass * 0.4, 1.0)
	var col := Color.from_hsv(hue, 0.5, 0.35 + state.energy * 0.65)
	for child in _env_root.get_children():
		_tint_mesh_tree(child, col, 0.4 + state.energy * 3.0)


func _tint_mesh_tree(node: Node, emission_col: Color, energy: float) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = mi.material_override
			mat.emission_enabled = true
			mat.emission = emission_col
			mat.emission_energy_multiplier = energy
	for child in node.get_children():
		_tint_mesh_tree(child, emission_col, energy)


func _apply_centerpiece_audio(state: AudioState) -> void:
	var node: Node3D = null
	if _center_root.get_child_count() > 0:
		for child in _center_root.get_children():
			if child == _center_particles:
				continue
			if child is Node3D:
				node = child as Node3D
				break
	if node == null:
		return
	if RH.affect_scale() and not _center_particles_on:
		var reactive := state.bass * 1.2 + state.energy * 0.5
		if state.beat:
			reactive *= 1.25
		var amt := clampf(1.0 + reactive * RH.scale_amount() * 0.12, 0.5, 8.0)
		node.scale = _center_base_scale * RH.scale_vector(amt)
	if RH.affect_rotation() and not _center_particles_on:
		node.rotate_y(state.mids * 0.04)
	if RH.affect_emission():
		var hue := fposmod(state.mids * 0.8 + state.highs * 0.4, 1.0)
		var col := Color.from_hsv(hue, 0.75, 1.0)
		_apply_emission_to_node(node, col, 1.0 + state.mids * 6.0 + state.bass * 2.0)


func _apply_emission_to_node(node: Node, col: Color, energy: float) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat: StandardMaterial3D
		if mi.material_override is StandardMaterial3D:
			mat = mi.material_override
		else:
			mat = StandardMaterial3D.new()
			if mi.mesh and mi.mesh.surface_get_material(0):
				var base := mi.mesh.surface_get_material(0)
				if base is StandardMaterial3D:
					mat = (base as StandardMaterial3D).duplicate()
			mi.material_override = mat
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = energy
		mat.albedo_color = col.lerp(mat.albedo_color, 0.35)
	for child in node.get_children():
		_apply_emission_to_node(child, col, energy)


func _apply_scatter_audio(state: AudioState) -> void:
	if RH.affect_scale():
		var reactive := state.highs * 0.8 + state.energy * 0.4
		var amt := clampf(1.0 + reactive * RH.scale_amount() * 0.1, 0.4, 6.0)
		var scale_vec := RH.scale_vector(amt)
		for i in _scatter_meshes.size():
			var base: Vector3 = _scatter_base_scales[i] if i < _scatter_base_scales.size() else Vector3.ONE
			_scatter_meshes[i].scale = base * scale_vec
	if RH.affect_emission():
		for mi in _scatter_meshes:
			if mi.material_override is StandardMaterial3D:
				var mat: StandardMaterial3D = mi.material_override
				mat.emission_enabled = true
				var hue := fposmod(0.3 + state.highs * 0.6, 1.0)
				mat.emission = Color.from_hsv(hue, 0.7, 1.0)
				mat.emission_energy_multiplier = 0.5 + state.highs * 4.0


func _reset_reactive_scales() -> void:
	_reset_centerpiece_scale()
	_reset_scatter_scales()
	if _light:
		_light.light_energy = 1.0
		_light.light_color = Color(0.95, 0.95, 1.0)
	_set_centerpiece_mesh_visible(not _center_particles_on)


func _reset_centerpiece_scale() -> void:
	if _center_root.get_child_count() > 0 and _center_root.get_child(0) is Node3D:
		(_center_root.get_child(0) as Node3D).scale = _center_base_scale


func _reset_scatter_scales() -> void:
	for i in _scatter_meshes.size():
		var base: Vector3 = _scatter_base_scales[i] if i < _scatter_base_scales.size() else Vector3.ONE
		_scatter_meshes[i].scale = base


func set_cue_param(key: String, value: Variant) -> void:
	match key:
		"speed", "fly_speed":
			fly_speed = float(value)
			if _rig:
				_rig.fly_speed = fly_speed
		"environment", "scatter", "centerpiece":
			if value is Dictionary:
				set_layer_source(key, value)
		"follow_centerpiece":
			_centerpiece_locked = bool(value)
		"centerpiece_locked":
			_centerpiece_locked = bool(value)
		"center_distance":
			_center_distance = float(value)
		"layer":
			# Expect { "id": "scatter", "config": { ... } }
			if value is Dictionary:
				var d: Dictionary = value
				set_layer_source(str(d.get("id", "")), d.get("config", {}) as Dictionary)
