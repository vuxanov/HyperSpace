extends ReactiveEnvironment
class_name FlythroughEnvironment

## Shared fly-through: path + camera + layers (environment, scatter, centerpiece, lighting).

const RH = preload("res://core/reactivity_hub.gd")
const _MEDIA_PROP := preload("res://items/flythrough/media_prop.gd")
## Target longest AABB axis (meters) for imported environment models.
const ENV_TARGET_LONGEST := 48.0
const ENV_MIN_LONGEST := 10.0
const ENV_MAX_LONGEST := 140.0

var fly_speed: float = 12.0

var _camera: Camera3D
var _light: OmniLight3D
var _sun: DirectionalLight3D
var _world_env: WorldEnvironment
var _env_root: Node3D
var _scatter_root: Node3D
var _center_root: Node3D
var _rig: FlythroughCameraRig
var _curve: Curve3D
var _layer_configs: Dictionary = FlythroughAssetCatalog.default_layer_configs()
var _lighting_config: Dictionary = FlythroughAssetCatalog.default_lighting_config()
var _centerpiece_mesh: MeshInstance3D
var _scatter_nodes: Array[Node3D] = []
var _center_base_scale := Vector3.ONE
var _scatter_base_scales: Array[Vector3] = []
## Keep centerpiece locked in the middle of the camera view (not flying along the path).
var _centerpiece_locked: bool = true
var _center_distance: float = 2.75
var _idle_t: float = 0.0
var _center_particles: GPUParticles3D
var _env_particles: GPUParticles3D
var _scatter_particles: GPUParticles3D
var _center_particles_on: bool = false
var _env_particles_on: bool = false
var _scatter_particles_on: bool = false
var _accent := Color(0.92, 0.93, 0.95)
var _terrain_meta: Dictionary = {}
var _rot_accum_center: Vector3 = Vector3.ZERO
var _rot_accum_scatter: Vector3 = Vector3.ZERO
var _rot_accum_env: Vector3 = Vector3.ZERO
var _base_fill_energy: float = 1.0
var _base_sun_energy: float = 1.1
var _base_sun_color := Color(1.0, 0.96, 0.9)
var _base_sky_energy: float = 1.0
var _base_ambient_energy: float = 0.7
var _base_bg_energy: float = 1.0
var _base_ambient_color := Color(0.55, 0.55, 0.56)
## Uniform scale applied to file-based environments for readable flythroughs.
var _env_fit_scale: float = 1.0
## Per-environment user scale (playlist / layer config). Multiplies after auto-fit.
var _env_user_scale: float = 1.0
var _scatter_side_range: float = 1.6
var _scatter_base_positions: Array[Vector3] = []
var _noise: FastNoiseLite
var _noise_t: float = 0.0
var _center_base_local := Vector3.ZERO
var _mat_cache: Dictionary = {}  # MeshInstance3D instance_id -> Array[BaseMaterial3D]
var _noise_backup: Dictionary = {}  # MeshInstance3D instance_id -> { override, surfaces }
var _noise_mats: Dictionary = {}  # MeshInstance3D instance_id -> Array[ShaderMaterial]
const NOISE_DEFORM_SHADER: Shader = preload("res://effects/noise_deform.gdshader")


func _ready() -> void:
	set_process(true)
	_noise = FastNoiseLite.new()
	_noise.seed = 77
	_noise.frequency = 0.85
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
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
	if params.has("lighting") and params["lighting"] is Dictionary:
		_lighting_config = (params["lighting"] as Dictionary).duplicate(true)
	if params.has("follow_centerpiece"):
		_centerpiece_locked = bool(params["follow_centerpiece"])
	if params.has("centerpiece_locked"):
		_centerpiece_locked = bool(params["centerpiece_locked"])
	if params.has("env_scale") or params.has("environment_scale"):
		var top_scale := float(params.get("env_scale", params.get("environment_scale", 1.0)))
		var env_cfg: Dictionary = (_layer_configs.get("environment", {}) as Dictionary).duplicate(true)
		env_cfg["user_scale"] = top_scale
		_layer_configs["environment"] = env_cfg
	var user_center_dist := params.has("center_distance")
	if user_center_dist:
		_center_distance = float(params["center_distance"])
	if is_inside_tree():
		if _rig:
			_rig.fly_speed = fly_speed
		_rebuild_all()
		_apply_lighting_config(_lighting_config)
		if user_center_dist:
			_center_distance = float(params["center_distance"])


func set_layer_source(layer_id: String, config: Dictionary) -> void:
	if layer_id == "lighting":
		_lighting_config = config.duplicate(true)
		if is_inside_tree():
			_apply_lighting_config(_lighting_config)
		return
	if layer_id not in ["environment", "scatter", "centerpiece"]:
		push_warning("FlythroughEnvironment: unknown layer %s" % layer_id)
		return
	_layer_configs[layer_id] = config.duplicate(true)
	if not is_inside_tree():
		return
	match layer_id:
		"environment":
			_rebuild_environment()
			_rebuild_path_from_environment(true)
			_rebuild_scatter()
			_place_centerpiece()
		"scatter":
			_rebuild_scatter()
		"centerpiece":
			_rebuild_centerpiece()
			_place_centerpiece()


func get_layer_config(layer_id: String) -> Dictionary:
	if layer_id == "lighting":
		return _lighting_config.duplicate(true)
	return (_layer_configs.get(layer_id, {}) as Dictionary).duplicate(true)


func handle_look_input(event: InputEvent) -> void:
	if _rig:
		_rig.handle_look_input(event)


func _build_world() -> void:
	_world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.42)
	env.ambient_light_energy = 0.7
	env.fog_enabled = false
	env.fog_light_color = Color(0.08, 0.09, 0.11)
	env.fog_density = 0.0
	env.fog_sky_affect = 0.0
	# Glow washes textured albedo — keep off by default (HDRI / studio stay clean).
	env.glow_enabled = false
	env.glow_intensity = 0.2
	env.glow_bloom = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	_world_env.environment = env
	add_child(_world_env)

	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.near = 0.05
	_camera.far = 200.0
	_camera.current = true
	add_child(_camera)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = false
	add_child(_sun)

	_light = OmniLight3D.new()
	_light.light_color = _accent
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
	_apply_lighting_config(_lighting_config)


func _color_from_dict(data: Variant, fallback: Color) -> Color:
	if data is Color:
		return data as Color
	if data is Dictionary:
		var d: Dictionary = data
		return Color(
			float(d.get("r", fallback.r)),
			float(d.get("g", fallback.g)),
			float(d.get("b", fallback.b)),
			float(d.get("a", 1.0))
		)
	return fallback


func _vec3_from_dict(data: Variant, fallback: Vector3) -> Vector3:
	if data is Vector3:
		return data as Vector3
	if data is Dictionary:
		var d: Dictionary = data
		return Vector3(
			float(d.get("x", fallback.x)),
			float(d.get("y", fallback.y)),
			float(d.get("z", fallback.z))
		)
	return fallback


func _apply_lighting_config(config: Dictionary) -> void:
	if _world_env == null or _world_env.environment == null:
		return
	var cfg: Dictionary = config if not config.is_empty() else FlythroughAssetCatalog.default_lighting_config()
	var env: Environment = _world_env.environment
	_base_sun_energy = float(cfg.get("sun_energy", 1.1))
	_base_sun_color = _color_from_dict(cfg.get("sun_color", {}), Color(1.0, 0.96, 0.9))
	_base_fill_energy = float(cfg.get("fill_energy", 1.0))
	var use_hdri := bool(cfg.get("use_hdri", false)) or str(cfg.get("hdri_path", "")).strip_edges() != ""
	# Neutral fill — no cool/blue bias that washes textured albedo.
	_accent = _base_sun_color.lerp(Color(0.94, 0.94, 0.96), 0.35)

	if _sun:
		_sun.light_energy = _base_sun_energy
		_sun.light_color = _base_sun_color
		_sun.rotation_degrees = _vec3_from_dict(cfg.get("sun_rotation_deg", {}), Vector3(-42.0, 35.0, 0.0))
	if _light:
		_light.light_energy = _base_fill_energy
		_light.light_color = _accent

	var ambient := _color_from_dict(cfg.get("ambient_color", {}), Color(0.55, 0.55, 0.56))
	var fog_density := float(cfg.get("fog_density", 0.0))
	env.fog_density = fog_density
	env.fog_enabled = fog_density > 0.00015
	env.fog_light_color = ambient.darkened(0.45)
	env.fog_sky_affect = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = float(cfg.get("tonemap_exposure", 1.0))
	env.glow_enabled = false
	_base_bg_energy = float(cfg.get("background_energy", 1.0))
	env.background_energy_multiplier = _base_bg_energy
	_base_ambient_color = ambient

	var hdri_path := str(cfg.get("hdri_path", "")).strip_edges()
	if use_hdri and not hdri_path.is_empty():
		var panorama := _load_hdri_texture(hdri_path)
		if panorama != null:
			env.background_mode = Environment.BG_SKY
			var sky := Sky.new()
			var mat := PanoramaSkyMaterial.new()
			mat.panorama = panorama
			_base_sky_energy = float(cfg.get("sky_energy", 1.0))
			mat.energy_multiplier = _base_sky_energy
			sky.sky_material = mat
			env.sky = sky
			env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			env.ambient_light_sky_contribution = 1.0
			# Milder ambient so IBL doesn't crush albedo detail.
			_base_ambient_energy = float(cfg.get("ambient_energy", 0.55))
			env.ambient_light_energy = _base_ambient_energy
			env.ambient_light_color = Color(1, 1, 1)
			env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
			# HDRI must read as sky — keep fog off the panorama.
			env.fog_sky_affect = 0.0
			if fog_density <= 0.00015:
				env.fog_enabled = false
			return
		push_warning("FlythroughEnvironment: HDRI missing or unloadable: %s" % hdri_path)

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	_base_ambient_energy = float(cfg.get("ambient_energy", 0.7))
	env.ambient_light_energy = _base_ambient_energy
	_base_sky_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED

	var use_sky := bool(cfg.get("use_sky", false))
	if use_sky:
		env.background_mode = Environment.BG_SKY
		var sky2 := Sky.new()
		var mat2 := ProceduralSkyMaterial.new()
		mat2.sky_top_color = _color_from_dict(cfg.get("sky_top", {}), Color(0.45, 0.48, 0.52))
		mat2.sky_horizon_color = _color_from_dict(cfg.get("sky_horizon", {}), Color(0.65, 0.66, 0.68))
		mat2.ground_bottom_color = _color_from_dict(cfg.get("bg_color", {}), Color(0.08, 0.08, 0.09))
		mat2.ground_horizon_color = mat2.sky_horizon_color.darkened(0.2)
		mat2.sun_angle_max = 30.0
		mat2.sky_energy_multiplier = float(cfg.get("sky_energy", 1.0))
		_base_sky_energy = float(cfg.get("sky_energy", 1.0))
		sky2.sky_material = mat2
		env.sky = sky2
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = _color_from_dict(cfg.get("bg_color", {}), Color(0.08, 0.08, 0.09))
		env.sky = null


func _load_hdri_texture(path: String) -> Texture2D:
	var resolved := path.replace("\\", "/")
	if resolved.begins_with("res://") or resolved.begins_with("user://"):
		if ResourceLoader.exists(resolved):
			var res: Resource = load(resolved)
			if res is Texture2D:
				return res as Texture2D
	var file_path := resolved
	if file_path.begins_with("res://") or file_path.begins_with("user://"):
		file_path = ProjectSettings.globalize_path(file_path)
	if not FileAccess.file_exists(file_path):
		return null
	var img: Image = Image.load_from_file(file_path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


func _setup_particle_systems() -> void:
	_center_particles = _make_layer_particles(320, 1.4)
	_center_root.add_child(_center_particles)

	_env_particles = _make_layer_particles(700, 2.2)
	_env_root.add_child(_env_particles)

	_scatter_particles = _make_layer_particles(500, 1.8)
	_scatter_root.add_child(_scatter_particles)


func _make_layer_particles(amount: int, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.15
	p.visibility_aabb = AABB(Vector3(-80, -80, -80), Vector3(160, 160, 160))
	p.local_coords = true
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.07, 0.07, 0.07)
	p.draw_pass_1 = mesh
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 1.0
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.2
	mat.initial_velocity_max = 3.5
	mat.gravity = Vector3(0, -0.35, 0)
	mat.scale_min = 0.35
	mat.scale_max = 1.6
	mat.color = Color(0.95, 0.95, 1.0)
	p.process_material = mat
	return p


func _rebuild_all() -> void:
	_clear_noise_deform()
	_rebuild_environment()
	_rebuild_path_from_environment(true)
	_rebuild_scatter()
	_rebuild_centerpiece()
	_place_centerpiece()
	_apply_lighting_config(_lighting_config)
	if _rig and _camera and _curve:
		_rig.fly_speed = fly_speed
		_rig.setup(_camera, _curve)


func _rebuild_environment() -> void:
	_clear_noise_deform()
	for child in _env_root.get_children():
		if child == _env_particles:
			continue
		_env_root.remove_child(child)
		child.free()
	_terrain_meta = {}
	_env_fit_scale = 1.0
	_mat_cache.clear()
	var config: Dictionary = _layer_configs.get("environment", {})
	_env_user_scale = clampf(float(config.get("user_scale", config.get("scale", 1.0))), 0.05, 50.0)
	_env_root.scale = Vector3.ONE * _env_user_scale
	var source := FlythroughLayerSlot.resolve_source_string(config)
	if source.is_empty():
		source = FlythroughAssetCatalog.default_environment_path()
	if FlythroughLayerSlot.is_file_path(source):
		var node := FlythroughLayerSlot.load_asset_into(_env_root, source, {"role": "environment", "billboard": false})
		if node:
			_fit_environment_node(node)
	elif FlythroughHTerrainBuilder.is_hterrain_kind(source):
		_terrain_meta = FlythroughHTerrainBuilder.spawn(_env_root, source)
		_update_framing_from_environment()
	elif FlythroughLayerSlot.is_primitive_source(source):
		var kind := FlythroughLayerSlot.normalize_primitive(source)
		FlythroughPrimitives.spawn_environment(kind, _env_root)
		_update_framing_from_environment()
	else:
		FlythroughPrimitives.spawn_environment("box_corridor", _env_root)
		_update_framing_from_environment()
	_env_particles_on = false
	_sync_particles()


func _fit_environment_node(node: Node3D) -> void:
	## Always normalize imported envs to a shared target size, then multiply by user_scale on root.
	var aabb := FlythroughLayerSlot.compute_aabb(node)
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if longest <= 0.001:
		_env_fit_scale = 1.0
		return
	var target := clampf(ENV_TARGET_LONGEST, ENV_MIN_LONGEST, ENV_MAX_LONGEST)
	FlythroughLayerSlot.fit_node_to_size(node, target)
	_env_fit_scale = target / longest
	_update_framing_from_environment()


func set_environment_user_scale(scale_val: float) -> void:
	_env_user_scale = clampf(scale_val, 0.05, 50.0)
	var cfg: Dictionary = (_layer_configs.get("environment", {}) as Dictionary).duplicate(true)
	cfg["user_scale"] = _env_user_scale
	_layer_configs["environment"] = cfg
	_apply_env_display_scale()
	# Path/framing stay at auto-fit size so user_scale visibly changes mesh vs camera.
	_update_framing_from_environment()
	_place_centerpiece()


func _apply_env_display_scale(reactive_vec: Vector3 = Vector3.ONE) -> void:
	if _env_root == null or not _terrain_meta.is_empty():
		return
	_env_root.scale = reactive_vec * _env_user_scale


func _fit_aabb_ignoring_user_scale() -> AABB:
	## Path/framing must ignore user_scale — otherwise scale + path grow together and look unchanged.
	if _env_root == null:
		return AABB(Vector3(-2, -2, -30), Vector3(4, 4, 60))
	var saved := _env_root.scale
	var p_vis := true
	if _env_particles:
		p_vis = _env_particles.visible
		_env_particles.visible = false
	_env_root.scale = Vector3.ONE
	var aabb := FlythroughLayerSlot.compute_aabb(_env_root)
	_env_root.scale = saved
	if _env_particles:
		_env_particles.visible = p_vis
	return aabb


func _update_framing_from_environment() -> void:
	var aabb := _fit_aabb_ignoring_user_scale()
	if aabb.size.length() < 0.01 and not _terrain_meta.is_empty():
		return
	var horiz := maxf(aabb.size.x, aabb.size.z)
	_scatter_side_range = clampf(horiz * 0.08, 1.2, 10.0)
	# Keep hero readable relative to fit size (not user_scale).
	_center_distance = clampf(2.4 + horiz * 0.012, 2.2, 4.5)
	if _camera:
		var span := maxf(horiz, aabb.size.y)
		_camera.far = maxf(200.0, span * 4.0 + 80.0)
		_camera.near = 0.05


func _rebuild_path_from_environment(reset_progress: bool = true) -> void:
	var config: Dictionary = _layer_configs.get("environment", {})
	var source := FlythroughLayerSlot.resolve_source_string(config)
	var kind := FlythroughLayerSlot.normalize_primitive(source) if FlythroughLayerSlot.is_primitive_source(source) else ""
	if not _terrain_meta.is_empty():
		_curve = FlythroughHTerrainBuilder.build_flight_path(_terrain_meta)
	elif kind == "flat_plane":
		_curve = FlythroughPathBuilder.overland(80.0, 8.0)
	elif FlythroughLayerSlot.is_file_path(source):
		var aabb := _fit_aabb_ignoring_user_scale()
		var min_half := clampf(10.0 * clampf(_env_fit_scale, 0.25, 4.0), 8.0, 28.0)
		_curve = FlythroughPathBuilder.from_aabb(aabb, 0.12, min_half)
		_update_framing_from_environment()
	else:
		_curve = FlythroughPathBuilder.straight(60.0, 0.0)
	if _camera and _curve:
		var path_len := _curve.get_baked_length()
		_camera.far = maxf(_camera.far, path_len * 1.5 + 60.0)
		_camera.current = true
	if _rig and _camera:
		_rig.set_curve(_curve, reset_progress)


func _rebuild_centerpiece() -> void:
	_clear_noise_deform()
	for child in _center_root.get_children():
		if child == _center_particles:
			continue
		_center_root.remove_child(child)
		child.free()
	_centerpiece_mesh = null
	_mat_cache.clear()
	var config: Dictionary = _layer_configs.get("centerpiece", {})
	var source := FlythroughLayerSlot.resolve_source_string(config)
	# Explicit empty source = no main character (three-tab solo env play).
	if source.is_empty():
		_center_particles_on = false
		_sync_particles()
		return
	if FlythroughLayerSlot.is_file_path(source):
		var node := FlythroughLayerSlot.load_asset_into(_center_root, source, {"role": "centerpiece", "billboard": false})
		if node:
			_center_base_scale = FlythroughLayerSlot.fit_node_to_size(node, 1.6)
	elif FlythroughLayerSlot.is_primitive_source(source):
		var kind := FlythroughLayerSlot.normalize_primitive(source)
		_centerpiece_mesh = FlythroughPrimitives.spawn_centerpiece(kind, _center_root)
		_center_base_scale = Vector3.ONE
	else:
		_centerpiece_mesh = FlythroughPrimitives.spawn_centerpiece("torus", _center_root)
		_center_base_scale = Vector3.ONE
	_raise_centerpiece_priority(_center_root)
	_center_particles_on = false  # force resync
	_sync_particles()


func _raise_centerpiece_priority(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.sorting_offset = 2.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bump_mesh_render_priority(mi, 16)
	for child in node.get_children():
		_raise_centerpiece_priority(child)


func _bump_mesh_render_priority(mi: MeshInstance3D, priority: int) -> void:
	## Preserve imported textures: never replace with a flat material_override.
	if mi.material_override is Material:
		var ov := (mi.material_override as Material).duplicate() as Material
		ov.render_priority = priority
		mi.material_override = ov
		return
	if mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		var base := mi.get_active_material(s)
		if base == null:
			continue
		var mat := base.duplicate() as Material
		mat.render_priority = priority
		mi.set_surface_override_material(s, mat)


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
	# Slow idle spin only when Rotation target is off — schedule inactive must mute, not idle-Y.
	if delta > 0.0 and _center_root.get_child_count() > 0 and not RH.affect_rotation():
		var child := _center_root.get_child(0)
		if child is Node3D and child != _center_particles:
			(child as Node3D).rotate_y(delta * 0.4)


func _rebuild_scatter() -> void:
	_clear_noise_deform()
	for child in _scatter_root.get_children():
		if child == _scatter_particles:
			continue
		_scatter_root.remove_child(child)
		child.free()
	_scatter_nodes.clear()
	_scatter_base_scales.clear()
	_scatter_base_positions.clear()
	_mat_cache.clear()
	if _curve == null:
		return
	var config: Dictionary = _layer_configs.get("scatter", {})
	var count := int(config.get("count", 18))
	count = clampi(count, 0, 80)
	var length := _curve.get_baked_length()
	if length <= 0.01 or count <= 0:
		_scatter_particles_on = false
		_sync_particles()
		return
	var source := FlythroughLayerSlot.resolve_source_string(config)
	if source.is_empty():
		_scatter_particles_on = false
		_sync_particles()
		return

	var template_mesh: Mesh = null
	var template_mat: Material = null
	var use_file := FlythroughLayerSlot.is_file_path(source)
	var use_media := FlythroughLayerSlot.is_media_path(source)
	var packed_scene: PackedScene = null
	var media_master: Node3D = null
	var media_base_scale := Vector3.ONE
	if use_file and not use_media:
		var res_path := source.replace("\\", "/")
		if ResourceLoader.exists(res_path):
			var res: Resource = load(res_path)
			if res is PackedScene:
				packed_scene = res as PackedScene

	if use_media:
		media_master = _MEDIA_PROP.spawn(_scatter_root, source, {"role": "scatter", "billboard": true}) as Node3D
		if media_master == null:
			_scatter_particles_on = false
			_sync_particles()
			return
		FlythroughLayerSlot.fit_node_to_size(media_master, 0.85)
		media_base_scale = media_master.scale
	elif use_file:
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
		var offset := side * rng.randf_range(-_scatter_side_range, _scatter_side_range) \
			+ up * rng.randf_range(-_scatter_side_range * 0.5, _scatter_side_range * 0.55)
		var inst: Node3D
		if use_media:
			if i == 0:
				inst = media_master
			else:
				var clone: MeshInstance3D = null
				if media_master.has_method("make_mesh_clone"):
					clone = media_master.call("make_mesh_clone", _scatter_root) as MeshInstance3D
				if clone == null:
					continue
				inst = clone
			inst.scale = media_base_scale
		elif use_file:
			if packed_scene:
				var n := packed_scene.instantiate()
				_scatter_root.add_child(n)
				inst = n as Node3D
				if inst == null:
					n.queue_free()
					continue
			else:
				inst = FlythroughLayerSlot.load_asset_into(_scatter_root, source, {"role": "scatter", "billboard": true})
			if inst == null:
				continue
			FlythroughLayerSlot.fit_node_to_size(inst, 0.85)
		else:
			var mesh_inst := MeshInstance3D.new()
			mesh_inst.mesh = template_mesh
			mesh_inst.material_override = template_mat
			_scatter_root.add_child(mesh_inst)
			inst = mesh_inst
		inst.position = path_xf.origin + offset
		inst.scale = inst.scale * rng.randf_range(0.75, 1.25)
		_scatter_nodes.append(inst)
		_scatter_base_scales.append(inst.scale)
		_scatter_base_positions.append(inst.position)
	_scatter_particles_on = false
	_sync_particles()


func _process(delta: float) -> void:
	_noise_t += delta
	if _rig:
		_rig.fly_speed = fly_speed
		_rig.advance(delta)
	if _camera and _light:
		_light.global_position = _camera.global_position + Vector3(0, 1.2, 0)
	_update_centerpiece_transform(delta)
	_sync_particles()


func _sync_particles() -> void:
	var want_center := RH.particles_applies_to("centerpiece")
	var want_env := RH.particles_applies_to("environment")
	var want_scatter := RH.particles_applies_to("scatter")
	if want_center != _center_particles_on:
		_center_particles_on = want_center
		if want_center:
			_bind_particles_to_root(_center_particles, _center_root, [_center_particles], 0.85)
		if _center_particles:
			_center_particles.emitting = want_center
			_center_particles.visible = want_center
		_set_centerpiece_mesh_visible(not want_center)
	if want_env != _env_particles_on:
		_env_particles_on = want_env
		if want_env:
			_bind_particles_to_root(_env_particles, _env_root, [_env_particles], 2.5)
		if _env_particles:
			_env_particles.emitting = want_env
			_env_particles.visible = want_env
		_set_env_mesh_visible(not want_env)
	if want_scatter != _scatter_particles_on:
		_scatter_particles_on = want_scatter
		if want_scatter:
			_bind_particles_to_root(_scatter_particles, _scatter_root, [_scatter_particles], 1.2)
		if _scatter_particles:
			_scatter_particles.emitting = want_scatter
			_scatter_particles.visible = want_scatter
		_set_scatter_mesh_visible(not want_scatter)


func _set_env_mesh_visible(vis: bool) -> void:
	if _env_root == null:
		return
	for child in _env_root.get_children():
		if child == _env_particles:
			continue
		if child is Node3D:
			(child as Node3D).visible = vis


func _set_centerpiece_mesh_visible(vis: bool) -> void:
	for child in _center_root.get_children():
		if child == _center_particles:
			continue
		if child is Node3D:
			(child as Node3D).visible = vis


func _set_scatter_mesh_visible(vis: bool) -> void:
	for node in _scatter_nodes:
		if is_instance_valid(node):
			node.visible = vis


func _bind_particles_to_root(particles: GPUParticles3D, root: Node3D, exclude: Array, fallback_radius: float) -> void:
	if particles == null or root == null:
		return
	var points := PackedVector3Array()
	_collect_mesh_points_local(root, root, points, exclude, 2200)
	var mat := particles.process_material as ParticleProcessMaterial
	if mat == null:
		return
	particles.position = Vector3.ZERO
	particles.rotation = Vector3.ZERO
	particles.scale = Vector3.ONE
	if points.size() >= 8:
		var tex := _points_to_emission_texture(points)
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
		mat.emission_point_texture = tex
		mat.emission_point_count = points.size()
		particles.amount = clampi(points.size(), 120, 1800)
		var aabb := AABB(points[0], Vector3.ZERO)
		for p in points:
			aabb = aabb.expand(p)
		particles.visibility_aabb = aabb.grow(4.0)
	else:
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		mat.emission_sphere_radius = fallback_radius
		mat.emission_point_texture = null
		mat.emission_point_count = 1
		particles.amount = clampi(int(220 * fallback_radius), 160, 900)
		particles.visibility_aabb = AABB(Vector3(-fallback_radius, -fallback_radius, -fallback_radius) * 3.0, Vector3.ONE * fallback_radius * 6.0)
	particles.restart()


func _collect_mesh_points_local(node: Node, space_root: Node3D, out: PackedVector3Array, exclude: Array, budget: int) -> void:
	if out.size() >= budget:
		return
	if node in exclude:
		pass
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var xf := space_root.global_transform.affine_inverse() * mi.global_transform
			for s in mi.mesh.get_surface_count():
				if out.size() >= budget:
					break
				var arrays := mi.mesh.surface_get_arrays(s)
				if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
					continue
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var step := maxi(1, int(ceili(float(verts.size()) / 400.0)))
				var i := 0
				while i < verts.size() and out.size() < budget:
					out.append(xf * verts[i])
					i += step
	for child in node.get_children():
		if out.size() >= budget:
			return
		_collect_mesh_points_local(child, space_root, out, exclude, budget)


func _points_to_emission_texture(points: PackedVector3Array) -> ImageTexture:
	var n := points.size()
	var w := int(ceili(sqrt(float(n))))
	w = maxi(w, 1)
	var h := int(ceili(float(n) / float(w)))
	h = maxi(h, 1)
	var img := Image.create(w, h, false, Image.FORMAT_RGBAF)
	img.fill(Color(0, 0, 0, 0))
	for i in n:
		var p := points[i]
		img.set_pixel(i % w, int(i / w), Color(p.x, p.y, p.z, 1.0))
	return ImageTexture.create_from_image(img)

func apply_audio_state(state: AudioState) -> void:
	_sync_particles()
	if not RH.enabled():
		_reset_reactive_scales()
		_clear_noise_deform()
		return

	var lfo := float(RH.get_field("lfo_mod01", 0.0))
	var light_drive := RH.drive_value("light", state, lfo) if RH.property_active("light") else 0.0
	# Lights react when "What reacts" includes lights (or Everything).
	# Primary: HDRI / sky / ambient energy. Secondary: sun + fill.
	if RH.property_active("light") and RH.applies_to("lights"):
		var noise_mul := 1.0
		if RH.noise_applies_to("lights"):
			noise_mul = 1.0 + _sample_noise(0.5, 9.0) * (RH.noise_amount() / 35.0) * 1.5
		var bright := (0.35 + light_drive * 2.8) * noise_mul
		_apply_hdri_energy(bright)
		if _light:
			_light.light_energy = _base_fill_energy * bright
			_light.omni_range = 14.0 + light_drive * 40.0
			_light.light_color = _accent
		if _sun:
			_sun.light_energy = _base_sun_energy * bright
			_sun.light_color = _base_sun_color
	else:
		_apply_hdri_energy(1.0)
		if _light:
			_light.light_energy = _base_fill_energy
			_light.light_color = _accent
		if _sun:
			_sun.light_energy = _base_sun_energy
			_sun.light_color = _base_sun_color

	if RH.applies_to("environment"):
		_apply_environment_audio(state, lfo)
	else:
		_apply_env_display_scale()
		_reset_layer_emission(_env_root)
	if RH.applies_to("scatter"):
		_apply_scatter_audio(state, lfo)
	else:
		_reset_scatter_scales()
		for node in _scatter_nodes:
			if is_instance_valid(node):
				_reset_layer_emission(node)
	if RH.applies_to("centerpiece"):
		_apply_centerpiece_audio(state, lfo)
	else:
		_reset_centerpiece_scale()
		var cnode := _centerpiece_content_node()
		if cnode:
			_reset_layer_emission(cnode)

	_apply_noise_distort(state, lfo)
	_drive_particle_systems(state)


func _apply_hdri_energy(mul: float) -> void:
	## Drive panorama / sky / ambient / background energy so “Lights” clearly brightens HDRI.
	if _world_env == null or _world_env.environment == null:
		return
	var env: Environment = _world_env.environment
	var m := maxf(mul, 0.05)
	env.ambient_light_energy = _base_ambient_energy * m
	env.background_energy_multiplier = _base_bg_energy * m
	if env.sky and env.sky.sky_material:
		var sm: Material = env.sky.sky_material
		if sm is PanoramaSkyMaterial:
			(sm as PanoramaSkyMaterial).energy_multiplier = _base_sky_energy * m
		elif sm is ProceduralSkyMaterial:
			(sm as ProceduralSkyMaterial).sky_energy_multiplier = _base_sky_energy * m


func _drive_particle_systems(state: AudioState) -> void:
	if _center_particles_on and _center_particles:
		_center_particles.amount = clampi(int(200 + state.bass * 900), 120, 1600)
		if _center_particles.process_material is ParticleProcessMaterial:
			var pm: ParticleProcessMaterial = _center_particles.process_material
			pm.initial_velocity_max = 2.0 + state.energy * 10.0
			pm.color = Color.from_hsv(fposmod(state.mids, 1.0), 0.7, 1.0)
		if state.beat:
			_center_particles.restart()
	if _env_particles_on and _env_particles:
		_env_particles.amount = clampi(int(400 + state.energy * 1200), 200, 2000)
		if _env_particles.process_material is ParticleProcessMaterial:
			var epm: ParticleProcessMaterial = _env_particles.process_material
			epm.initial_velocity_max = 1.5 + state.highs * 9.0
			epm.color = Color.from_hsv(fposmod(0.4 + state.highs * 0.5, 1.0), 0.65, 1.0)
		if state.beat:
			_env_particles.restart()
	if _scatter_particles_on and _scatter_particles:
		_scatter_particles.amount = clampi(int(280 + state.mids * 1000), 160, 1800)
		if _scatter_particles.process_material is ParticleProcessMaterial:
			var spm: ParticleProcessMaterial = _scatter_particles.process_material
			spm.initial_velocity_max = 1.2 + state.highs * 8.0
			spm.color = Color.from_hsv(fposmod(0.15 + state.bass * 0.5, 1.0), 0.7, 1.0)
		if state.beat:
			_scatter_particles.restart()


func _apply_environment_audio(state: AudioState, lfo: float) -> void:
	if RH.property_active("rotation") and _env_root:
		var rd := RH.drive_value("rotation", state, lfo)
		# Terrain: slower orbit. Non-terrain: mild. Amount + axes from settings.
		var mul := 0.55 if not _terrain_meta.is_empty() else 1.0
		var rate := RH.rotation_rate(rd) * mul
		_apply_axis_rotation(_env_root, rate, true)
	if RH.property_active("scale") and _terrain_meta.is_empty():
		var sd := RH.drive_value("scale", state, lfo)
		# Keep env readable in frame — still punchy at mid/high Scale Amount.
		var amt := clampf(RH.scale_multiplier(sd), 0.35, 8.0)
		_apply_env_display_scale(RH.scale_vector(amt))
	else:
		_apply_env_display_scale()
	if RH.property_active("emission"):
		var ed := RH.drive_value("emission", state, lfo)
		_drive_mesh_emission(_env_root, ed, false)
		_drive_ambient_tint(ed)
	else:
		_reset_layer_emission(_env_root)


func _apply_centerpiece_audio(state: AudioState, lfo: float) -> void:
	var node := _centerpiece_content_node()
	if node == null:
		return
	if RH.property_active("scale") and not _center_particles_on:
		var d := RH.drive_value("scale", state, lfo)
		if state.beat:
			d = minf(d * 1.35, 1.0)
		var amt := RH.scale_multiplier(d)
		node.scale = _center_base_scale * RH.scale_vector(amt)
	elif not _center_particles_on:
		_reset_centerpiece_scale()
	if RH.property_active("rotation") and not _center_particles_on:
		var rd := RH.drive_value("rotation", state, lfo)
		var rate := RH.rotation_rate(rd) * 1.15
		_apply_axis_rotation(node, rate, false)
	if RH.property_active("emission") and not _center_particles_on:
		var ed := RH.drive_value("emission", state, lfo)
		_drive_mesh_emission(node, ed, true)
		_drive_ambient_tint(ed)
	else:
		_reset_layer_emission(node)


func _centerpiece_content_node() -> Node3D:
	for child in _center_root.get_children():
		if child == _center_particles:
			continue
		if child is Node3D:
			return child as Node3D
	return null


func _apply_axis_rotation(node: Node3D, rate: float, track_env_accum: bool) -> void:
	## Spin only the enabled X/Y/Z axes. rate is radians per audio frame (~per display frame).
	if node == null:
		return
	var axes := RH.rotation_axis_mask()
	if axes.length_squared() < 0.01:
		return
	# Small floor so axis toggles stay obvious when the band is quiet.
	var r := maxf(rate, (RH.rotation_amount() / 20.0) * 0.01)
	if axes.x > 0.0:
		node.rotate_x(r * axes.x)
	if axes.y > 0.0:
		node.rotate_y(r * axes.y)
	if axes.z > 0.0:
		node.rotate_z(r * axes.z)
	if track_env_accum:
		_rot_accum_env = node.rotation


func _apply_scatter_audio(state: AudioState, lfo: float) -> void:
	if RH.property_active("scale") and not _scatter_particles_on:
		var d := RH.drive_value("scale", state, lfo)
		var amt := RH.scale_multiplier(d)
		var scale_vec := RH.scale_vector(amt)
		for i in _scatter_nodes.size():
			if not is_instance_valid(_scatter_nodes[i]):
				continue
			var base: Vector3 = _scatter_base_scales[i] if i < _scatter_base_scales.size() else Vector3.ONE
			_scatter_nodes[i].scale = base * scale_vec
	elif not _scatter_particles_on:
		_reset_scatter_scales()
	if RH.property_active("rotation") and not _scatter_particles_on:
		var rd := RH.drive_value("rotation", state, lfo)
		var rate := RH.rotation_rate(rd) * 0.95
		for node in _scatter_nodes:
			if is_instance_valid(node):
				_apply_axis_rotation(node, rate, false)
	if RH.property_active("emission") and not _scatter_particles_on:
		var ed := RH.drive_value("emission", state, lfo)
		for node in _scatter_nodes:
			if is_instance_valid(node):
				_drive_mesh_emission(node, ed, true)
		_drive_ambient_tint(ed)
	else:
		for node in _scatter_nodes:
			if is_instance_valid(node):
				_reset_layer_emission(node)


func _reset_layer_emission(root: Node) -> void:
	if root == null:
		return
	var key_nodes: Array = []
	_collect_mesh_instances(root, key_nodes)
	for mi in key_nodes:
		if not (mi is MeshInstance3D):
			continue
		var mid := (mi as MeshInstance3D).get_instance_id()
		if not _mat_cache.has(mid):
			continue
		var mats: Array = _mat_cache[mid]
		for mat in mats:
			if mat is BaseMaterial3D:
				(mat as BaseMaterial3D).emission_energy_multiplier = 0.0
				(mat as BaseMaterial3D).emission_enabled = false


func _collect_mesh_instances(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out)


func _drive_mesh_emission(root: Node, drive01: float, allow_untextured_tint: bool) -> void:
	## Per-surface emission/color. Textured albedos stay put; untextured can tint when allowed.
	if root == null:
		return
	var d := clampf(drive01, 0.0, 1.0)
	d = clampf(pow(d, 0.45) * 1.2, 0.0, 1.0)
	var emit_col := Color.from_hsv(fposmod(0.55 + d * 0.35, 1.0), 0.55, 1.0)
	_drive_mesh_emission_recursive(root, d, emit_col, allow_untextured_tint)


func _drive_ambient_tint(drive01: float) -> void:
	## Make Emission / Color visibly shift sky/ambient so the control isn't a no-op on textured scenes.
	if _world_env == null or _world_env.environment == null:
		return
	var env: Environment = _world_env.environment
	var d := clampf(drive01, 0.0, 1.0)
	var tint := Color.from_hsv(fposmod(0.08 + d * 0.55, 1.0), 0.35 + d * 0.4, 1.0)
	env.ambient_light_color = _base_ambient_color.lerp(tint, d * 0.85)
	if env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY:
		env.ambient_light_color = Color(1, 1, 1).lerp(tint, d * 0.65)


func _drive_mesh_emission_recursive(node: Node, drive01: float, emit_col: Color, allow_untextured_tint: bool) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mats := _materials_for_mesh(mi)
		for mat in mats:
			if mat == null:
				continue
			mat.emission_enabled = true
			mat.emission = emit_col
			mat.emission_energy_multiplier = 0.35 + drive01 * 6.5
			if allow_untextured_tint and mat.albedo_texture == null:
				mat.albedo_color = mat.albedo_color.lerp(emit_col, drive01 * 0.55)
			elif drive01 > 0.05:
				# Textured meshes still get a readable glow without full albedo wash.
				mat.emission_energy_multiplier = 0.8 + drive01 * 5.0
	for child in node.get_children():
		_drive_mesh_emission_recursive(child, drive01, emit_col, allow_untextured_tint)


func _materials_for_mesh(mi: MeshInstance3D) -> Array[BaseMaterial3D]:
	var key := mi.get_instance_id()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var out: Array[BaseMaterial3D] = []
	if mi.material_override is BaseMaterial3D:
		var ov := (mi.material_override as BaseMaterial3D).duplicate() as BaseMaterial3D
		mi.material_override = ov
		out.append(ov)
	elif mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s)
			if base is BaseMaterial3D:
				var dup := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
				mi.set_surface_override_material(s, dup)
				out.append(dup)
	_mat_cache[key] = out
	return out


func _sample_noise(x: float, y: float) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 77
		_noise.frequency = 0.85
	return _noise.get_noise_2d(_noise_t * 2.5 + x * 17.0, y * 13.0)


func _apply_noise_distort(state: AudioState, lfo: float) -> void:
	if not RH.property_active("noise"):
		_clear_noise_deform()
		return
	var drive := RH.drive_value("noise", state, lfo)
	# noise_amount (UI: how much) strongly controls visible displace; audio/LFO boosts within that budget.
	var strength := clampf(RH.noise_amount() / 100.0, 0.0, 1.0)
	var amt := strength * (4.0 + drive * 36.0)
	var feature := maxf(RH.noise_scale(), 0.5)
	var axes := RH.noise_axis_mask()
	if axes.length_squared() < 0.01 or strength < 0.005:
		_clear_noise_deform()
		return
	var want_env := RH.noise_applies_to("environment") and _env_root != null
	var want_center := RH.noise_applies_to("centerpiece") and not _center_particles_on
	var want_scatter := RH.noise_applies_to("scatter") and not _scatter_particles_on
	if _env_root and _terrain_meta.is_empty():
		# Don't clobber reactive multi-axis rotation on the env root.
		if not RH.property_active("rotation"):
			_env_root.rotation_degrees.x = 0.0
			_env_root.rotation_degrees.z = 0.0
		_env_root.position = Vector3.ZERO
	var cnode := _centerpiece_content_node()
	if cnode and not RH.property_active("rotation"):
		cnode.position = Vector3.ZERO
		cnode.rotation_degrees.x = 0.0
		cnode.rotation_degrees.z = 0.0
	for i in _scatter_nodes.size():
		if is_instance_valid(_scatter_nodes[i]) and i < _scatter_base_positions.size():
			_scatter_nodes[i].position = _scatter_base_positions[i]

	var active_ids: Dictionary = {}
	# HTerrain uses DirectMeshInstance chunks — vertex shader overrides don't apply.
	# Approximate displace via root transform wobble so mountains still react.
	if want_env and not _terrain_meta.is_empty():
		_apply_terrain_noise_wobble(amt, axes)
	elif want_env:
		_apply_noise_to_root(_env_root, amt, feature, Vector3(0.1, 0.2, 0.3), axes, active_ids)
	if want_center and cnode:
		_apply_noise_to_root(cnode, amt * 0.85, feature * 0.7, Vector3(1.1, 0.4, 0.7), axes, active_ids)
	if want_scatter:
		for i in _scatter_nodes.size():
			if not is_instance_valid(_scatter_nodes[i]):
				continue
			var nseed := Vector3(float(i) * 0.37, 2.0, float(i) * 0.19)
			_apply_noise_to_root(_scatter_nodes[i], amt * 0.75, feature * 0.85, nseed, axes, active_ids)
	_prune_noise_materials(active_ids)


func _apply_terrain_noise_wobble(amount: float, axes: Vector3) -> void:
	if _env_root == null:
		return
	var nx := _sample_noise(0.2, 1.0)
	var ny := _sample_noise(1.1, 2.4)
	var nz := _sample_noise(2.7, 0.6)
	# World-unit wobble — amount already scaled by UI "how much".
	_env_root.position = Vector3(nx, ny, nz) * axes * amount * 0.55


func _apply_noise_to_root(root: Node, amount: float, feature: float, nseed: Vector3, axes: Vector3, active_ids: Dictionary) -> void:
	if root == null or amount <= 0.001:
		return
	var meshes: Array = []
	_collect_mesh_instances(root, meshes)
	var limit := mini(meshes.size(), 96)
	for i in limit:
		var mi: MeshInstance3D = meshes[i] as MeshInstance3D
		if mi == null or not mi.visible:
			continue
		# Skip draw-pass meshes belonging to particle systems.
		if mi.get_parent() is GPUParticles3D:
			continue
		var mats := _ensure_noise_materials(mi, nseed + Vector3(float(i), 0, 0))
		active_ids[mi.get_instance_id()] = true
		for mat in mats:
			if mat is ShaderMaterial:
				var sm := mat as ShaderMaterial
				sm.set_shader_parameter("noise_amount", amount)
				sm.set_shader_parameter("noise_scale", feature)
				sm.set_shader_parameter("noise_axes", axes)
				sm.set_shader_parameter("time_sec", _noise_t)


func _ensure_noise_materials(mi: MeshInstance3D, nseed: Vector3) -> Array:
	var key := mi.get_instance_id()
	if _noise_mats.has(key):
		return _noise_mats[key]
	var backup := {"override": mi.material_override, "surfaces": []}
	var out: Array = []
	if mi.material_override != null:
		var sm := _make_noise_shader_from(mi.material_override, nseed)
		backup["override"] = mi.material_override
		mi.material_override = sm
		out.append(sm)
	elif mi.mesh != null:
		var surfaces: Array = []
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s)
			surfaces.append(mi.get_surface_override_material(s))
			var sm2 := _make_noise_shader_from(base, nseed + Vector3(float(s) * 0.13, 0, 0))
			mi.set_surface_override_material(s, sm2)
			out.append(sm2)
		backup["surfaces"] = surfaces
	_noise_backup[key] = backup
	_noise_mats[key] = out
	return out


func _make_noise_shader_from(base: Material, nseed: Vector3) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = NOISE_DEFORM_SHADER
	var alb := Color(0.75, 0.75, 0.78)
	var rough := 0.85
	var metal := 0.0
	var tex: Texture2D = null
	if base is BaseMaterial3D:
		var bm := base as BaseMaterial3D
		alb = bm.albedo_color
		rough = bm.roughness
		metal = bm.metallic
		tex = bm.albedo_texture
	sm.set_shader_parameter("albedo_color", alb)
	sm.set_shader_parameter("roughness", rough)
	sm.set_shader_parameter("metallic", metal)
	sm.set_shader_parameter("noise_seed", nseed)
	sm.set_shader_parameter("noise_amount", 0.0)
	sm.set_shader_parameter("noise_scale", 1.0)
	sm.set_shader_parameter("noise_axes", Vector3.ONE)
	if tex != null:
		sm.set_shader_parameter("albedo_tex", tex)
		sm.set_shader_parameter("use_albedo_tex", 1.0)
	else:
		sm.set_shader_parameter("use_albedo_tex", 0.0)
	return sm


func _prune_noise_materials(active_ids: Dictionary) -> void:
	var drop: Array = []
	for key in _noise_mats.keys():
		if not active_ids.has(key):
			drop.append(key)
	for key in drop:
		_restore_noise_material(int(key))


func _restore_noise_material(key: int) -> void:
	if not _noise_backup.has(key):
		_noise_mats.erase(key)
		return
	var mi_obj := instance_from_id(key)
	var backup: Dictionary = _noise_backup[key]
	if mi_obj is MeshInstance3D:
		var mi := mi_obj as MeshInstance3D
		mi.material_override = backup.get("override", null)
		var surfaces: Array = backup.get("surfaces", [])
		for s in surfaces.size():
			mi.set_surface_override_material(s, surfaces[s])
	_noise_backup.erase(key)
	_noise_mats.erase(key)


func _clear_noise_deform() -> void:
	var keys: Array = _noise_mats.keys()
	for key in keys:
		_restore_noise_material(int(key))
	_noise_mats.clear()
	_noise_backup.clear()
	if _env_root:
		_env_root.position = Vector3.ZERO
		if _terrain_meta.is_empty() and not RH.property_active("rotation"):
			_env_root.rotation_degrees.x = 0.0
			_env_root.rotation_degrees.z = 0.0
	var cnode := _centerpiece_content_node()
	if cnode:
		cnode.position = Vector3.ZERO
		if not RH.property_active("rotation"):
			cnode.rotation_degrees.x = 0.0
			cnode.rotation_degrees.z = 0.0
	for i in _scatter_nodes.size():
		if not is_instance_valid(_scatter_nodes[i]):
			continue
		if i < _scatter_base_positions.size():
			_scatter_nodes[i].position = _scatter_base_positions[i]


func _reset_reactive_scales() -> void:
	_reset_centerpiece_scale()
	_reset_scatter_scales()
	if _light:
		_light.light_energy = _base_fill_energy
		_light.light_color = _accent
	if _sun:
		_sun.light_energy = _base_sun_energy
		_sun.light_color = _base_sun_color
	_apply_env_display_scale()
	_set_centerpiece_mesh_visible(not _center_particles_on)
	_set_scatter_mesh_visible(not _scatter_particles_on)
	_set_env_mesh_visible(not _env_particles_on)


func _reset_centerpiece_scale() -> void:
	var node := _centerpiece_content_node()
	if node:
		node.scale = _center_base_scale


func _reset_scatter_scales() -> void:
	for i in _scatter_nodes.size():
		if not is_instance_valid(_scatter_nodes[i]):
			continue
		var base: Vector3 = _scatter_base_scales[i] if i < _scatter_base_scales.size() else Vector3.ONE
		_scatter_nodes[i].scale = base


func set_cue_param(key: String, value: Variant) -> void:
	match key:
		"speed", "fly_speed":
			fly_speed = float(value)
			if _rig:
				_rig.fly_speed = fly_speed
		"environment", "scatter", "centerpiece", "lighting":
			if value is Dictionary:
				set_layer_source(key, value)
		"env_scale", "environment_scale", "user_scale":
			set_environment_user_scale(float(value))
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
