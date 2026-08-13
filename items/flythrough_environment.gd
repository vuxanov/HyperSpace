extends ReactiveEnvironment
class_name FlythroughEnvironment

## Shared fly-through: path + camera + layers (environment, scatter, centerpiece, lighting).

const RH = preload("res://core/reactivity_hub.gd")
const _MEDIA_PROP := preload("res://items/flythrough/media_prop.gd")
const _AssetCache := preload("res://core/asset_cache.gd")
const _SceneMeshFx := preload("res://core/scene_mesh_fx.gd")
## Target longest AABB axis (meters) for imported environment models.
const ENV_TARGET_LONGEST := 48.0
const ENV_MIN_LONGEST := 10.0
const ENV_MAX_LONGEST := 140.0

var fly_speed: float = 12.0
## Camera path shape: auto (env-fitted straight) | circle | square | dive3d.
var path_style: String = FlythroughPathBuilder.STYLE_AUTO

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
var _center_fit_scale := Vector3.ONE
var _center_user_scale: float = 1.0
var _scatter_base_scales: Array[Vector3] = []
var _scatter_user_scale: float = 1.0
## Formation scale (volume cube + instance positions). Independent of per-item user_scale.
var _scatter_global_scale: float = 1.0
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
## Spawn / baseline orientations — restored when reactive rotation turns off.
var _env_rest_rotation := Vector3.ZERO
var _center_rest_rotation := Vector3.ZERO
var _scatter_rest_rotations: Array[Vector3] = []
var _rot_driving_env: bool = false
var _rot_driving_center: bool = false
var _rot_driving_scatter: bool = false
var _rot_driving_camera: bool = false
var _base_fill_energy: float = 1.0
var _base_sun_energy: float = 1.1
var _base_sun_color := Color(1.0, 0.96, 0.9)
var _base_sky_energy: float = 1.0
var _base_ambient_energy: float = 0.7
var _base_bg_energy: float = 1.0
var _base_ambient_color := Color(0.55, 0.55, 0.56)
## Last applied lighting identity — used to force sky RID refresh on HDRI swaps.
var _applied_lighting_key: String = ""
## Uniform scale applied to file-based environments for readable flythroughs.
var _env_fit_scale: float = 1.0
## Per-environment user scale (playlist / layer config). Multiplies after auto-fit.
var _env_user_scale: float = 1.0
var _scatter_base_positions: Array[Vector3] = []
var _noise: FastNoiseLite
var _noise_t: float = 0.0
var _center_base_local := Vector3.ZERO
var _mat_cache: Dictionary = {}  # MeshInstance3D instance_id -> Array[BaseMaterial3D]
var _noise_backup: Dictionary = {}  # MeshInstance3D instance_id -> { override, surfaces }
var _noise_mats: Dictionary = {}  # MeshInstance3D instance_id -> Array[ShaderMaterial]
## Cached mesh lists for noise (invalidated on layer rebuild).
var _noise_mesh_lists: Dictionary = {}  # root instance_id -> Array[MeshInstance3D]
var _cloth_on: bool = false
var _cloth_params: Dictionary = {}
var _point_cloud_on: bool = false
var _point_cloud_size: float = 6.0
var _point_cloud_targets: Dictionary = {
	"target_environment": true,
	"target_main": true,
	"target_scatter": true,
	"target_media": false,
}
var _pc_overlays: Array = []
var _pc_built: bool = false
var _camera_fx_on: bool = false
var _camera_fx_params: Dictionary = {}
var _particle_amount_center: int = -1
var _particle_amount_env: int = -1
var _particle_amount_scatter: int = -1
var _particle_beat_cool: float = 0.0
const NOISE_DEFORM_SHADER: Shader = preload("res://effects/noise_deform.gdshader")
const SCATTER_COUNT_MAX := 2000
const NOISE_MESH_LIMIT := 48
const PARTICLE_AMOUNT_HYSTERESIS := 80
const SCATTER_LAYOUT_RANDOM := "random"
const SCATTER_LAYOUT_GRID := "grid"
const SCATTER_LAYOUT_CIRCULAR := "circular"
## Skip path rebuild when env AABB barely changes (meters).
const PATH_AABB_EPS := 0.75

## Async layer swap generations — ignore stale callbacks.
var _load_gen: Dictionary = {"environment": 0, "centerpiece": 0, "scatter": 0, "lighting": 0}
var _pending_scatter_after_env: bool = false
var _last_path_aabb := AABB()
var _has_path_aabb: bool = false
var _env_source_key: String = ""
var _center_source_key: String = ""
var _scatter_source_key: String = ""
## Incremental scatter spawn leftover (packed path now uses MultiMesh).
var _scatter_spawn_job: Dictionary = {}
const SCATTER_PER_FRAME := 4
## GPU-instanced scatter (thousands of items, one draw per unique mesh).
var _scatter_cluster: Node3D = null
var _scatter_mm_nodes: Array[MultiMeshInstance3D] = []


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
	if params.has("path_style") or params.has("camera_path"):
		path_style = FlythroughPathBuilder.normalize_style(
			str(params.get("path_style", params.get("camera_path", path_style)))
		)
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
	if params.has("scatter_global_scale"):
		var sc_cfg: Dictionary = (_layer_configs.get("scatter", {}) as Dictionary).duplicate(true)
		sc_cfg["global_scale"] = clampf(float(params["scatter_global_scale"]), 0.01, 100.0)
		_layer_configs["scatter"] = sc_cfg
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
			_begin_environment_swap(config)
		"scatter":
			_begin_scatter_swap(config)
		"centerpiece":
			_begin_centerpiece_swap(config)


func get_layer_config(layer_id: String) -> Dictionary:
	if layer_id == "lighting":
		return _lighting_config.duplicate(true)
	return (_layer_configs.get(layer_id, {}) as Dictionary).duplicate(true)


func get_path_progress() -> float:
	if _rig == null:
		return 0.0
	return _rig.get_path_progress()


func get_fly_speed() -> float:
	return fly_speed


func handle_look_input(event: InputEvent) -> void:
	if _rig:
		_rig.handle_look_input(event)


func set_cloth(_on: bool, _params: Dictionary = {}) -> void:
	## Cloth FX removed — keep noise deform only.
	_cloth_on = false
	_cloth_params = {}
	_clear_softbodies()
	if not RH.property_active("noise"):
		_clear_noise_deform()
		_clear_media_deform()


func set_point_cloud(on: bool, params: Dictionary = {}) -> void:
	var size := clampf(float(params.get("point_size", _point_cloud_size)), 1.0, 64.0)
	var targets: Dictionary = SceneMeshFx.pc_targets_from(params)
	var targets_changed := not _pc_targets_equal(targets, _point_cloud_targets)
	_point_cloud_on = on
	_point_cloud_size = size
	_point_cloud_targets = targets
	if not on:
		_clear_point_cloud()
		_restamp_pc_deform()
		return
	if not _pc_built or targets_changed:
		_apply_point_cloud_now()
	else:
		var stale := SceneMeshFx.update_overlay_point_size(_pc_overlays, _point_cloud_size)
		if stale:
			_apply_point_cloud_now()
		else:
			_restamp_pc_deform()


func _pc_targets_equal(a: Dictionary, b: Dictionary) -> bool:
	return bool(a.get("target_environment", true)) == bool(b.get("target_environment", true)) \
		and bool(a.get("target_main", true)) == bool(b.get("target_main", true)) \
		and bool(a.get("target_scatter", true)) == bool(b.get("target_scatter", true)) \
		and bool(a.get("target_media", true)) == bool(b.get("target_media", true))


func _apply_point_cloud_now() -> void:
	if not _point_cloud_on:
		_clear_point_cloud()
		return
	var roots: Array = []
	if bool(_point_cloud_targets.get("target_environment", true)) and _env_root:
		roots.append(_env_root)
	if bool(_point_cloud_targets.get("target_main", true)) and _center_root:
		roots.append(_center_root)
	if bool(_point_cloud_targets.get("target_scatter", true)) and _scatter_root:
		roots.append(_scatter_root)
	if roots.is_empty():
		_clear_point_cloud()
		return
	_pc_overlays = SceneMeshFx.apply_point_cloud_layers(
		self, roots, true, _point_cloud_size, false
	)
	_sync_scatter_mm_point_cloud()
	_pc_built = true
	_restamp_pc_deform()


func _invalidate_point_cloud_overlays() -> void:
	## Drop cached overlay refs before a layer free/swap so size-updates cannot `is` a freed node.
	_pc_overlays.clear()
	_pc_built = false


func _clear_point_cloud() -> void:
	_free_scatter_mm_pc()
	SceneMeshFx.clear_point_cloud(self)
	_invalidate_point_cloud_overlays()


func _free_scatter_mm_pc() -> void:
	for mmi in _scatter_mm_nodes:
		if not is_instance_valid(mmi):
			continue
		if mmi.has_meta("hs_pc_overlay"):
			var existing: Variant = mmi.get_meta("hs_pc_overlay")
			if existing != null and is_instance_valid(existing) and existing is Node:
				(existing as Node).queue_free()
			mmi.remove_meta("hs_pc_overlay")
		if mmi.has_meta("hs_pc_layers"):
			mmi.layers = int(mmi.get_meta("hs_pc_layers"))
			mmi.remove_meta("hs_pc_layers")
		if mmi.has_meta("hs_pc_shadow"):
			mmi.cast_shadow = int(mmi.get_meta("hs_pc_shadow"))
			mmi.remove_meta("hs_pc_shadow")


func _sync_scatter_mm_point_cloud() -> void:
	_free_scatter_mm_pc()
	if not _point_cloud_on or not bool(_point_cloud_targets.get("target_scatter", true)):
		return
	for mmi in _scatter_mm_nodes:
		if not is_instance_valid(mmi) or bool(mmi.get_meta("media_screen", false)):
			continue
		var src_mm: MultiMesh = mmi.multimesh
		if src_mm == null or src_mm.mesh == null:
			continue
		var tmp := MeshInstance3D.new()
		tmp.mesh = src_mm.mesh
		tmp.material_override = mmi.material_override
		var pts: ArrayMesh = _SceneMeshFx.make_points_mesh_from(tmp)
		tmp.free()
		if pts == null:
			continue
		var pc_mm := MultiMesh.new()
		pc_mm.transform_format = MultiMesh.TRANSFORM_3D
		pc_mm.mesh = pts
		pc_mm.instance_count = src_mm.instance_count
		for i in src_mm.instance_count:
			pc_mm.set_instance_transform(i, src_mm.get_instance_transform(i))
		var pc_mi := MultiMeshInstance3D.new()
		pc_mi.name = "HSPointCloud"
		pc_mi.multimesh = pc_mm
		pc_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pc_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		pc_mi.layers = 1
		pc_mi.material_override = SceneMeshFx.make_point_deform_material(_point_cloud_size)
		mmi.add_child(pc_mi)
		mmi.set_meta("hs_pc_overlay", pc_mi)
		if not mmi.has_meta("hs_pc_layers"):
			mmi.set_meta("hs_pc_layers", mmi.layers)
		if not mmi.has_meta("hs_pc_shadow"):
			mmi.set_meta("hs_pc_shadow", mmi.cast_shadow)
		mmi.layers = 1 << 19
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _restamp_pc_deform() -> void:
	## Overlay is a rest-pose points mesh; same noise/cloth uniforms make dots follow deform.
	if _cloth_on or RH.property_active("noise"):
		_apply_noise_distort(null, 0.0)


func set_camera_fx(on: bool, params: Dictionary = {}) -> void:
	_camera_fx_on = on
	_camera_fx_params = params if on else {}
	if _camera:
		SceneMeshFx.apply_camera_fx(_camera, on, params)


func _reapply_live_mesh_fx() -> void:
	if _point_cloud_on:
		_apply_point_cloud_now()
	if _camera_fx_on and _camera:
		SceneMeshFx.apply_camera_fx(_camera, true, _camera_fx_params)
	if _cloth_on or RH.property_active("noise"):
		_apply_noise_distort(null, 0.0)


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
	if _camera_fx_on and _camera:
		SceneMeshFx.apply_camera_fx(_camera, true, _camera_fx_params)


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

	var hdri_path := str(cfg.get("hdri_path", "")).strip_edges().replace("\\", "/")
	var lighting_key := "%s|%s|%s" % [
		str(cfg.get("preset", "")),
		hdri_path,
		"hdri" if use_hdri else ("sky" if bool(cfg.get("use_sky", false)) else "color"),
	]
	# Drop previous sky RID so panorama swaps are visible (in-place Sky assign can stick).
	# For async HDRI: only clear when we already have a panorama ready.
	var panorama_ready: Texture2D = null
	if use_hdri and not hdri_path.is_empty():
		panorama_ready = _AssetCache.get_texture(hdri_path)
	if lighting_key != _applied_lighting_key:
		if not use_hdri or panorama_ready != null:
			env.sky = null
			env.background_mode = Environment.BG_COLOR

	if use_hdri and not hdri_path.is_empty():
		if panorama_ready != null:
			_apply_hdri_panorama(env, cfg, panorama_ready, lighting_key, fog_density)
			return
		# Keep previous sky visible while HDRI loads off-thread (never sync Image.load here).
		var gen := int(_load_gen.get("lighting", 0)) + 1
		_load_gen["lighting"] = gen
		var st: int = _AssetCache.request_texture(hdri_path, func(status: int, payload: Variant) -> void:
			if gen != int(_load_gen.get("lighting", 0)):
				return
			if status != _AssetCache.Status.READY or not (payload is Texture2D):
				push_warning("FlythroughEnvironment: HDRI missing or unloadable: %s" % hdri_path)
				return
			if _world_env == null or _world_env.environment == null:
				return
			_apply_hdri_panorama(_world_env.environment, cfg, payload as Texture2D, lighting_key, fog_density)
		)
		if st == _AssetCache.Status.READY:
			var tex := _AssetCache.get_texture(hdri_path)
			if tex != null:
				_apply_hdri_panorama(env, cfg, tex, lighting_key, fog_density)
				return
		if st == _AssetCache.Status.LOADING:
			_applied_lighting_key = lighting_key
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
	_applied_lighting_key = lighting_key
	_world_env.environment = env


func _apply_hdri_panorama(env: Environment, cfg: Dictionary, panorama: Texture2D, lighting_key: String, fog_density: float) -> void:
	var sky := Sky.new()
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = panorama
	_base_sky_energy = float(cfg.get("sky_energy", 1.0))
	mat.energy_multiplier = _base_sky_energy
	sky.sky_material = mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	_base_ambient_energy = float(cfg.get("ambient_energy", 0.55))
	env.ambient_light_energy = _base_ambient_energy
	env.ambient_light_color = Color(1, 1, 1)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_sky_affect = 0.0
	if fog_density <= 0.00015:
		env.fog_enabled = false
	_applied_lighting_key = lighting_key
	_world_env.environment = env


func _load_hdri_texture_cached(path: String) -> Texture2D:
	var cached := _AssetCache.get_texture(path)
	if cached != null:
		return cached
	var resolved := path.replace("\\", "/")
	if resolved.begins_with("res://") or resolved.begins_with("user://"):
		if ResourceLoader.exists(resolved):
			var res: Resource = ResourceLoader.load(resolved)
			if res is Texture2D:
				_AssetCache.put_texture(resolved, res as Texture2D)
				return res as Texture2D
	var file_path := resolved
	if file_path.begins_with("res://") or file_path.begins_with("user://"):
		file_path = ProjectSettings.globalize_path(file_path)
	if not FileAccess.file_exists(file_path):
		return null
	var img: Image = Image.load_from_file(file_path)
	if img == null or img.is_empty():
		return null
	var tex := ImageTexture.create_from_image(img)
	_AssetCache.put_texture(resolved, tex)
	return tex


func _load_hdri_texture(path: String) -> Texture2D:
	return _load_hdri_texture_cached(path)


func _setup_particle_systems() -> void:
	## Particles FX removed — do not spawn breakup GPU particles.
	_center_particles = null
	_env_particles = null
	_scatter_particles = null


func _make_layer_particles(amount: int, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.emitting = false
	p.amount = clampi(amount, 80, 700)
	p.lifetime = lifetime
	p.explosiveness = 0.15
	p.visibility_aabb = AABB(Vector3(-80, -80, -80), Vector3(160, 160, 160))
	p.local_coords = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	_reapply_live_mesh_fx()


func _bump_load_gen(layer_id: String) -> int:
	var g := int(_load_gen.get(layer_id, 0)) + 1
	_load_gen[layer_id] = g
	return g


func _begin_environment_swap(config: Dictionary) -> void:
	var source := FlythroughLayerSlot.resolve_source_string(config)
	if source.is_empty():
		source = FlythroughAssetCatalog.default_environment_path()
	var key := "%s|%s" % [source, str(config.get("user_scale", config.get("scale", 1.0)))]
	# Same asset already showing — only refresh user scale / framing.
	if key == _env_source_key and _env_root.get_child_count() > 1:
		_env_user_scale = maxf(float(config.get("user_scale", config.get("scale", 1.0))), 0.01)
		_apply_env_display_scale()
		_update_framing_from_environment()
		_place_centerpiece()
		return
	if not FlythroughLayerSlot.is_file_path(source) or FlythroughLayerSlot.is_media_path(source):
		_rebuild_environment()
		_rebuild_path_from_environment(true)
		_schedule_scatter_rebuild()
		_place_centerpiece()
		_env_source_key = key
		return
	var gen := _bump_load_gen("environment")
	var packed := _AssetCache.get_scene(source)
	if packed != null:
		# Defer one frame so UI / prior frame can present before the instantiate hitch.
		call_deferred("_swap_environment_packed", packed, config, key, gen)
		return
	var st: int = _AssetCache.request_scene(source, func(status: int, payload: Variant) -> void:
		if gen != int(_load_gen.get("environment", 0)):
			return
		if status != _AssetCache.Status.READY or not (payload is PackedScene):
			# Fallback sync once so the layer still updates.
			_rebuild_environment()
			_rebuild_path_from_environment(true)
			_schedule_scatter_rebuild()
			_place_centerpiece()
			_env_source_key = key
			return
		call_deferred("_swap_environment_packed", payload as PackedScene, config, key, gen)
	)
	if st == _AssetCache.Status.LOADING:
		# Keep previous env mesh visible until ready.
		return
	_rebuild_environment()
	_rebuild_path_from_environment(true)
	_schedule_scatter_rebuild()
	_place_centerpiece()
	_env_source_key = key


func _swap_environment_packed(packed: PackedScene, config: Dictionary, key: String, gen: int) -> void:
	if gen != int(_load_gen.get("environment", 0)):
		return
	_invalidate_point_cloud_overlays()
	_clear_noise_deform(true)
	for child in _env_root.get_children():
		if child == _env_particles:
			continue
		_env_root.remove_child(child)
		child.free()
	_terrain_meta = {}
	_env_fit_scale = 1.0
	_mat_cache.clear()
	_env_user_scale = maxf(float(config.get("user_scale", config.get("scale", 1.0))), 0.01)
	_env_root.rotation = Vector3.ZERO
	_env_root.position = Vector3.ZERO
	_env_root.scale = Vector3.ONE * _env_user_scale
	var instance: Node = packed.instantiate()
	_env_root.add_child(instance)
	_SceneMeshFx.ensure_mesh_tangents(instance)
	if instance is Node3D:
		_fit_environment_node(instance as Node3D)
	_env_particles_on = false
	_sync_particles()
	_env_source_key = key
	_rebuild_path_from_environment_if_needed(true)
	_schedule_scatter_rebuild()
	_place_centerpiece()
	_capture_env_rest_rotation()
	_reapply_live_mesh_fx()


func _begin_centerpiece_swap(config: Dictionary) -> void:
	var source := FlythroughLayerSlot.resolve_source_string(config)
	var key := source
	if key == _center_source_key:
		# Same asset — refresh user scale without full swap.
		set_centerpiece_user_scale(float(config.get("user_scale", config.get("scale", 1.0))))
		_place_centerpiece()
		return
	if source.is_empty() or not FlythroughLayerSlot.is_file_path(source) or FlythroughLayerSlot.is_media_path(source):
		_rebuild_centerpiece()
		_place_centerpiece()
		_center_source_key = key
		return
	var gen := _bump_load_gen("centerpiece")
	var packed := _AssetCache.get_scene(source)
	if packed != null:
		_swap_centerpiece_packed(packed, key, gen)
		return
	var st: int = _AssetCache.request_scene(source, func(status: int, payload: Variant) -> void:
		if gen != int(_load_gen.get("centerpiece", 0)):
			return
		if status != _AssetCache.Status.READY or not (payload is PackedScene):
			_rebuild_centerpiece()
			_place_centerpiece()
			_center_source_key = key
			return
		_swap_centerpiece_packed(payload as PackedScene, key, gen)
	)
	if st == _AssetCache.Status.LOADING:
		return
	_rebuild_centerpiece()
	_place_centerpiece()
	_center_source_key = key


func _swap_centerpiece_packed(packed: PackedScene, key: String, gen: int) -> void:
	if gen != int(_load_gen.get("centerpiece", 0)):
		return
	_invalidate_point_cloud_overlays()
	_clear_noise_deform()
	for child in _center_root.get_children():
		if child == _center_particles:
			continue
		_center_root.remove_child(child)
		child.free()
	_centerpiece_mesh = null
	_mat_cache.clear()
	var instance: Node = packed.instantiate()
	_center_root.add_child(instance)
	_SceneMeshFx.ensure_mesh_tangents(instance)
	if instance is Node3D:
		_apply_centerpiece_fit_scale(instance as Node3D)
	_raise_centerpiece_priority(_center_root)
	_center_particles_on = false
	_sync_particles()
	_center_source_key = key
	_place_centerpiece()
	_capture_centerpiece_rest_rotation()
	_reapply_live_mesh_fx()


func _begin_scatter_swap(config: Dictionary) -> void:
	var source := FlythroughLayerSlot.resolve_source_string(config)
	var key := _make_scatter_source_key(config)
	if key == _scatter_source_key and not _scatter_nodes.is_empty():
		set_scatter_user_scale(float(config.get("user_scale", config.get("scale", 1.0))))
		set_scatter_global_scale(float(config.get("global_scale", 1.0)))
		return
	if source.is_empty() or not FlythroughLayerSlot.is_file_path(source) or FlythroughLayerSlot.is_media_path(source):
		_rebuild_scatter()
		_scatter_source_key = key
		return
	var gen := _bump_load_gen("scatter")
	var packed := _AssetCache.get_scene(source)
	if packed != null:
		_scatter_source_key = key
		_rebuild_scatter_with_packed(packed)
		return
	var st: int = _AssetCache.request_scene(source, func(status: int, payload: Variant) -> void:
		if gen != int(_load_gen.get("scatter", 0)):
			return
		if status != _AssetCache.Status.READY or not (payload is PackedScene):
			_rebuild_scatter()
			_scatter_source_key = key
			return
		_scatter_source_key = key
		_rebuild_scatter_with_packed(payload as PackedScene)
	)
	if st == _AssetCache.Status.LOADING:
		return
	_rebuild_scatter()
	_scatter_source_key = key


func _normalize_scatter_layout(raw: Variant) -> String:
	var id := str(raw).strip_edges().to_lower()
	match id:
		"grid", "lattice":
			return SCATTER_LAYOUT_GRID
		"circular", "circle", "ring":
			return SCATTER_LAYOUT_CIRCULAR
		_:
			return SCATTER_LAYOUT_RANDOM


func _scatter_layout_from_config(config: Dictionary) -> String:
	return _normalize_scatter_layout(config.get("layout", config.get("mode", SCATTER_LAYOUT_RANDOM)))


func _scatter_clamp_count(n: int) -> int:
	return clampi(n, 0, SCATTER_COUNT_MAX)


func _make_scatter_source_key(config: Dictionary) -> String:
	return "%s|%d|%s" % [
		FlythroughLayerSlot.resolve_source_string(config),
		_scatter_clamp_count(int(config.get("count", 18))),
		_scatter_layout_from_config(config),
	]


func _scatter_volume_aabb(count: int = -1) -> AABB:
	## Compact cube at the path/env center. Density shrinks cell size so packing is obvious.
	## Above 80, the cube grows modestly (max ~36 m) so thousands stay dense, not an 80 m void.
	var n := count
	if n < 0:
		var cfg: Dictionary = _layer_configs.get("scatter", {}) as Dictionary
		n = _scatter_clamp_count(int(cfg.get("count", 18)))
	n = maxi(_scatter_clamp_count(n), 1)
	var aabb := _path_framing_aabb()
	var center := Vector3.ZERO
	var env_span := 16.0
	if aabb.size.length() >= 0.5:
		center = aabb.get_center()
		env_span = maxf(maxf(aabb.size.x, aabb.size.y), aabb.size.z)
	var cell := 5.5
	var cap := clampf(env_span * 0.45, 10.0, 22.0)
	if n <= 80:
		var t_lo := float(n - 1) / 79.0
		cell = lerpf(5.5, 1.15, t_lo)
	else:
		var t_hi := float(n - 80) / float(SCATTER_COUNT_MAX - 80)
		cell = lerpf(1.15, 1.55, t_hi)
		cap = lerpf(22.0, 36.0, t_hi)
	var dims := _scatter_lattice_dims(n)
	var span_cells := float(maxi(maxi(dims.x - 1, dims.y - 1), maxi(dims.z - 1, 1)))
	var side := cell * span_cells
	side = maxf(side, cell * 2.0)
	side = clampf(side, 3.0, cap)
	var half := side * 0.5
	return AABB(center - Vector3(half, half, half), Vector3(side, side, side))


func _scatter_lattice_dims(n: int) -> Vector3i:
	n = maxi(n, 1)
	var nz := maxi(1, roundi(pow(float(n), 1.0 / 3.0)))
	var ny := maxi(1, roundi(sqrt(float(n) / float(nz))))
	var nx := maxi(1, ceili(float(n) / float(ny * nz)))
	return Vector3i(nx, ny, nz)


func _scatter_axis_t(i: int, dim: int) -> float:
	if dim <= 1:
		return 0.5
	return float(i) / float(dim - 1)


func _scatter_volume_point(volume: AABB, tx: float, ty: float, tz: float) -> Vector3:
	return Vector3(
		volume.position.x + tx * volume.size.x,
		volume.position.y + ty * volume.size.y,
		volume.position.z + tz * volume.size.z
	)


func _scatter_placement_rng_draws(layout: String) -> int:
	## Random layout burns 3 draws for XYZ in the volume cube; grid/circular are deterministic.
	if layout == SCATTER_LAYOUT_RANDOM:
		return 3
	return 0


func _scatter_position_for_index(
	layout: String,
	index: int,
	count: int,
	volume: AABB,
	rng: RandomNumberGenerator
) -> Vector3:
	var n := maxi(count, 1)
	if n <= 1:
		return volume.get_center()
	match layout:
		SCATTER_LAYOUT_GRID:
			var dims := _scatter_lattice_dims(n)
			var nx: int = dims.x
			var ny: int = dims.y
			var nz: int = dims.z
			var ix := index % nx
			var iy := int(index / nx) % ny
			var iz := int(index / (nx * ny))
			return _scatter_volume_point(
				volume,
				_scatter_axis_t(ix, nx),
				_scatter_axis_t(iy, ny),
				_scatter_axis_t(iz, nz)
			)
		SCATTER_LAYOUT_CIRCULAR:
			## Stacked concentric XZ rings (cylinder). More rings so it is not a single bead circle.
			var layers := maxi(1, roundi(pow(float(n), 1.0 / 3.0)))
			var per_layer := maxi(1, ceili(float(n) / float(layers)))
			var layer := mini(int(index / per_layer), layers - 1)
			var i_in: int = index - layer * per_layer
			var this_n: int = per_layer
			if layer >= layers - 1:
				this_n = maxi(1, n - layer * per_layer)
			i_in = mini(i_in, this_n - 1)
			var rings := maxi(1, mini(ceili(sqrt(float(this_n) / 3.0)), 48))
			var pts_per_ring := maxi(1, ceili(float(this_n) / float(rings)))
			var ring := mini(int(i_in / pts_per_ring), rings - 1)
			var slot: int = i_in - ring * pts_per_ring
			var pts_here: int = pts_per_ring
			if ring >= rings - 1:
				pts_here = maxi(1, this_n - ring * pts_per_ring)
			var angle := TAU * float(slot) / float(pts_here)
			var radius_t := 1.0 if rings <= 1 else float(ring + 1) / float(rings)
			var radius := minf(volume.size.x, volume.size.z) * 0.48 * radius_t
			var y_t := _scatter_axis_t(layer, layers)
			var c := volume.get_center()
			return Vector3(
				c.x + cos(angle) * radius,
				volume.position.y + y_t * volume.size.y,
				c.z + sin(angle) * radius
			)
		_:
			return _scatter_volume_point(volume, rng.randf(), rng.randf(), rng.randf())


func _schedule_scatter_rebuild() -> void:
	## Spread env→path→scatter across frames so one apply doesn't stall for seconds.
	_pending_scatter_after_env = true
	call_deferred("_flush_pending_scatter")


func _flush_pending_scatter() -> void:
	if not _pending_scatter_after_env:
		return
	_pending_scatter_after_env = false
	_rebuild_scatter()


func _rebuild_path_from_environment_if_needed(reset_progress: bool = true) -> void:
	var aabb := _fit_aabb_ignoring_user_scale()
	if _has_path_aabb:
		var prev := _last_path_aabb
		var center_delta := (aabb.get_center() - prev.get_center()).length()
		var size_delta := (aabb.size - prev.size).length()
		if center_delta < PATH_AABB_EPS and size_delta < PATH_AABB_EPS:
			_update_framing_from_environment()
			return
	_last_path_aabb = aabb
	_has_path_aabb = true
	_rebuild_path_from_environment(reset_progress)


func _rebuild_environment() -> void:
	_invalidate_point_cloud_overlays()
	_clear_noise_deform(true)
	for child in _env_root.get_children():
		if child == _env_particles:
			continue
		_env_root.remove_child(child)
		child.free()
	_terrain_meta = {}
	_env_fit_scale = 1.0
	_mat_cache.clear()
	var config: Dictionary = _layer_configs.get("environment", {})
	_env_user_scale = maxf(float(config.get("user_scale", config.get("scale", 1.0))), 0.01)
	_env_root.rotation = Vector3.ZERO
	_env_root.position = Vector3.ZERO
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
	_env_source_key = "%s|%s" % [source, str(_env_user_scale)]
	_capture_env_rest_rotation()
	_reapply_live_mesh_fx()


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
	## Live scale — stamp root immediately; path stays at auto-fit so mesh vs camera changes.
	_env_user_scale = maxf(scale_val, 0.01)
	var cfg: Dictionary = (_layer_configs.get("environment", {}) as Dictionary).duplicate(true)
	cfg["user_scale"] = _env_user_scale
	_layer_configs["environment"] = cfg
	var source := FlythroughLayerSlot.resolve_source_string(cfg)
	if source.is_empty():
		source = FlythroughAssetCatalog.default_environment_path()
	_env_source_key = "%s|%s" % [source, str(_env_user_scale)]
	_apply_env_display_scale()
	_update_framing_from_environment()
	_place_centerpiece()


func set_centerpiece_user_scale(scale_val: float) -> void:
	_center_user_scale = maxf(scale_val, 0.01)
	var cfg: Dictionary = (_layer_configs.get("centerpiece", {}) as Dictionary).duplicate(true)
	cfg["user_scale"] = _center_user_scale
	_layer_configs["centerpiece"] = cfg
	_center_base_scale = _center_fit_scale * _center_user_scale
	_reset_centerpiece_scale()


func set_scatter_user_scale(scale_val: float) -> void:
	var next := maxf(scale_val, 0.01)
	var prev := maxf(_scatter_user_scale, 0.01)
	_scatter_user_scale = next
	var cfg: Dictionary = (_layer_configs.get("scatter", {}) as Dictionary).duplicate(true)
	cfg["user_scale"] = _scatter_user_scale
	_layer_configs["scatter"] = cfg
	var ratio := next / prev
	if absf(ratio - 1.0) < 0.0001:
		return
	_rescale_scatter_item_sizes(ratio)


func set_scatter_global_scale(scale_val: float) -> void:
	## Live formation scale: ScatterCluster around the volume-cube center. No asset reload.
	var next := clampf(scale_val, 0.01, 100.0)
	_scatter_global_scale = next
	var cfg: Dictionary = (_layer_configs.get("scatter", {}) as Dictionary).duplicate(true)
	cfg["global_scale"] = _scatter_global_scale
	_layer_configs["scatter"] = cfg
	if _scatter_cluster == null or not is_instance_valid(_scatter_cluster):
		return
	_scatter_cluster.scale = Vector3.ONE * _scatter_global_scale
	for i in _scatter_nodes.size():
		if _scatter_nodes[i] == _scatter_cluster:
			if i < _scatter_base_scales.size():
				_scatter_base_scales[i] = _scatter_cluster.scale
			break
	_scatter_cluster.force_update_transform()


func _layer_user_scale_from_config(config: Dictionary, fallback: float = 1.0) -> float:
	return maxf(float(config.get("user_scale", config.get("scale", fallback))), 0.01)


func _apply_centerpiece_fit_scale(node: Node3D) -> void:
	var cfg: Dictionary = _layer_configs.get("centerpiece", {})
	_center_user_scale = _layer_user_scale_from_config(cfg, 1.0)
	_center_fit_scale = FlythroughLayerSlot.fit_node_to_size(node, 1.6)
	_center_base_scale = _center_fit_scale * _center_user_scale
	node.scale = _center_base_scale


func _read_scatter_user_scale() -> float:
	var cfg: Dictionary = _layer_configs.get("scatter", {})
	_scatter_user_scale = _layer_user_scale_from_config(cfg, 1.0)
	return _scatter_user_scale


func _read_scatter_global_scale() -> float:
	var cfg: Dictionary = _layer_configs.get("scatter", {})
	_scatter_global_scale = clampf(float(cfg.get("global_scale", 1.0)), 0.01, 100.0)
	return _scatter_global_scale


func _rescale_scatter_item_sizes(ratio: float) -> void:
	## Per-item size only — does not move formation positions.
	var sv := Vector3(ratio, ratio, ratio)
	for mmi in _scatter_mm_nodes:
		if not is_instance_valid(mmi) or mmi.multimesh == null:
			continue
		var mm: MultiMesh = mmi.multimesh
		for i in mm.instance_count:
			var xf := mm.get_instance_transform(i)
			var origin := xf.origin
			xf.basis = xf.basis.scaled(sv)
			xf.origin = origin
			mm.set_instance_transform(i, xf)
	for i in _scatter_nodes.size():
		var node := _scatter_nodes[i]
		if node == _scatter_cluster or not is_instance_valid(node):
			continue
		node.scale = node.scale * sv
		if i < _scatter_base_scales.size():
			_scatter_base_scales[i] = _scatter_base_scales[i] * sv
	if _point_cloud_on:
		_sync_scatter_mm_point_cloud()


func _finalize_scatter_instance_scale(inst: Node3D, rng: RandomNumberGenerator) -> void:
	## Fit/random variation, then per-item user_scale from scatter config.
	inst.scale = inst.scale * rng.randf_range(0.75, 1.25) * _scatter_user_scale
	_scatter_nodes.append(inst)
	_scatter_base_scales.append(inst.scale)


func _apply_env_display_scale(reactive_vec: Vector3 = Vector3.ONE) -> void:
	## Always stamp live user_scale (terrain included). Path framing ignores this via AABB helper.
	if _env_root == null:
		return
	var s := reactive_vec * _env_user_scale
	_env_root.scale = s
	# Force transform dirty so SubViewport / LOD see the change without a path rebuild.
	_env_root.force_update_transform()
	for child in _env_root.get_children():
		if child is Node3D and child != _env_particles:
			(child as Node3D).force_update_transform()


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
	# Keep hero readable relative to fit size (not user_scale).
	_center_distance = clampf(2.4 + horiz * 0.012, 2.2, 4.5)
	if _camera:
		var span := maxf(horiz, aabb.size.y)
		_camera.far = maxf(200.0, span * 4.0 + 80.0)
		_camera.near = 0.05


func set_path_style(style: String) -> void:
	var next := FlythroughPathBuilder.normalize_style(style)
	if next == path_style and _curve != null:
		return
	path_style = next
	if not is_inside_tree():
		return
	_rebuild_path_from_environment(true)
	_schedule_scatter_rebuild()


func _path_framing_aabb() -> AABB:
	## Shared sizing basis for styled paths (ignores user_scale).
	if not _terrain_meta.is_empty():
		var aabb := _fit_aabb_ignoring_user_scale()
		if aabb.size.length() > 0.5:
			return aabb
		return FlythroughPathBuilder.fallback_aabb(40.0, 16.0)
	var config: Dictionary = _layer_configs.get("environment", {})
	var source := FlythroughLayerSlot.resolve_source_string(config)
	if FlythroughLayerSlot.is_file_path(source):
		return _fit_aabb_ignoring_user_scale()
	var kind := FlythroughLayerSlot.normalize_primitive(source) if FlythroughLayerSlot.is_primitive_source(source) else ""
	if kind == "flat_plane":
		return FlythroughPathBuilder.fallback_aabb(40.0, 10.0)
	return FlythroughPathBuilder.fallback_aabb(30.0, 8.0)


func _rebuild_path_from_environment(reset_progress: bool = true) -> void:
	# Re-stamp live scale so path rebuilds never "reveal" a stale pending scale.
	_apply_env_display_scale()
	var style := FlythroughPathBuilder.normalize_style(path_style)
	var config: Dictionary = _layer_configs.get("environment", {})
	var source := FlythroughLayerSlot.resolve_source_string(config)
	var kind := FlythroughLayerSlot.normalize_primitive(source) if FlythroughLayerSlot.is_primitive_source(source) else ""
	var min_half := clampf(10.0 * clampf(_env_fit_scale, 0.25, 4.0), 8.0, 28.0)
	if style != FlythroughPathBuilder.STYLE_AUTO:
		var aabb := _path_framing_aabb()
		_last_path_aabb = aabb
		_has_path_aabb = true
		_curve = FlythroughPathBuilder.build_styled(style, aabb, 0.14, min_half)
		_update_framing_from_environment()
	elif not _terrain_meta.is_empty():
		_curve = FlythroughHTerrainBuilder.build_flight_path(_terrain_meta)
	elif kind == "flat_plane":
		_curve = FlythroughPathBuilder.overland(80.0, 8.0)
	elif FlythroughLayerSlot.is_file_path(source):
		var aabb := _fit_aabb_ignoring_user_scale()
		_last_path_aabb = aabb
		_has_path_aabb = true
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
	_invalidate_point_cloud_overlays()
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
		_center_source_key = ""
		return
	if FlythroughLayerSlot.is_file_path(source):
		# Media: parent is camera-locked each frame, so mesh uses Y-180 flip (no
		# shader billboard — that would double-face and wash the screen).
		# Scatter still billboards; environment stays world-oriented.
		var node := FlythroughLayerSlot.load_asset_into(_center_root, source, {
			"role": "centerpiece",
			"billboard": false,
		})
		if node:
			_apply_centerpiece_fit_scale(node)
	elif FlythroughLayerSlot.is_primitive_source(source):
		var kind := FlythroughLayerSlot.normalize_primitive(source)
		_centerpiece_mesh = FlythroughPrimitives.spawn_centerpiece(kind, _center_root)
		_center_fit_scale = Vector3.ONE
		_center_user_scale = _layer_user_scale_from_config(config, 1.0)
		_center_base_scale = _center_fit_scale * _center_user_scale
		if _centerpiece_mesh:
			_centerpiece_mesh.scale = _center_base_scale
	else:
		_centerpiece_mesh = FlythroughPrimitives.spawn_centerpiece("torus", _center_root)
		_center_fit_scale = Vector3.ONE
		_center_user_scale = _layer_user_scale_from_config(config, 1.0)
		_center_base_scale = _center_fit_scale * _center_user_scale
		if _centerpiece_mesh:
			_centerpiece_mesh.scale = _center_base_scale
	_raise_centerpiece_priority(_center_root)
	_center_particles_on = false  # force resync
	_sync_particles()
	_center_source_key = source
	_capture_centerpiece_rest_rotation()
	_reapply_live_mesh_fx()


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
	## Media screens keep their shared material instance (no duplicate orphaning).
	if mi.get_meta("media_screen", false):
		if mi.material_override is Material:
			(mi.material_override as Material).render_priority = priority
		return
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
	if not is_inside_tree() or not _camera.is_inside_tree() or not _center_root.is_inside_tree():
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
	# Do not spin media screens (they face the camera via mesh flip / billboard).
	if delta > 0.0 and _center_root.get_child_count() > 0 and not RH.affect_rotation():
		var child := _center_root.get_child(0)
		if child is Node3D and child != _center_particles and not (child is FlythroughMediaProp):
			(child as Node3D).rotate_y(delta * 0.4)


func _clear_scatter_visuals() -> void:
	_invalidate_point_cloud_overlays()
	_clear_noise_deform()
	_cancel_scatter_spawn()
	_free_scatter_mm_pc()
	for child in _scatter_root.get_children():
		if child == _scatter_particles:
			continue
		_scatter_root.remove_child(child)
		child.free()
	_scatter_nodes.clear()
	_scatter_base_scales.clear()
	_scatter_base_positions.clear()
	_scatter_rest_rotations.clear()
	_scatter_mm_nodes.clear()
	_scatter_cluster = null
	_rot_driving_scatter = false
	_mat_cache.clear()


func _register_scatter_cluster(cluster: Node3D) -> void:
	_scatter_cluster = cluster
	_scatter_nodes.append(cluster)
	_scatter_base_scales.append(cluster.scale)
	_scatter_base_positions.append(cluster.position)
	_scatter_rest_rotations.append(cluster.rotation)


func _xform_in_space(node: Node3D, space_root: Node3D) -> Transform3D:
	## Relative transform without requiring nodes to be in the SceneTree.
	## Packed-scene instantiate() is off-tree; global_transform then logs !is_inside_tree().
	if node == null or space_root == null:
		return Transform3D.IDENTITY
	if node == space_root:
		return Transform3D.IDENTITY
	if node.is_inside_tree() and space_root.is_inside_tree():
		return space_root.global_transform.affine_inverse() * node.global_transform
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != space_root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _extract_scatter_drawables(root: Node, space_root: Node3D) -> Array:
	## [{mesh, material, local}] unique meshes under root, local xf in space_root space.
	var meshes: Array = []
	_collect_mesh_instances(root, meshes)
	var out: Array = []
	var seen: Dictionary = {}
	for mi_any in meshes:
		if mi_any == null or not is_instance_valid(mi_any) or not (mi_any is MeshInstance3D):
			continue
		var mi := mi_any as MeshInstance3D
		if mi.mesh == null:
			continue
		var mid := mi.mesh.get_instance_id()
		if seen.has(mid):
			continue
		seen[mid] = true
		var mat: Material = mi.material_override
		if mat == null:
			mat = mi.get_active_material(0)
		out.append({
			"mesh": mi.mesh,
			"material": mat,
			"local": _xform_in_space(mi, space_root),
		})
		if out.size() >= 8:
			break
	return out


func _fill_scatter_multimesh(
	mm: MultiMesh,
	count: int,
	layout: String,
	volume: AABB,
	rng: RandomNumberGenerator,
	local_xf: Transform3D,
	extra_scale: Vector3
) -> void:
	mm.instance_count = count
	var origin := volume.get_center()
	for i in count:
		var pos := _scatter_position_for_index(layout, i, count, volume, rng) - origin
		var s := extra_scale * rng.randf_range(0.75, 1.25) * _scatter_user_scale
		var slot := Transform3D(Basis.from_scale(s), pos)
		mm.set_instance_transform(i, slot * local_xf)


func _add_scatter_multimesh(
	parent: Node3D,
	mesh: Mesh,
	mat: Material,
	count: int,
	layout: String,
	volume: AABB,
	rng: RandomNumberGenerator,
	local_xf: Transform3D,
	extra_scale: Vector3,
	is_media: bool
) -> MultiMeshInstance3D:
	if mesh == null or count <= 0:
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	_fill_scatter_multimesh(mm, count, layout, volume, rng, local_xf, extra_scale)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat != null:
		mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if is_media \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if is_media:
		mmi.set_meta("media_screen", true)
	parent.add_child(mmi)
	_scatter_mm_nodes.append(mmi)
	return mmi


func _finish_scatter_rebuild() -> void:
	_rot_driving_scatter = false
	_scatter_particles_on = false
	_sync_particles()
	_scatter_source_key = _make_scatter_source_key(_layer_configs.get("scatter", {}))
	_reapply_live_mesh_fx()


func _rebuild_scatter() -> void:
	_clear_scatter_visuals()
	var config: Dictionary = _layer_configs.get("scatter", {})
	var count := _scatter_clamp_count(int(config.get("count", 18)))
	if count <= 0:
		_scatter_particles_on = false
		_sync_particles()
		return
	var source := FlythroughLayerSlot.resolve_source_string(config)
	if source.is_empty():
		_scatter_particles_on = false
		_sync_particles()
		return

	var use_file := FlythroughLayerSlot.is_file_path(source)
	var use_media := FlythroughLayerSlot.is_media_path(source)
	var packed_scene: PackedScene = null
	if use_file and not use_media:
		packed_scene = _AssetCache.get_scene(source)
		if packed_scene == null:
			packed_scene = _AssetCache.peek_or_load_scene_sync(source)
		if packed_scene:
			_rebuild_scatter_with_packed(packed_scene)
			return

	_read_scatter_user_scale()
	_read_scatter_global_scale()
	var layout := _scatter_layout_from_config(config)
	var volume := _scatter_volume_aabb(count)
	var cluster := Node3D.new()
	cluster.name = "ScatterCluster"
	cluster.position = volume.get_center()
	cluster.scale = Vector3.ONE * _scatter_global_scale
	_scatter_root.add_child(cluster)

	if use_media:
		var media_master: Node3D = _MEDIA_PROP.spawn(cluster, source, {"role": "scatter", "billboard": true}) as Node3D
		if media_master == null:
			cluster.free()
			_scatter_particles_on = false
			_sync_particles()
			return
		FlythroughLayerSlot.fit_node_to_size(media_master, 0.85)
		var media_scale := media_master.scale
		media_master.visible = false
		var mesh: Mesh = null
		var mat: Material = null
		if media_master.has_method("get_quad_mesh"):
			mesh = media_master.call("get_quad_mesh") as Mesh
		if media_master.has_method("get_shared_material"):
			mat = media_master.call("get_shared_material") as Material
		var rng_m := RandomNumberGenerator.new()
		rng_m.seed = 42
		if _add_scatter_multimesh(cluster, mesh, mat, count, layout, volume, rng_m, Transform3D.IDENTITY, media_scale, true) == null:
			cluster.free()
			_scatter_particles_on = false
			_sync_particles()
			return
		_register_scatter_cluster(cluster)
		_finish_scatter_rebuild()
		return

	if use_file:
		var inst: Node3D = FlythroughLayerSlot.load_asset_into(_scatter_root, source, {"role": "scatter", "billboard": true})
		if inst == null:
			cluster.free()
			_scatter_particles_on = false
			_sync_particles()
			return
		_SceneMeshFx.ensure_mesh_tangents(inst)
		var fit_s := FlythroughLayerSlot.fit_node_to_size(inst, 0.85)
		var drawables := _extract_scatter_drawables(inst, inst)
		_scatter_root.remove_child(inst)
		inst.free()
		if drawables.is_empty():
			cluster.free()
			_scatter_particles_on = false
			_sync_particles()
			return
		for d in drawables:
			var rng_f := RandomNumberGenerator.new()
			rng_f.seed = 42
			_add_scatter_multimesh(
				cluster,
				d.get("mesh") as Mesh,
				d.get("material") as Material,
				count,
				layout,
				volume,
				rng_f,
				d.get("local", Transform3D.IDENTITY),
				fit_s,
				false
			)
		_register_scatter_cluster(cluster)
		_finish_scatter_rebuild()
		return

	var kind := "cubes"
	if FlythroughLayerSlot.is_primitive_source(source):
		kind = FlythroughLayerSlot.normalize_primitive(source)
	var proto := FlythroughPrimitives.spawn_scatter_template(kind)
	var rng_p := RandomNumberGenerator.new()
	rng_p.seed = 42
	_add_scatter_multimesh(
		cluster, proto.mesh, proto.material_override, count, layout, volume, rng_p,
		Transform3D.IDENTITY, Vector3.ONE, false
	)
	proto.free()
	_register_scatter_cluster(cluster)
	_finish_scatter_rebuild()


func _rebuild_scatter_with_packed(packed_scene: PackedScene) -> void:
	_clear_scatter_visuals()
	if packed_scene == null:
		_scatter_particles_on = false
		_sync_particles()
		return
	var config: Dictionary = _layer_configs.get("scatter", {})
	var count := _scatter_clamp_count(int(config.get("count", 18)))
	if count <= 0:
		_scatter_particles_on = false
		_sync_particles()
		return
	var inst: Node = packed_scene.instantiate()
	if inst == null:
		_scatter_particles_on = false
		_sync_particles()
		return
	_SceneMeshFx.ensure_mesh_tangents(inst)
	var space := inst as Node3D
	if space == null:
		inst.free()
		_scatter_particles_on = false
		_sync_particles()
		return
	var fit_s := FlythroughLayerSlot.fit_node_to_size(space, 0.85)
	var drawables := _extract_scatter_drawables(space, space)
	inst.free()
	if drawables.is_empty():
		_scatter_particles_on = false
		_sync_particles()
		return
	_read_scatter_user_scale()
	_read_scatter_global_scale()
	var layout := _scatter_layout_from_config(config)
	var volume := _scatter_volume_aabb(count)
	var cluster := Node3D.new()
	cluster.name = "ScatterCluster"
	cluster.position = volume.get_center()
	cluster.scale = Vector3.ONE * _scatter_global_scale
	_scatter_root.add_child(cluster)
	for d in drawables:
		var rng := RandomNumberGenerator.new()
		rng.seed = 42
		_add_scatter_multimesh(
			cluster,
			d.get("mesh") as Mesh,
			d.get("material") as Material,
			count,
			layout,
			volume,
			rng,
			d.get("local", Transform3D.IDENTITY),
			fit_s,
			false
		)
	_register_scatter_cluster(cluster)
	_finish_scatter_rebuild()


func _cancel_scatter_spawn() -> void:
	_scatter_spawn_job.clear()


func _tick_scatter_spawn() -> void:
	if _scatter_spawn_job.is_empty():
		return
	var packed: PackedScene = _scatter_spawn_job.get("packed") as PackedScene
	if packed == null:
		_cancel_scatter_spawn()
		return
	var count: int = int(_scatter_spawn_job.get("count", 0))
	var index: int = int(_scatter_spawn_job.get("index", 0))
	var layout: String = _normalize_scatter_layout(_scatter_spawn_job.get("layout", SCATTER_LAYOUT_RANDOM))
	var vol_pos: Vector3 = _scatter_spawn_job.get("vol_pos", Vector3(-8, -8, -8))
	var vol_size: Vector3 = _scatter_spawn_job.get("vol_size", Vector3(16, 16, 16))
	var volume := AABB(vol_pos, vol_size)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# Fast-forward RNG to current index for stable positions + scale variation.
	var draws_per := _scatter_placement_rng_draws(layout) + 1  # +1 scale draw in finalize
	for _skip in index:
		for _d in draws_per:
			rng.randf()
	var spawned := 0
	while index < count and spawned < SCATTER_PER_FRAME:
		var pos := _scatter_position_for_index(layout, index, count, volume, rng)
		var n := packed.instantiate()
		_scatter_root.add_child(n)
		_SceneMeshFx.ensure_mesh_tangents(n)
		var inst := n as Node3D
		if inst == null:
			n.queue_free()
			index += 1
			spawned += 1
			continue
		FlythroughLayerSlot.fit_node_to_size(inst, 0.85)
		var origin := volume.get_center()
		inst.position = origin + (pos - origin) * _scatter_global_scale
		_finalize_scatter_instance_scale(inst, rng)
		_scatter_base_positions.append(inst.position)
		_scatter_rest_rotations.append(inst.rotation)
		index += 1
		spawned += 1
	_scatter_spawn_job["index"] = index
	if spawned > 0 and _point_cloud_on:
		_apply_point_cloud_now()
	if index >= count:
		_cancel_scatter_spawn()
		_rot_driving_scatter = false
		_scatter_particles_on = false
		_sync_particles()
		_scatter_source_key = _make_scatter_source_key(_layer_configs.get("scatter", {}))
		_reapply_live_mesh_fx()

func _process(delta: float) -> void:
	_tick_scatter_spawn()
	_noise_t += delta
	if _particle_beat_cool > 0.0:
		_particle_beat_cool = maxf(_particle_beat_cool - delta, 0.0)
	if _rig:
		_rig.fly_speed = fly_speed
		_rig.advance(delta)
	if _camera and _light:
		_light.global_position = _camera.global_position + Vector3(0, 1.2, 0)
	_update_centerpiece_transform(delta)
	_sync_particles()


func _sync_particles() -> void:
	## Particles FX removed.
	return
	var want_center := false
	var want_env := false
	var want_scatter := false
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
	_collect_mesh_points_local(root, root, points, exclude, 900)
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
		particles.amount = clampi(points.size(), 100, 700)
		var aabb := AABB(points[0], Vector3.ZERO)
		for p in points:
			aabb = aabb.expand(p)
		particles.visibility_aabb = aabb.grow(4.0)
	else:
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		mat.emission_sphere_radius = fallback_radius
		mat.emission_point_texture = null
		mat.emission_point_count = 1
		particles.amount = clampi(int(180 * fallback_radius), 100, 500)
		particles.visibility_aabb = AABB(Vector3(-fallback_radius, -fallback_radius, -fallback_radius) * 3.0, Vector3.ONE * fallback_radius * 6.0)
	particles.restart()


func _collect_mesh_points_local(node: Node, space_root: Node3D, out: PackedVector3Array, exclude: Array, budget: int) -> void:
	if out.size() >= budget:
		return
	if node in exclude:
		pass
	elif node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		var mm: MultiMesh = mmi.multimesh
		if mm != null:
			var n := mini(mm.instance_count, budget - out.size())
			for i in n:
				out.append(mm.get_instance_transform(i).origin)
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var xf := _xform_in_space(mi, space_root)
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
		# No deform toggles on — unwind leftover poses, keep cloth/noise clear path.
		restore_reactive_poses()
		_apply_noise_distort(state, 0.0)
		return

	var lfo := float(RH.get_field("lfo_mod01", 0.0))
	var light_drive := RH.drive_value("light", state, lfo) if RH.property_active("light") else 0.0
	# Lights react when "What reacts" includes Lights.
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
		_apply_environment_rotation(state, lfo)
	if RH.applies_to("scatter"):
		_apply_scatter_audio(state, lfo)
	else:
		_reset_scatter_scales()
		for node in _scatter_nodes:
			if is_instance_valid(node):
				_reset_layer_emission(node)
		_apply_scatter_rotation(state, lfo)
	if RH.applies_to("centerpiece"):
		_apply_centerpiece_audio(state, lfo)
	else:
		_reset_centerpiece_scale()
		var cnode := _centerpiece_content_node()
		if cnode:
			_reset_layer_emission(cnode)
		_apply_centerpiece_rotation(state, lfo)

	_apply_noise_distort(state, lfo)
	_apply_camera_rotation(state, lfo)
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
	## Avoid rewriting GPUParticles.amount every frame (forces pool rebuild / hitch).
	var want_restart := state.beat and _particle_beat_cool <= 0.0
	if want_restart:
		_particle_beat_cool = 0.18
	if _center_particles_on and _center_particles:
		_set_particle_amount_stable(_center_particles, clampi(int(160 + state.bass * 420), 100, 600), "_particle_amount_center")
		if _center_particles.process_material is ParticleProcessMaterial:
			var pm: ParticleProcessMaterial = _center_particles.process_material
			pm.initial_velocity_max = 2.0 + state.energy * 10.0
			pm.color = Color.from_hsv(fposmod(state.mids, 1.0), 0.7, 1.0)
		if want_restart:
			_center_particles.restart()
	if _env_particles_on and _env_particles:
		_set_particle_amount_stable(_env_particles, clampi(int(240 + state.energy * 460), 140, 700), "_particle_amount_env")
		if _env_particles.process_material is ParticleProcessMaterial:
			var epm: ParticleProcessMaterial = _env_particles.process_material
			epm.initial_velocity_max = 1.5 + state.highs * 9.0
			epm.color = Color.from_hsv(fposmod(0.4 + state.highs * 0.5, 1.0), 0.65, 1.0)
		if want_restart:
			_env_particles.restart()
	if _scatter_particles_on and _scatter_particles:
		_set_particle_amount_stable(_scatter_particles, clampi(int(180 + state.mids * 400), 120, 600), "_particle_amount_scatter")
		if _scatter_particles.process_material is ParticleProcessMaterial:
			var spm: ParticleProcessMaterial = _scatter_particles.process_material
			spm.initial_velocity_max = 1.2 + state.highs * 8.0
			spm.color = Color.from_hsv(fposmod(0.15 + state.bass * 0.5, 1.0), 0.7, 1.0)
		if want_restart:
			_scatter_particles.restart()


func _set_particle_amount_stable(particles: GPUParticles3D, target: int, cache_field: String) -> void:
	if particles == null:
		return
	var prev: int = int(get(cache_field))
	if prev >= 0 and absi(target - prev) < PARTICLE_AMOUNT_HYSTERESIS:
		return
	particles.amount = target
	set(cache_field, target)


func _apply_environment_audio(state: AudioState, lfo: float) -> void:
	_apply_environment_rotation(state, lfo)
	if RH.property_active("scale"):
		var amt := RH.scale_multiplier()
		_apply_env_display_scale(RH.scale_vector(amt))
	else:
		_apply_env_display_scale()
	if RH.property_active("emission"):
		var ed := RH.drive_value("emission", state, lfo)
		_drive_mesh_emission(_env_root, ed, false)
		_drive_ambient_tint(ed)
	else:
		_reset_layer_emission(_env_root)


func _apply_environment_rotation(state: AudioState, lfo: float) -> void:
	var want := RH.rotation_applies_to("environment") and RH.property_active("rotation") and _env_root != null
	if not want:
		# Always snap back — do not gate on _rot_driving (capture/rebuild can clear the flag).
		_restore_env_rotation()
		_rot_driving_env = false
		return
	_rot_driving_env = true
	var rd := RH.drive_value("rotation", state, lfo)
	# Terrain: slower orbit. Non-terrain: mild. Amount + axes from settings.
	var mul := 0.55 if not _terrain_meta.is_empty() else 1.0
	var rate := RH.rotation_rate(rd) * mul
	_apply_axis_rotation(_env_root, rate, true)


func _apply_centerpiece_audio(state: AudioState, lfo: float) -> void:
	var node := _centerpiece_content_node()
	if node == null:
		return
	if RH.property_active("scale") and not _center_particles_on:
		var amt := RH.scale_multiplier()
		node.scale = _center_base_scale * RH.scale_vector(amt)
	elif not _center_particles_on:
		_reset_centerpiece_scale()
	_apply_centerpiece_rotation(state, lfo)
	if RH.property_active("emission") and not _center_particles_on:
		var ed := RH.drive_value("emission", state, lfo)
		_drive_mesh_emission(node, ed, true)
		_drive_ambient_tint(ed)
	else:
		_reset_layer_emission(node)


func _apply_centerpiece_rotation(state: AudioState, lfo: float) -> void:
	var want := RH.rotation_applies_to("centerpiece") and RH.property_active("rotation") \
		and not _center_particles_on
	if not want:
		_restore_centerpiece_rotation()
		_rot_driving_center = false
		return
	var node := _centerpiece_content_node()
	if node == null:
		_restore_centerpiece_rotation()
		_rot_driving_center = false
		return
	_rot_driving_center = true
	var rd := RH.drive_value("rotation", state, lfo)
	var rate := RH.rotation_rate(rd) * 1.15
	_apply_axis_rotation(node, rate, false)


func _apply_camera_rotation(state: AudioState, lfo: float) -> void:
	if _rig == null:
		return
	var want := RH.rotation_applies_to("camera") and RH.schedule_open("rotation")
	# property_active("rotation") covers affect_rotation OR affect_camera_rotation + schedule.
	want = want and RH.property_active("rotation")
	if not want:
		_rig.reset_reactive_spin()
		_rot_driving_camera = false
		return
	_rot_driving_camera = true
	var rd := RH.drive_value("rotation", state, lfo)
	var rate := RH.rotation_rate(rd) * 0.85
	_rig.apply_reactive_spin(rate, RH.rotation_axis_mask())


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
	var r := rate
	if axes.x > 0.0:
		node.rotate_x(r * axes.x)
	if axes.y > 0.0:
		node.rotate_y(r * axes.y)
	if axes.z > 0.0:
		node.rotate_z(r * axes.z)
	if track_env_accum:
		_rot_accum_env = node.rotation


func _capture_env_rest_rotation() -> void:
	## Layer root rest is always identity — reactive spin is transient on `_env_root`.
	if _env_root:
		_env_root.rotation = Vector3.ZERO
		_env_root.position = Vector3.ZERO
	_env_rest_rotation = Vector3.ZERO
	_rot_accum_env = Vector3.ZERO
	_rot_driving_env = false


func _capture_centerpiece_rest_rotation() -> void:
	var node := _centerpiece_content_node()
	# Capture spawn orientation once; never adopt a mid-spin pose as rest.
	_center_rest_rotation = node.rotation if node else Vector3.ZERO
	_rot_driving_center = false


func _capture_scatter_rest_rotations() -> void:
	_scatter_rest_rotations.clear()
	for node in _scatter_nodes:
		if is_instance_valid(node):
			_scatter_rest_rotations.append(node.rotation)
		else:
			_scatter_rest_rotations.append(Vector3.ZERO)
	_rot_driving_scatter = false


func _restore_env_rotation() -> void:
	if _env_root:
		_env_root.rotation = _env_rest_rotation
		_env_root.position = Vector3.ZERO
	_rot_accum_env = _env_rest_rotation


func _restore_centerpiece_rotation() -> void:
	var node := _centerpiece_content_node()
	if node:
		node.rotation = _center_rest_rotation


func _restore_scatter_rotations() -> void:
	for i in _scatter_nodes.size():
		if not is_instance_valid(_scatter_nodes[i]):
			continue
		var rest: Vector3 = _scatter_rest_rotations[i] if i < _scatter_rest_rotations.size() else Vector3.ZERO
		_scatter_nodes[i].rotation = rest
		if i < _scatter_base_positions.size():
			_scatter_nodes[i].position = _scatter_base_positions[i]


func restore_reactive_poses() -> void:
	## Immediate unwind of leftovers. Skips layers that are still actively driven.
	var rot_on := RH.property_active("rotation")
	if not (rot_on and RH.rotation_applies_to("environment")):
		_restore_env_rotation()
		_rot_driving_env = false
	if not (rot_on and RH.rotation_applies_to("centerpiece")):
		_restore_centerpiece_rotation()
		_rot_driving_center = false
	if not (rot_on and RH.rotation_applies_to("scatter")):
		_restore_scatter_rotations()
		_rot_driving_scatter = false
	var want_cam := rot_on and RH.rotation_applies_to("camera") and RH.schedule_open("rotation")
	if not want_cam:
		if _rig:
			_rig.reset_reactive_spin()
		_rot_driving_camera = false
	if not RH.property_active("scale"):
		_reset_reactive_scales()
	_clear_noise_deform(false)
	if not RH.property_active("emission"):
		_reset_layer_emission(_env_root)
		var cnode := _centerpiece_content_node()
		if cnode:
			_reset_layer_emission(cnode)
		for node in _scatter_nodes:
			if is_instance_valid(node):
				_reset_layer_emission(node)
		if _world_env and _world_env.environment:
			_world_env.environment.ambient_light_color = _base_ambient_color
	if not RH.enabled() or not (RH.property_active("light") and RH.applies_to("lights")):
		_apply_hdri_energy(1.0)
		if _light:
			_light.light_energy = _base_fill_energy
			_light.light_color = _accent
			_light.omni_range = 24.0
		if _sun:
			_sun.light_energy = _base_sun_energy
			_sun.light_color = _base_sun_color


func reset_stage_to_defaults() -> void:
	## Recover a sane stage pose without swapping playlist assets.
	# Force-clear everything — callers turn off corrupting RH flags first.
	_restore_env_rotation()
	_rot_driving_env = false
	_restore_centerpiece_rotation()
	_rot_driving_center = false
	_restore_scatter_rotations()
	_rot_driving_scatter = false
	if _rig:
		_rig.reset_reactive_spin()
	_rot_driving_camera = false
	_reset_reactive_scales()
	_cloth_on = false
	_cloth_params = {}
	_point_cloud_on = false
	_camera_fx_on = false
	_clear_point_cloud()
	if _camera:
		SceneMeshFx.restore_camera_fx(_camera)
	_clear_media_deform()
	_clear_softbodies()
	_clear_noise_deform(true)
	_reset_layer_emission(_env_root)
	var cnode := _centerpiece_content_node()
	if cnode:
		_reset_layer_emission(cnode)
	for node in _scatter_nodes:
		if is_instance_valid(node):
			_reset_layer_emission(node)
	if _world_env and _world_env.environment:
		_world_env.environment.ambient_light_color = _base_ambient_color
	# Hard identity on env root (rest capture already zeros; belt-and-suspenders).
	if _env_root:
		_env_root.rotation = Vector3.ZERO
		_env_root.position = Vector3.ZERO
	_env_rest_rotation = Vector3.ZERO
	if cnode:
		cnode.rotation = _center_rest_rotation
	# Re-stamp scatter rests to current spawn orientations if arrays drifted.
	if _scatter_rest_rotations.size() != _scatter_nodes.size():
		_capture_scatter_rest_rotations()
	else:
		_restore_scatter_rotations()
	# Fly speed + lighting energies back to catalog-ish defaults / current cfg baselines.
	fly_speed = 2.0
	if _rig:
		_rig.fly_speed = fly_speed
		_rig.reset_reactive_spin()
	_apply_lighting_config(_lighting_config)
	_apply_env_display_scale()
	_place_centerpiece()


func _apply_scatter_audio(state: AudioState, lfo: float) -> void:
	if RH.property_active("scale") and not _scatter_particles_on:
		var amt := RH.scale_multiplier()
		var scale_vec := RH.scale_vector(amt)
		for i in _scatter_nodes.size():
			if not is_instance_valid(_scatter_nodes[i]):
				continue
			var base: Vector3 = _scatter_base_scales[i] if i < _scatter_base_scales.size() else Vector3.ONE
			_scatter_nodes[i].scale = base * scale_vec
	elif not _scatter_particles_on:
		_reset_scatter_scales()
	_apply_scatter_rotation(state, lfo)
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


func _apply_scatter_rotation(state: AudioState, lfo: float) -> void:
	var want := RH.rotation_applies_to("scatter") and RH.property_active("rotation") \
		and not _scatter_particles_on
	if not want:
		_restore_scatter_rotations()
		_rot_driving_scatter = false
		return
	_rot_driving_scatter = true
	var rd := RH.drive_value("rotation", state, lfo)
	var rate := RH.rotation_rate(rd) * 0.95
	for node in _scatter_nodes:
		if is_instance_valid(node):
			_apply_axis_rotation(node, rate, false)


func _reset_layer_emission(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	var key_nodes: Array = []
	_collect_mesh_instances(root, key_nodes)
	for mi in key_nodes:
		if mi == null or not is_instance_valid(mi) or not (mi is MeshInstance3D):
			continue
		var mid := (mi as MeshInstance3D).get_instance_id()
		if not _mat_cache.has(mid):
			continue
		var mats: Array = _mat_cache[mid]
		for mat in mats:
			if mat is BaseMaterial3D:
				(mat as BaseMaterial3D).emission_energy_multiplier = 0.0
				(mat as BaseMaterial3D).emission_enabled = false
	var mms: Array = []
	_collect_multimesh_instances(root, mms)
	for mmi_any in mms:
		if mmi_any == null or not is_instance_valid(mmi_any) or not (mmi_any is MultiMeshInstance3D):
			continue
		var mmi := mmi_any as MultiMeshInstance3D
		if mmi.material_override is BaseMaterial3D:
			var ov := mmi.material_override as BaseMaterial3D
			ov.emission_energy_multiplier = 0.0
			ov.emission_enabled = false


func _collect_mesh_instances(node: Node, out: Array) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is MeshInstance3D:
		if not str(node.name).begins_with("HSPointCloud"):
			out.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out)


func _collect_multimesh_instances(node: Node, out: Array) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is MultiMeshInstance3D:
		if not str(node.name).begins_with("HSPointCloud"):
			out.append(node)
	for child in node.get_children():
		_collect_multimesh_instances(child, out)


func _ensure_noise_materials_gi(gi: GeometryInstance3D, nseed: Vector3, for_points: bool = false) -> Array:
	var key := gi.get_instance_id()
	if _noise_mats.has(key):
		return _noise_mats[key]
	var backup := {"override": gi.material_override, "surfaces": []}
	var base: Material = gi.material_override
	if base == null and gi is MultiMeshInstance3D:
		var mm: MultiMesh = (gi as MultiMeshInstance3D).multimesh
		if mm != null and mm.mesh != null and mm.mesh.get_surface_count() > 0:
			base = mm.mesh.surface_get_material(0)
	var sm := _make_noise_shader_from(base, nseed, for_points)
	gi.material_override = sm
	_noise_backup[key] = backup
	_noise_mats[key] = [sm]
	return [sm]


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
		# Image/video screens must stay display-referred — emission blows them to white.
		if str(mi.name).begins_with("HSPointCloud"):
			pass
		elif not (mi.get_meta("media_screen", false) or node.get_parent() is FlythroughMediaProp):
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
	elif node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		if str(mmi.name).begins_with("HSPointCloud"):
			pass
		elif not bool(mmi.get_meta("media_screen", false)) and mmi.material_override is BaseMaterial3D:
			var ov := mmi.material_override as BaseMaterial3D
			if not ov.resource_local_to_scene:
				ov = ov.duplicate() as BaseMaterial3D
				mmi.material_override = ov
			ov.emission_enabled = true
			ov.emission = emit_col
			ov.emission_energy_multiplier = 0.8 + drive01 * 5.0
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
	var noise_on := RH.property_active("noise")
	var cloth_on := _cloth_on
	if not noise_on and not cloth_on:
		_clear_noise_deform()
		_clear_media_deform()
		_clear_softbodies()
		return
	# Amount field is the displace (expression can be bass * 1000). No extra audio multiply.
	var amt := RH.noise_amount() if noise_on else 0.0
	var feature := maxf(RH.noise_scale(), 0.5)
	var axes := RH.noise_axis_mask() if noise_on else Vector3.ONE
	if noise_on and (axes.length_squared() < 0.01 or absf(amt) < 0.000001):
		noise_on = false
		amt = 0.0
		if not cloth_on:
			_clear_noise_deform()
			_clear_media_deform()
			_clear_softbodies()
			return
	var cloth_amt := float(_cloth_params.get("amount", 0.7)) if cloth_on else 0.0
	var cloth_stiff := float(_cloth_params.get("stiffness", 0.55)) if cloth_on else 0.55
	var cloth_damp := float(_cloth_params.get("damping", 0.28)) if cloth_on else 0.28
	var cloth_wind := float(_cloth_params.get("wind", 0.55)) if cloth_on else 0.0
	var cloth_grav := float(_cloth_params.get("gravity", 1.0)) if cloth_on else 0.0
	var want_env := ((RH.noise_applies_to("environment") and noise_on) or cloth_on) and _env_root != null
	var want_center := ((RH.noise_applies_to("centerpiece") and noise_on) or cloth_on) and not _center_particles_on
	var want_scatter := ((RH.noise_applies_to("scatter") and noise_on) or cloth_on) and not _scatter_particles_on
	if _env_root and _terrain_meta.is_empty():
		# Don't clobber reactive multi-axis rotation on the env root.
		if not RH.property_active("rotation") or not RH.rotation_applies_to("environment"):
			_restore_env_rotation()
		_env_root.position = Vector3.ZERO
	var cnode := _centerpiece_content_node()
	if cnode and (not RH.property_active("rotation") or not RH.rotation_applies_to("centerpiece")):
		cnode.position = Vector3.ZERO
		_restore_centerpiece_rotation()
	for i in _scatter_nodes.size():
		if is_instance_valid(_scatter_nodes[i]) and i < _scatter_base_positions.size():
			_scatter_nodes[i].position = _scatter_base_positions[i]

	var active_ids: Dictionary = {}
	# HTerrain chunks use DirectMeshInstance — MeshInstance overrides never reach them.
	# Drive Classic4 material uniforms (u_hs_noise_*) for real vertex displace on hills.
	if want_env and not _terrain_meta.is_empty() and noise_on:
		_apply_terrain_noise_displace(amt, feature, axes)
	elif want_env:
		if not _terrain_meta.is_empty() and not noise_on:
			_clear_terrain_noise_displace()
		_apply_noise_to_root(_env_root, amt, feature, Vector3(0.1, 0.2, 0.3), axes, active_ids, cloth_amt, cloth_stiff, cloth_wind, cloth_grav)
	else:
		_clear_terrain_noise_displace()
	if want_center and cnode:
		_apply_noise_to_root(cnode, amt * 0.85, feature * 0.7, Vector3(1.1, 0.4, 0.7), axes, active_ids, cloth_amt * 0.9, cloth_stiff, cloth_wind, cloth_grav)
	if want_scatter:
		for i in _scatter_nodes.size():
			if not is_instance_valid(_scatter_nodes[i]):
				continue
			var nseed := Vector3(float(i) * 0.37, 2.0, float(i) * 0.19)
			_apply_noise_to_root(_scatter_nodes[i], amt * 0.75, feature * 0.85, nseed, axes, active_ids, cloth_amt * 0.8, cloth_stiff, cloth_wind, cloth_grav)
	_prune_noise_materials(active_ids)
	_stamp_all_pc_overlays(
		amt, feature, axes, cloth_amt, cloth_stiff, cloth_wind, cloth_grav,
		want_env, want_center, want_scatter
	)
	_apply_media_deform(
		amt, feature, axes, cloth_on, cloth_amt, cloth_stiff, cloth_damp, cloth_wind,
		want_env, want_center, want_scatter
	)


func _apply_terrain_noise_displace(amount: float, feature: float, axes: Vector3) -> void:
	var terrain: Variant = _terrain_meta.get("terrain", null)
	if terrain == null or not is_instance_valid(terrain):
		return
	if terrain.has_method("set_shader_param"):
		terrain.call("set_shader_param", "u_hs_noise_amount", amount)
		terrain.call("set_shader_param", "u_hs_noise_scale", feature)
		terrain.call("set_shader_param", "u_hs_noise_time", _noise_t)
		terrain.call("set_shader_param", "u_hs_noise_axes", axes)
	# Keep root stable — displace is in the terrain shader now.
	if _env_root:
		_env_root.position = Vector3.ZERO


func _clear_terrain_noise_displace() -> void:
	var terrain: Variant = _terrain_meta.get("terrain", null) if not _terrain_meta.is_empty() else null
	if terrain == null or not is_instance_valid(terrain):
		return
	if terrain.has_method("set_shader_param"):
		terrain.call("set_shader_param", "u_hs_noise_amount", 0.0)


func _apply_terrain_noise_wobble(amount: float, axes: Vector3) -> void:
	## Legacy fallback — prefer _apply_terrain_noise_displace.
	_apply_terrain_noise_displace(amount, maxf(RH.noise_scale(), 0.5), axes)


func _apply_noise_to_root(root: Node, amount: float, feature: float, nseed: Vector3, axes: Vector3, active_ids: Dictionary, cloth_amt: float = 0.0, cloth_stiff: float = 0.55, cloth_wind: float = 0.0, cloth_grav: float = 1.0) -> void:
	if root == null or not is_instance_valid(root) or (amount <= 0.001 and cloth_amt <= 0.001):
		return
	var meshes := _noise_meshes_for(root)
	var limit := mini(meshes.size(), NOISE_MESH_LIMIT)
	for i in limit:
		var mi: MeshInstance3D = meshes[i] as MeshInstance3D
		if mi == null or not is_instance_valid(mi) or not mi.visible:
			continue
		# Skip draw-pass meshes belonging to particle systems.
		if mi.get_parent() is GPUParticles3D:
			continue
		if str(mi.name).begins_with("HSPointCloud"):
			continue
		# Media screens keep their own shader — driven via _apply_media_deform.
		if mi.get_meta("media_screen", false) or mi.get_parent() is FlythroughMediaProp:
			continue
		var nseed_i := nseed + Vector3(float(i), 0, 0)
		var mats := _ensure_noise_materials(mi, nseed_i)
		active_ids[mi.get_instance_id()] = true
		_stamp_noise_uniforms(mats, amount, feature, axes, cloth_amt, cloth_stiff, cloth_wind, cloth_grav, false)
	var mms: Array = []
	_collect_multimesh_instances(root, mms)
	for mmi_any in mms:
		var mmi := mmi_any as MultiMeshInstance3D
		if mmi == null or not is_instance_valid(mmi) or not mmi.visible:
			continue
		if bool(mmi.get_meta("media_screen", false)):
			continue
		var mats_mm := _ensure_noise_materials_gi(mmi, nseed, false)
		active_ids[mmi.get_instance_id()] = true
		_stamp_noise_uniforms(mats_mm, amount, feature, axes, cloth_amt, cloth_stiff, cloth_wind, cloth_grav, false)


func _noise_meshes_for(root: Node) -> Array:
	if root == null or not is_instance_valid(root):
		return []
	var key := root.get_instance_id()
	if _noise_mesh_lists.has(key):
		var cached: Array = _noise_mesh_lists[key]
		var cache_live := not cached.is_empty()
		for c in cached:
			if c == null or not is_instance_valid(c):
				cache_live = false
				break
		if cache_live:
			return cached
	var meshes: Array = []
	_collect_mesh_instances(root, meshes)
	_noise_mesh_lists[key] = meshes
	return meshes


func _ensure_noise_materials(mi: MeshInstance3D, nseed: Vector3) -> Array:
	var key := mi.get_instance_id()
	if _noise_mats.has(key):
		return _noise_mats[key]
	var backup := {"override": mi.material_override, "surfaces": []}
	var out: Array = []
	var for_points := _mesh_is_point_overlay(mi)
	if mi.material_override != null:
		var sm := _make_noise_shader_from(mi.material_override, nseed, for_points)
		backup["override"] = mi.material_override
		mi.material_override = sm
		out.append(sm)
	elif mi.mesh != null:
		var surfaces: Array = []
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s)
			surfaces.append(mi.get_surface_override_material(s))
			var sm2 := _make_noise_shader_from(base, nseed + Vector3(float(s) * 0.13, 0, 0), for_points)
			mi.set_surface_override_material(s, sm2)
			out.append(sm2)
		backup["surfaces"] = surfaces
	_noise_backup[key] = backup
	_noise_mats[key] = out
	return out


func _mesh_is_point_overlay(mi: MeshInstance3D) -> bool:
	if mi == null:
		return false
	if str(mi.name).begins_with("HSPointCloud"):
		return true
	if mi.mesh is ArrayMesh:
		var am := mi.mesh as ArrayMesh
		if am.get_surface_count() > 0:
			return am.surface_get_primitive_type(0) == Mesh.PRIMITIVE_POINTS
	return false


func _stamp_noise_uniforms(
	mats: Array,
	amount: float,
	feature: float,
	axes: Vector3,
	cloth_amt: float,
	cloth_stiff: float,
	cloth_wind: float,
	cloth_grav: float,
	for_points: bool
) -> void:
	for mat in mats:
		if not (mat is ShaderMaterial):
			continue
		var sm := mat as ShaderMaterial
		if sm.shader == null:
			continue
		sm.set_shader_parameter("noise_amount", amount)
		sm.set_shader_parameter("noise_scale", feature)
		sm.set_shader_parameter("noise_axes", axes)
		sm.set_shader_parameter("time_sec", _noise_t)
		sm.set_shader_parameter("cloth_amount", cloth_amt)
		sm.set_shader_parameter("cloth_stiffness", cloth_stiff)
		sm.set_shader_parameter("cloth_wind", cloth_wind)
		sm.set_shader_parameter("cloth_gravity", cloth_grav)
		sm.set_shader_parameter("cloth_time", _noise_t)
		if for_points:
			sm.set_shader_parameter("point_size", _point_cloud_size)


func _stamp_all_pc_overlays(
	amt: float,
	feature: float,
	axes: Vector3,
	cloth_amt: float,
	cloth_stiff: float,
	cloth_wind: float,
	cloth_grav: float,
	want_env: bool,
	want_center: bool,
	want_scatter: bool
) -> void:
	## Stamp visible overlays directly. Do not put them in `_noise_mats` — prune
	## restores StandardMaterial3D and kills vertex displace.
	if not _point_cloud_on:
		return
	for ov_any in _pc_overlays:
		if not SceneMeshFx.is_live(ov_any) or not (ov_any is MeshInstance3D):
			continue
		var ov := ov_any as MeshInstance3D
		var scaled: Dictionary = _pc_deform_for_node(ov, amt, feature, cloth_amt, want_env, want_center, want_scatter)
		_stamp_one_pc_overlay(
			ov, float(scaled["amt"]), float(scaled["feature"]), axes,
			float(scaled["cloth"]), cloth_stiff, cloth_wind, cloth_grav
		)
	for mmi in _scatter_mm_nodes:
		if not is_instance_valid(mmi) or not mmi.has_meta("hs_pc_overlay"):
			continue
		var pc_any: Variant = mmi.get_meta("hs_pc_overlay")
		if not SceneMeshFx.is_live(pc_any) or not (pc_any is GeometryInstance3D):
			continue
		var mm_amt := amt * 0.75 if want_scatter else 0.0
		var mm_feat := feature * 0.85 if want_scatter else feature
		var mm_cloth := cloth_amt * 0.8 if want_scatter else 0.0
		_stamp_one_pc_overlay(
			pc_any as GeometryInstance3D, mm_amt, mm_feat, axes,
			mm_cloth, cloth_stiff, cloth_wind, cloth_grav
		)


func _pc_deform_for_node(
	ov: Node,
	amt: float,
	feature: float,
	cloth_amt: float,
	want_env: bool,
	want_center: bool,
	want_scatter: bool
) -> Dictionary:
	if _scatter_root != null and is_instance_valid(_scatter_root) and _scatter_root.is_ancestor_of(ov):
		if want_scatter:
			return {"amt": amt * 0.75, "feature": feature * 0.85, "cloth": cloth_amt * 0.8}
		return {"amt": 0.0, "feature": feature, "cloth": 0.0}
	if _center_root != null and is_instance_valid(_center_root) and _center_root.is_ancestor_of(ov):
		if want_center:
			return {"amt": amt * 0.85, "feature": feature * 0.7, "cloth": cloth_amt * 0.9}
		return {"amt": 0.0, "feature": feature, "cloth": 0.0}
	if want_env:
		return {"amt": amt, "feature": feature, "cloth": cloth_amt}
	return {"amt": 0.0, "feature": feature, "cloth": 0.0}


func _stamp_one_pc_overlay(
	gi: GeometryInstance3D,
	amount: float,
	feature: float,
	axes: Vector3,
	cloth_amt: float,
	cloth_stiff: float,
	cloth_wind: float,
	cloth_grav: float
) -> void:
	var sm: ShaderMaterial = SceneMeshFx.ensure_point_deform_material(gi, _point_cloud_size)
	if sm == null:
		return
	var nseed := Vector3.ZERO
	var parent := gi.get_parent()
	if SceneMeshFx.is_live(parent) and parent is GeometryInstance3D:
		var pmat: Material = (parent as GeometryInstance3D).material_override
		if pmat is ShaderMaterial and (pmat as ShaderMaterial).shader != null:
			var ns: Variant = (pmat as ShaderMaterial).get_shader_parameter("noise_seed")
			if ns is Vector3:
				nseed = ns as Vector3
	if nseed == Vector3.ZERO:
		nseed = Vector3(float(gi.get_instance_id() % 997), 0.37, 0.19)
	sm.set_shader_parameter("noise_seed", nseed)
	_stamp_noise_uniforms([sm], amount, feature, axes, cloth_amt, cloth_stiff, cloth_wind, cloth_grav, true)


func _make_noise_shader_from(base: Material, nseed: Vector3, for_points: bool = false) -> ShaderMaterial:
	if for_points:
		var psm: ShaderMaterial = SceneMeshFx.make_point_deform_material(_point_cloud_size)
		psm.set_shader_parameter("noise_seed", nseed)
		return psm
	var sm := ShaderMaterial.new()
	sm.shader = NOISE_DEFORM_SHADER
	if sm.shader == null:
		return sm
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
	elif base is ShaderMaterial:
		# Media screens use ShaderMaterial — pull bound albedo if present so noise
		# never replaces a textured screen with flat gray/white.
		var shm := base as ShaderMaterial
		var bound: Variant = shm.get_shader_parameter("tex_albedo")
		if bound is Texture2D:
			tex = bound as Texture2D
			alb = Color(1, 1, 1)
	sm.set_shader_parameter("albedo_color", alb)
	sm.set_shader_parameter("roughness", rough)
	sm.set_shader_parameter("metallic", metal)
	sm.set_shader_parameter("noise_seed", nseed)
	sm.set_shader_parameter("noise_amount", 0.0)
	sm.set_shader_parameter("noise_scale", 1.0)
	sm.set_shader_parameter("noise_axes", Vector3.ONE)
	sm.set_shader_parameter("cloth_amount", 0.0)
	sm.set_shader_parameter("cloth_stiffness", 0.55)
	sm.set_shader_parameter("cloth_wind", 0.0)
	sm.set_shader_parameter("cloth_gravity", 1.0)
	sm.set_shader_parameter("cloth_time", 0.0)
	sm.set_shader_parameter("use_vertex_color", 1.0 if for_points else 0.0)
	sm.set_shader_parameter("point_size", _point_cloud_size if for_points else 0.0)
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
	if mi_obj == null or not is_instance_valid(mi_obj):
		_noise_backup.erase(key)
		_noise_mats.erase(key)
		return
	if mi_obj is MeshInstance3D:
		var mi := mi_obj as MeshInstance3D
		mi.material_override = backup.get("override", null)
		var surfaces: Array = backup.get("surfaces", [])
		for s in surfaces.size():
			mi.set_surface_override_material(s, surfaces[s])
	elif mi_obj is GeometryInstance3D:
		(mi_obj as GeometryInstance3D).material_override = backup.get("override", null)
	_noise_backup.erase(key)
	_noise_mats.erase(key)


func _clear_noise_deform(force_restore_rotation: bool = false) -> void:
	_clear_terrain_noise_displace()
	if _point_cloud_on:
		var cloth_keep := float(_cloth_params.get("amount", 0.7)) if _cloth_on else 0.0
		var cloth_stiff := float(_cloth_params.get("stiffness", 0.55)) if _cloth_on else 0.55
		var cloth_wind := float(_cloth_params.get("wind", 0.55)) if _cloth_on else 0.0
		var cloth_grav := float(_cloth_params.get("gravity", 1.0)) if _cloth_on else 1.0
		_stamp_all_pc_overlays(
			0.0, 1.0, Vector3.ONE, cloth_keep, cloth_stiff, cloth_wind, cloth_grav,
			true, true, true
		)
	if _cloth_on:
		for key in _noise_mats.keys():
			var mats: Array = _noise_mats[key]
			for mat in mats:
				if mat is ShaderMaterial:
					(mat as ShaderMaterial).set_shader_parameter("noise_amount", 0.0)
	else:
		var keys: Array = _noise_mats.keys()
		for key in keys:
			_restore_noise_material(int(key))
		_noise_mats.clear()
		_noise_backup.clear()
		_noise_mesh_lists.clear()
		_clear_media_deform()
		_clear_softbodies()
	if _env_root:
		_env_root.position = Vector3.ZERO
		if force_restore_rotation or _terrain_meta.is_empty() and (
			not RH.property_active("rotation") or not RH.rotation_applies_to("environment")
		):
			_restore_env_rotation()
	var cnode := _centerpiece_content_node()
	if cnode:
		cnode.position = Vector3.ZERO
		if force_restore_rotation or not RH.property_active("rotation") or not RH.rotation_applies_to("centerpiece"):
			_restore_centerpiece_rotation()
	for i in _scatter_nodes.size():
		if not is_instance_valid(_scatter_nodes[i]):
			continue
		if i < _scatter_base_positions.size():
			_scatter_nodes[i].position = _scatter_base_positions[i]
		if force_restore_rotation or not RH.property_active("rotation") or not RH.rotation_applies_to("scatter"):
			var rest: Vector3 = _scatter_rest_rotations[i] if i < _scatter_rest_rotations.size() else Vector3.ZERO
			_scatter_nodes[i].rotation = rest


func _apply_media_deform(
	noise_amt: float,
	feature: float,
	axes: Vector3,
	cloth_on: bool,
	cloth_amt: float,
	cloth_stiff: float,
	cloth_damp: float,
	cloth_wind: float,
	want_env: bool = true,
	want_center: bool = true,
	want_scatter: bool = true
) -> void:
	var props: Array = []
	_collect_media_props(self, props)
	## Same world-unit amount as other meshes (was * 0.012 — invisible on 1 m planes).
	var media_noise := noise_amt * 0.55
	var media_cloth := cloth_amt * 0.55
	var wind_vec := Vector3(cloth_wind * 2.4, cloth_wind * 0.2, cloth_wind * 0.9)
	for p in props:
		if not (p is FlythroughMediaProp) or not is_instance_valid(p):
			continue
		var prop := p as FlythroughMediaProp
		var allow := _media_prop_wants_deform(prop, want_env, want_center, want_scatter)
		if not allow:
			prop.set_softbody_cloth(false, cloth_stiff, cloth_damp, Vector3.ZERO)
			prop.set_deform_uniforms({})
			continue
		var scatter_mm := _scatter_root != null and _scatter_root.is_ancestor_of(prop) and not _scatter_mm_nodes.is_empty()
		if cloth_on and not _point_cloud_on and not scatter_mm:
			prop.set_softbody_cloth(true, cloth_stiff, cloth_damp, wind_vec)
		else:
			prop.set_softbody_cloth(false, cloth_stiff, cloth_damp, Vector3.ZERO)
		var shader_cloth := media_cloth if cloth_on else 0.0
		if cloth_on and prop.has_active_softbody():
			shader_cloth = 0.0
		prop.set_deform_uniforms({
			"deform_amount": media_noise,
			"deform_scale": feature,
			"deform_time": _noise_t,
			"deform_axes": axes,
			"cloth_amount": shader_cloth,
			"cloth_stiffness": cloth_stiff,
			"cloth_wind": cloth_wind,
			"cloth_time": _noise_t,
		})


func _media_prop_wants_deform(prop: FlythroughMediaProp, want_env: bool, want_center: bool, want_scatter: bool) -> bool:
	if _scatter_root != null and _scatter_root.is_ancestor_of(prop):
		return want_scatter
	if _center_root != null and _center_root.is_ancestor_of(prop):
		return want_center
	if _env_root != null and _env_root.is_ancestor_of(prop):
		return want_env
	return want_env or want_center or want_scatter


func _clear_media_deform() -> void:
	var props: Array = []
	_collect_media_props(self, props)
	for p in props:
		if p is FlythroughMediaProp and is_instance_valid(p):
			(p as FlythroughMediaProp).set_deform_uniforms({})


func _clear_softbodies() -> void:
	var props: Array = []
	_collect_media_props(self, props)
	for p in props:
		if p is FlythroughMediaProp and is_instance_valid(p):
			(p as FlythroughMediaProp).set_softbody_cloth(false, 0.55, 0.28, Vector3.ZERO)


func _collect_media_props(node: Node, out: Array) -> void:
	if node is FlythroughMediaProp:
		out.append(node)
	for child in node.get_children():
		_collect_media_props(child, out)


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
		"path_style", "camera_path":
			set_path_style(str(value))
		"environment", "scatter", "centerpiece", "lighting":
			if value is Dictionary:
				set_layer_source(key, value)
		"env_scale", "environment_scale", "user_scale":
			set_environment_user_scale(float(value))
		"centerpiece_scale":
			set_centerpiece_user_scale(float(value))
		"scatter_scale":
			set_scatter_user_scale(float(value))
		"scatter_global_scale":
			set_scatter_global_scale(float(value))
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
