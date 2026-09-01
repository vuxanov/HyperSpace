extends RefCounted
class_name SceneMeshFx

## Shared 3D mesh FX helpers: fake point-cloud overlays, camera DOF/lens, SoftBody wrap.
## Used by Scene3DItem / FlythroughEnvironment so effects can "affect everything".

const SOFTBODY_VERT_LIMIT := 1600
const SOFTBODY_MAX_PLANE := 8.0
## Point cloud CPU/GPU budget — env tiling can be 100+ mesh copies.
## Prefer a coarser cloud over a main-thread freeze.
const POINT_MESH_LIMIT := 48
const POINT_VERT_LIMIT := 1200
const POINT_VERT_LIMIT_TILE := 180
const POINT_TILE_MESH_LIMIT := 8
const POINT_INSTANCE_BUDGET := 28000
const POINT_IDLE_MS := 6
const POINT_FIRST_MS := 8
const POINT_PER_CHUNK := 3
const PC_ROLE_MAIN := 0
const PC_ROLE_SCATTER := 1
const PC_ROLE_ENV := 2
const PC_ROLE_OTHER := 3
const PC_ROLE_TILE := 4
## UV grid for a single image/GIF/video plane (scatter keeps source verts).
const MEDIA_POINT_GRID := 32
## Camera cull bit used to hide originals while the overlay child stays on layer 1.
const PC_HIDE_LAYER_BIT := 19
## Cached PRIMITIVE_POINTS meshes keyed by source Mesh instance_id (shared by scatter clones).
static var _pc_mesh_cache: Dictionary = {}
static var _pc_quad: QuadMesh
static var _pc_mm_cache: Dictionary = {}
static var _pc_img_cache: Dictionary = {}
static var _pc_surf_cache: Dictionary = {}
static var _pc_job: Dictionary = {}
static var _pc_tick_frame: int = -1
static var _pc_idle_armed: bool = false
## ArrayMeshes after tangent generation (imported GLBs can still lack ARRAY_TANGENT).
static var _tangent_mesh_cache: Dictionary = {}

const META_PC := "hs_pc_overlay"
const META_PC_LAYERS := "hs_pc_layers"
const META_PC_SHADOW := "hs_pc_shadow"
const META_PC_XPAR := "hs_pc_xpar"
const META_PC_SRC := "hs_pc_src"
const META_PC_VIS := "hs_pc_vis"
const META_PC_CULL := "hs_pc_cull"
const META_CAM := "hs_cam_fx_backup"
const META_SOFT := "hs_softbody"
const META_SOFT_SRC := "hs_softbody_src"
const POINT_DEFORM_SHADER: Shader = preload("res://effects/point_cloud.gdshader")
const MAT_OVERRIDE_VIZ_SHADER: Shader = preload("res://effects/material_override_viz.gdshader")
const META_MAT_OV := "hs_mat_ov_backup"
const META_MAT_OV_OURS := "hs_mat_ov_ours"
const META_MAT_OV_LOOK := "hs_mat_ov_look"
const META_NP_BACKUP := "np_mat_backup"
const META_NP_WRAP := "np_wrapped_mat"
static var _mat_ov_pbr: Dictionary = {}
static var _mat_ov_metal_tex: ImageTexture


static func is_live(obj: Variant) -> bool:
	## Safe before `is` / cast — Godot crashes if the left operand of `is` was already freed.
	return obj != null and is_instance_valid(obj)


static func is_media_instance(node: Node) -> bool:
	if not is_live(node):
		return false
	if bool(node.get_meta("media_screen", false)):
		return true
	return node.get_parent() is FlythroughMediaProp or node is FlythroughMediaProp


static func collect_meshes(root: Node, out: Array, skip_particles: bool = true, skip_media: bool = false) -> void:
	if not is_live(root):
		return
	if skip_media and root is FlythroughMediaProp:
		return
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var skip := skip_particles and mi.get_parent() is GPUParticles3D
		if not skip and not str(mi.name).begins_with("HSPointCloud"):
			var is_media := bool(mi.get_meta("media_screen", false)) or mi.get_parent() is FlythroughMediaProp
			if not (skip_media and is_media):
				out.append(mi)
	for child in root.get_children():
		collect_meshes(child, out, skip_particles, skip_media)


static func collect_geometry(root: Node, out: Array, skip_particles: bool = true, skip_media: bool = true) -> void:
	## MeshInstance3D + MultiMeshInstance3D for material override (scatter uses MultiMesh).
	if not is_live(root):
		return
	if skip_media and root is FlythroughMediaProp:
		return
	if root is GeometryInstance3D:
		var gi := root as GeometryInstance3D
		var skip := skip_particles and gi.get_parent() is GPUParticles3D
		var nm := str(gi.name)
		if not skip and not nm.begins_with("HSPointCloud") and (gi is MeshInstance3D or gi is MultiMeshInstance3D):
			var is_media := bool(gi.get_meta("media_screen", false)) or gi.get_parent() is FlythroughMediaProp
			if not (skip_media and is_media):
				out.append(gi)
	for child in root.get_children():
		collect_geometry(child, out, skip_particles, skip_media)


static func find_camera(root: Node) -> Camera3D:
	if not is_live(root):
		return null
	if root is Camera3D:
		return root as Camera3D
	for child in root.get_children():
		var found: Camera3D = find_camera(child)
		if found:
			return found
	return null


static func find_play_camera(root: Node) -> Camera3D:
	## Prefer the Camera3D that is actually drawing (imported GLBs ship extras).
	var cameras: Array[Camera3D] = []
	_collect_cameras(root, cameras)
	for cam in cameras:
		if cam.current:
			return cam
	if not cameras.is_empty():
		return cameras[0]
	return null


static func _collect_cameras(root: Node, out: Array[Camera3D]) -> void:
	if not is_live(root):
		return
	if root is Camera3D:
		out.append(root as Camera3D)
	for child in root.get_children():
		_collect_cameras(child, out)


static func disable_nested_cameras(root: Node, keep: Camera3D = null) -> void:
	## Imported GLBs often ship Camera3D nodes that steal `current` from the
	## flythrough gameplay camera after the first instantiate/swap.
	if not is_live(root):
		return
	if root is Camera3D and root != keep:
		(root as Camera3D).current = false
	for child in root.get_children():
		disable_nested_cameras(child, keep)


static func fov_from_focal_mm(focal_mm: float) -> float:
	## Horizontal FOV for a 36mm full-frame sensor. Godot Camera3D.fov is 1..179.
	var f := clampf(focal_mm, 0.5, 4000.0)
	var fov := rad_to_deg(2.0 * atan(36.0 / (2.0 * maxf(f, 0.5))))
	return clampf(fov, 1.0, 179.0)


## Focus-range slider (meters). Far at this value = infinity (far DoF off).
const CAM_FOCUS_NEAR_MIN := 0.4
const CAM_FOCUS_FAR_MAX := 80.0
const CAM_FOCUS_NEAR_DEFAULT := 1.5
const CAM_FOCUS_FAR_INF_EPS := 0.35


static func camera_focus_range(params: Dictionary) -> Vector2:
	## X = near handle (m), Y = far handle (m). Far at CAM_FOCUS_FAR_MAX = infinity.
	var near_v := CAM_FOCUS_NEAR_DEFAULT
	var far_v := CAM_FOCUS_FAR_MAX
	if params.has("focus_near"):
		near_v = float(params["focus_near"])
	elif params.has("focus_distance"):
		# Old single plane: keep the hero sharp (~3 m) and blur closer env.
		near_v = clampf(float(params["focus_distance"]) * 0.25, 0.8, 2.5)
	if params.has("focus_far"):
		far_v = float(params["focus_far"])
	near_v = maxf(near_v, CAM_FOCUS_NEAR_MIN)
	far_v = maxf(far_v, near_v)
	return Vector2(near_v, far_v)


static func camera_far_is_infinity(far_m: float) -> bool:
	return far_m >= CAM_FOCUS_FAR_MAX - CAM_FOCUS_FAR_INF_EPS


static func apply_camera_fx(camera: Camera3D, on: bool, params: Dictionary) -> void:
	if camera == null:
		return
	if not on:
		restore_camera_fx(camera)
		return
	if not camera.has_meta(META_CAM):
		camera.set_meta(META_CAM, {
			"fov": camera.fov,
			"attributes": camera.attributes,
		})
	var focal := float(params.get("focal_length", 28.0))
	var aperture := float(params.get("aperture", 2.8))
	var bokeh := clampf(float(params.get("bokeh", 0.55)), 0.0, 1.5)
	var lens := clampf(float(params.get("lens_distortion", 0.0)), 0.0, 1.0)
	var rng := camera_focus_range(params)
	var near_dist: float = rng.x
	var far_dist: float = rng.y
	var attr := CameraAttributesPractical.new()
	var cam_near := maxf(camera.near, 0.05)
	# Godot: 0 blur at near/far_distance; full near blur at distance - transition.
	# That full-blur plane must stay in FRONT of the camera or close env never smears.
	near_dist = maxf(near_dist, cam_near + 0.12)
	var fstop := maxf(aperture, 0.7)
	# Focus falloff expands the transition region rather than changing the blur strength.
	# That keeps the focal plane readable while removing the hard in/out-of-focus edge.
	var focus_softness := clampf(float(params.get("focus_softness", 0.7)), 0.0, 1.0)
	# Wide open (low f) = shallower DoF: tighter baseline ramp.
	var deep := clampf((fstop - 0.7) / 21.3, 0.0, 1.0)
	var near_frac := lerpf(lerpf(0.28, 0.75, deep), 0.95, focus_softness)
	var near_trans := clampf(near_dist * near_frac, 0.18, 3.5)
	near_trans = minf(near_trans, maxf(near_dist - cam_near - 0.04, 0.08))
	attr.dof_blur_near_enabled = bool(params.get("near_enabled", true))
	attr.dof_blur_near_distance = near_dist
	attr.dof_blur_near_transition = near_trans
	# Far handle at max = infinity: rest of the stage stays sharp.
	var far_at_inf := camera_far_is_infinity(far_dist)
	attr.dof_blur_far_enabled = not far_at_inf
	if not far_at_inf:
		var far_plane := maxf(far_dist, near_dist + 0.15)
		var far_frac := lerpf(lerpf(0.14, 0.45, deep), 0.9, focus_softness)
		attr.dof_blur_far_distance = far_plane
		attr.dof_blur_far_transition = clampf(far_plane * far_frac, 0.6, 32.0)
	# Aperture is primary (∝ 1/N). Bokeh scales it. Never force 1.0 from bokeh alone.
	var b01 := clampf(bokeh, 0.0, 1.0)
	var n_k := clampf(2.4 / fstop, 0.12, 1.0)
	attr.dof_blur_amount = clampf(b01 * n_k, 0.0, 1.0)
	camera.attributes = attr
	var fov := fov_from_focal_mm(focal)
	# Beyond fisheye the Camera3D FOV cannot represent the look; shader takes over.
	# Still push toward 179 so the capture is ultra-wide before the warp.
	if lens > 0.28:
		fov = lerpf(fov, 179.0, clampf((lens - 0.28) / 0.72, 0.0, 1.0))
	camera.fov = clampf(fov, 1.0, 179.0)


static func restore_camera_fx(camera: Camera3D) -> void:
	if camera == null or not camera.has_meta(META_CAM):
		return
	var backup: Dictionary = camera.get_meta(META_CAM)
	camera.fov = float(backup.get("fov", camera.fov))
	camera.attributes = backup.get("attributes", null)
	camera.remove_meta(META_CAM)


static func pc_targets_from(params: Dictionary) -> Dictionary:
	return {
		"target_environment": bool(params.get("target_environment", true)),
		"target_main": bool(params.get("target_main", true)),
		"target_scatter": bool(params.get("target_scatter", true)),
		"target_media": false,
	}


static func make_points_mesh_from(mi: MeshInstance3D, dense_media: bool = true) -> ArrayMesh:
	## Public wrapper so scatter MultiMesh can share the cached points mesh.
	return _mesh_to_points(mi, dense_media)


static func apply_point_cloud(root: Node, on: bool, point_size: float, include_media: bool = true) -> Array:
	return apply_point_cloud_layers(root, [root], on, point_size, include_media)


static func apply_point_cloud_layers(
	world: Node,
	layer_roots: Array,
	on: bool,
	point_size: float,
	include_media: bool = true,
	camera: Camera3D = null
) -> Array:
	## Queue overlays (main/scatter/primary env first). First burst this frame; rest on idle.
	## Never hides a solid until that mesh has an overlay. Env tiles are last and sparse.
	if world == null:
		return []
	if not on:
		cancel_point_cloud_build(world)
		clear_point_cloud(world)
		return []
	var cameras: Array[Camera3D] = []
	_collect_cameras(world, cameras)
	for cam in cameras:
		_ensure_pc_camera_cull(cam)
	if is_live(camera) and camera is Camera3D:
		_ensure_pc_camera_cull(camera as Camera3D)
	var items: Array = _pc_collect_budgeted(layer_roots, include_media)
	if not _pc_job.is_empty() and int(_pc_job.get("world_id", 0)) != world.get_instance_id():
		var prev_any: Variant = _pc_job.get("world")
		_pc_job.clear()
		_unhook_pc_idle()
		if is_live(prev_any) and prev_any is Node:
			clear_point_cloud(prev_any as Node)
	if not _pc_job.is_empty() and int(_pc_job.get("world_id", 0)) == world.get_instance_id():
		_pc_job["point_size"] = point_size
		_pc_job_merge(items)
		return _pc_job.get("overlays", []) as Array
	_pc_job = {
		"world": world,
		"world_id": world.get_instance_id(),
		"queue": items,
		"overlays": [],
		"active": {},
		"point_size": point_size,
		"instances": 0,
		"include_media": include_media,
	}
	_hook_pc_idle()
	tick_point_cloud_build(POINT_FIRST_MS)
	return _pc_job.get("overlays", []) as Array


static func point_cloud_build_pending(world: Node = null) -> bool:
	if _pc_job.is_empty():
		return false
	if world != null and int(_pc_job.get("world_id", 0)) != world.get_instance_id():
		return false
	return not (_pc_job.get("queue", []) as Array).is_empty()


static func point_cloud_overlays(world: Node = null) -> Array:
	if _pc_job.is_empty():
		return []
	if world != null and int(_pc_job.get("world_id", 0)) != world.get_instance_id():
		return []
	return _pc_job.get("overlays", []) as Array


static func cancel_point_cloud_build(world: Node = null) -> void:
	if _pc_job.is_empty():
		return
	if world != null and int(_pc_job.get("world_id", 0)) != world.get_instance_id():
		return
	_pc_job.clear()
	_unhook_pc_idle()


static func tick_point_cloud_build(max_ms: int = POINT_IDLE_MS) -> Array:
	if _pc_job.is_empty():
		_unhook_pc_idle()
		return []
	var frame := Engine.get_process_frames()
	if max_ms <= POINT_IDLE_MS and frame == _pc_tick_frame:
		return _pc_job.get("overlays", []) as Array
	_pc_tick_frame = frame
	var world_any: Variant = _pc_job.get("world")
	if not is_live(world_any) or not (world_any is Node):
		_pc_job.clear()
		_unhook_pc_idle()
		return []
	var world := world_any as Node
	var queue: Array = _pc_job.get("queue", []) as Array
	var overlays: Array = _pc_job.get("overlays", []) as Array
	var active: Dictionary = _pc_job.get("active", {}) as Dictionary
	var point_size := float(_pc_job.get("point_size", 6.0))
	var used := int(_pc_job.get("instances", 0))
	var t0 := Time.get_ticks_msec()
	var n := 0
	while not queue.is_empty():
		var item: Variant = queue.pop_front()
		if not (item is Dictionary):
			continue
		var gi_any: Variant = (item as Dictionary).get("gi")
		if not is_live(gi_any) or not (gi_any is GeometryInstance3D):
			continue
		var gi := gi_any as GeometryInstance3D
		var gid := gi.get_instance_id()
		if active.has(gid) or bool(gi.get_meta("hs_softbody_src", false)):
			continue
		if used >= POINT_INSTANCE_BUDGET or overlays.size() >= POINT_MESH_LIMIT:
			queue.clear()
			break
		var cap := int((item as Dictionary).get("cap", POINT_VERT_LIMIT))
		cap = mini(cap, POINT_INSTANCE_BUDGET - used)
		if cap < 8:
			queue.clear()
			break
		var overlay: GeometryInstance3D = null
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
			overlay = _ensure_point_overlay(gi as MeshInstance3D, point_size, cap)
		elif gi is MultiMeshInstance3D:
			overlay = _ensure_multimesh_overlay(gi as MultiMeshInstance3D, point_size, cap)
		if overlay != null:
			overlays.append(overlay)
			active[gid] = true
			used += _pc_overlay_instances(overlay)
		n += 1
		if n >= POINT_PER_CHUNK or Time.get_ticks_msec() - t0 >= max_ms:
			break
	_pc_job["queue"] = queue
	_pc_job["overlays"] = overlays
	_pc_job["active"] = active
	_pc_job["instances"] = used
	if queue.is_empty() or used >= POINT_INSTANCE_BUDGET or overlays.size() >= POINT_MESH_LIMIT:
		_prune_point_overlays(world, active)
		_pc_job["queue"] = []
		_unhook_pc_idle()
	return overlays


static func _hook_pc_idle() -> void:
	if _pc_idle_armed:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_pc_idle_armed = true
	tree.create_timer(0.0).timeout.connect(_on_pc_idle_timeout, CONNECT_ONE_SHOT)


static func _unhook_pc_idle() -> void:
	_pc_idle_armed = false


static func _on_pc_idle_timeout() -> void:
	_pc_idle_armed = false
	if _pc_job.is_empty():
		return
	tick_point_cloud_build()
	if point_cloud_build_pending():
		_hook_pc_idle()


static func _pc_collect_budgeted(layer_roots: Array, include_media: bool) -> Array:
	var items: Array = []
	var seen: Dictionary = {}
	var tile_n := 0
	for root_any in layer_roots:
		if not is_live(root_any) or not (root_any is Node):
			continue
		var root := root_any as Node
		var root_role := _pc_role_for_root(root)
		var batch: Array = []
		collect_geometry(root, batch, true, not include_media)
		for gi_any in batch:
			if not is_live(gi_any) or not (gi_any is GeometryInstance3D):
				continue
			var gi := gi_any as GeometryInstance3D
			var gid := gi.get_instance_id()
			if seen.has(gid) or bool(gi.get_meta("hs_softbody_src", false)):
				continue
			seen[gid] = true
			var role := root_role
			if root_role == PC_ROLE_ENV and _pc_is_env_tile(gi):
				role = PC_ROLE_TILE
			if role == PC_ROLE_TILE:
				if tile_n >= POINT_TILE_MESH_LIMIT:
					continue
				tile_n += 1
			var cap := POINT_VERT_LIMIT_TILE if role == PC_ROLE_TILE else POINT_VERT_LIMIT
			items.append({"gi": gi, "role": role, "cap": cap})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("role", PC_ROLE_OTHER)) < int(b.get("role", PC_ROLE_OTHER))
	)
	if items.size() > POINT_MESH_LIMIT:
		items.resize(POINT_MESH_LIMIT)
	return items


static func _pc_job_merge(items: Array) -> void:
	var queue: Array = _pc_job.get("queue", []) as Array
	var active: Dictionary = _pc_job.get("active", {}) as Dictionary
	var queued: Dictionary = {}
	for q_any in queue:
		if q_any is Dictionary and is_live((q_any as Dictionary).get("gi")):
			queued[((q_any as Dictionary).get("gi") as Object).get_instance_id()] = true
	for item_any in items:
		if not (item_any is Dictionary):
			continue
		var gi_any: Variant = (item_any as Dictionary).get("gi")
		if not is_live(gi_any):
			continue
		var gid := (gi_any as Object).get_instance_id()
		if active.has(gid) or queued.has(gid):
			continue
		queue.append(item_any)
		queued[gid] = true
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("role", PC_ROLE_OTHER)) < int(b.get("role", PC_ROLE_OTHER))
	)
	_pc_job["queue"] = queue
	_hook_pc_idle()


static func _pc_role_for_root(root: Node) -> int:
	if bool(root.get_meta("hs_np_main", false)) or str(root.name) == "Centerpiece":
		return PC_ROLE_MAIN
	if str(root.name) == "Scatter":
		return PC_ROLE_SCATTER
	if str(root.name) == "Environment":
		return PC_ROLE_ENV
	return PC_ROLE_OTHER


static func _pc_is_env_tile(n: Node) -> bool:
	var cur: Node = n
	while is_live(cur):
		if bool(cur.get_meta("hs_env_tile", false)):
			return true
		cur = cur.get_parent()
	return false


static func _pc_overlay_instances(overlay: GeometryInstance3D) -> int:
	if overlay is MultiMeshInstance3D:
		var mm: MultiMesh = (overlay as MultiMeshInstance3D).multimesh
		if mm != null:
			return mm.instance_count
	return 0


static func update_overlay_point_size(overlays: Array, point_size: float) -> bool:
	## Updates point size on live overlays. Prunes freed/invalid refs in-place.
	## Returns true if any entries were removed (caller should rebuild).
	var sz := maxf(point_size, 1.0)
	var pruned := false
	var i := 0
	while i < overlays.size():
		var ov_any: Variant = overlays[i]
		if not is_live(ov_any) or not (ov_any is GeometryInstance3D):
			overlays.remove_at(i)
			pruned = true
			continue
		var ov := ov_any as GeometryInstance3D
		var src: GeometryInstance3D = null
		if ov.has_meta(META_PC_SRC):
			var src_any: Variant = ov.get_meta(META_PC_SRC)
			if is_live(src_any) and src_any is GeometryInstance3D:
				src = src_any as GeometryInstance3D
		if src:
			_hide_original_pc_layers(src)
			ov.global_transform = src.global_transform
		_stamp_point_size(ov, sz)
		i += 1
	return pruned


static func _stamp_point_size(gi: GeometryInstance3D, point_size: float) -> void:
	if not is_live(gi):
		return
	var sz := maxf(point_size, 1.0)
	var mat: Material = gi.material_override
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		bm.use_point_size = true
		bm.point_size = sz
		bm.vertex_color_use_as_albedo = true
	elif mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		set_shader_param(sm, "point_size", sz)
		set_shader_param(sm, "viewport_size", _pc_vp_size(gi))


static func _pc_vp_size(node: Node) -> Vector2:
	if not is_live(node):
		return Vector2(1280, 720)
	var vp := node.get_viewport()
	if vp == null:
		return Vector2(1280, 720)
	var s := vp.get_visible_rect().size
	if s.x < 1.0 or s.y < 1.0:
		return Vector2(1280, 720)
	return s


static func clear_point_cloud(root: Node) -> void:
	cancel_point_cloud_build(root)
	if not is_live(root):
		return
	var camera: Camera3D = find_play_camera(root)
	_restore_pc_camera_cull(camera)
	# Imported GLB cameras may also have been stamped — restore any with the meta.
	var cameras: Array[Camera3D] = []
	_collect_cameras(root, cameras)
	for cam in cameras:
		_restore_pc_camera_cull(cam)
	var geos: Array = []
	collect_geometry(root, geos, false, false)
	for gi_any in geos:
		if is_live(gi_any) and gi_any is GeometryInstance3D:
			_restore_point_overlay(gi_any as GeometryInstance3D)


static func _ensure_pc_camera_cull(camera: Camera3D) -> void:
	if camera == null:
		return
	if not camera.has_meta(META_PC_CULL):
		camera.set_meta(META_PC_CULL, camera.cull_mask)
	camera.cull_mask = int(camera.get_meta(META_PC_CULL)) & ~(1 << PC_HIDE_LAYER_BIT)


static func _restore_pc_camera_cull(camera: Camera3D) -> void:
	if camera == null or not camera.has_meta(META_PC_CULL):
		return
	camera.cull_mask = int(camera.get_meta(META_PC_CULL))
	camera.remove_meta(META_PC_CULL)


static func _pc_sprite_mesh() -> QuadMesh:
	if _pc_quad == null or not is_instance_valid(_pc_quad):
		_pc_quad = QuadMesh.new()
		_pc_quad.size = Vector2(1.0, 1.0)
	return _pc_quad


static func _new_pc_mmi(mm: MultiMesh, point_size: float, media: bool) -> MultiMeshInstance3D:
	var overlay := MultiMeshInstance3D.new()
	overlay.name = "HSPointCloud"
	overlay.multimesh = mm
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	overlay.extra_cull_margin = 128.0
	overlay.layers = 1
	overlay.set_meta("hs_pc_vcol", true)
	overlay.set_meta("hs_pc_px", true)
	overlay.set_meta("hs_pc_mmq", true)
	overlay.material_override = make_point_deform_material(point_size, overlay)
	if media:
		overlay.set_meta("hs_pc_live_tex", true)
	return overlay


static func _discard_stale_pc_overlay(src: GeometryInstance3D) -> void:
	if not src.has_meta(META_PC):
		return
	var existing: Variant = src.get_meta(META_PC)
	if is_live(existing) and existing is Node:
		(existing as Node).queue_free()
	src.remove_meta(META_PC)


static func _ensure_point_overlay(mi: MeshInstance3D, point_size: float, vert_cap: int = POINT_VERT_LIMIT) -> GeometryInstance3D:
	var overlay: MultiMeshInstance3D = null
	var media := is_media_instance(mi)
	if mi.has_meta(META_PC):
		var existing: Variant = mi.get_meta(META_PC)
		if is_live(existing) and existing is MultiMeshInstance3D and bool((existing as Node).get_meta("hs_pc_mmq", false)):
			overlay = existing as MultiMeshInstance3D
		else:
			_discard_stale_pc_overlay(mi)
	if overlay != null and (not overlay.has_meta("hs_pc_sib") or (media and not overlay.has_meta("hs_pc_live_tex"))):
		_discard_stale_pc_overlay(mi)
		overlay = null
	if overlay == null:
		var mm: MultiMesh = _cached_multimesh_for_mi(mi, vert_cap)
		if mm == null:
			return null
		overlay = _new_pc_mmi(mm, point_size, media)
		_attach_overlay_sibling(mi, overlay)
		if media:
			bind_overlay_live_texture(overlay, mi)
	else:
		overlay.layers = 1
		_hide_original_pc_layers(mi)
		ensure_point_deform_material(overlay, point_size)
		update_overlay_point_size([overlay], point_size)
		if media:
			bind_overlay_live_texture(overlay, mi)
	return overlay


static func _ensure_multimesh_overlay(mmi: MultiMeshInstance3D, point_size: float, vert_cap: int = POINT_VERT_LIMIT) -> GeometryInstance3D:
	var src_mm: MultiMesh = mmi.multimesh
	if src_mm == null or src_mm.mesh == null:
		return null
	var overlay: MultiMeshInstance3D = null
	var media := is_media_instance(mmi)
	if mmi.has_meta(META_PC):
		var existing: Variant = mmi.get_meta(META_PC)
		if is_live(existing) and existing is MultiMeshInstance3D and bool((existing as Node).get_meta("hs_pc_mmq", false)):
			overlay = existing as MultiMeshInstance3D
		else:
			_discard_stale_pc_overlay(mmi)
	if overlay != null and not overlay.has_meta("hs_pc_sib"):
		_discard_stale_pc_overlay(mmi)
		overlay = null
	if overlay == null:
		var mm: MultiMesh = _multimesh_from_samples(_samples_from_scatter_mm(mmi, vert_cap))
		if mm == null:
			return null
		overlay = _new_pc_mmi(mm, point_size, media)
		_attach_overlay_sibling(mmi, overlay)
		if media:
			bind_overlay_live_texture(overlay, mmi)
	else:
		overlay.layers = 1
		_hide_original_pc_layers(mmi)
		ensure_point_deform_material(overlay, point_size)
		_stamp_point_size(overlay, point_size)
		if media:
			bind_overlay_live_texture(overlay, mmi)
	return overlay


static func _cached_multimesh_for_mi(mi: MeshInstance3D, vert_cap: int) -> MultiMesh:
	if mi == null or mi.mesh == null:
		return null
	if is_media_instance(mi):
		return _multimesh_from_samples(_samples_from_mi(mi, vert_cap))
	var src_info: Dictionary = _albedo_source(mi)
	var tex_id := 0
	if src_info.get("tex") is Texture2D:
		tex_id = (src_info["tex"] as Texture2D).get_instance_id()
	var key := "%d_%d_%d" % [mi.mesh.get_instance_id(), tex_id, vert_cap]
	if _pc_mm_cache.has(key):
		var cached: Variant = _pc_mm_cache[key]
		if is_live(cached) and cached is MultiMesh and (cached as MultiMesh).instance_count > 0:
			return cached as MultiMesh
		_pc_mm_cache.erase(key)
	var mm: MultiMesh = _multimesh_from_samples(_samples_from_mi(mi, vert_cap))
	if mm == null:
		return null
	if _pc_mm_cache.size() > 64:
		_pc_mm_cache.clear()
	_pc_mm_cache[key] = mm
	return mm


static func _samples_from_mi(mi: MeshInstance3D, vert_cap: int = POINT_VERT_LIMIT) -> Dictionary:
	var empty := {"pos": PackedVector3Array(), "col": PackedColorArray(), "uvs": PackedVector2Array()}
	if mi == null or mi.mesh == null:
		return empty
	var cap := maxi(vert_cap, 8)
	if is_media_instance(mi):
		return _media_grid_samples(mi)
	var src_info: Dictionary = _albedo_source(mi)
	var img: Image = _albedo_image(src_info.get("tex") as Texture2D)
	var tint: Color = src_info.get("tint", Color.WHITE)
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	var uvs_out := PackedVector2Array()
	var mesh: Mesh = mi.mesh
	for s in mesh.get_surface_count():
		var arrays: Array = _surface_arrays(mesh, s)
		if arrays.is_empty():
			continue
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if not (verts is PackedVector3Array) or (verts as PackedVector3Array).is_empty():
			continue
		var pv := verts as PackedVector3Array
		var colors: Variant = arrays[Mesh.ARRAY_COLOR]
		var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		var nrm: Variant = arrays[Mesh.ARRAY_NORMAL] if arrays.size() > Mesh.ARRAY_NORMAL else null
		var remain := cap - pos.size()
		if remain <= 0:
			break
		if pv.size() > remain:
			var strided: Dictionary = _stride_points(pv, colors, uvs, nrm, remain)
			pv = strided["verts"]
			colors = strided["colors"]
			uvs = strided["uvs"]
		var baked: PackedColorArray = _bake_point_colors(pv, uvs, colors, img, tint)
		var has_uv := uvs is PackedVector2Array and (uvs as PackedVector2Array).size() == pv.size()
		var uv_arr: PackedVector2Array = uvs as PackedVector2Array if has_uv else PackedVector2Array()
		for i in pv.size():
			pos.append(pv[i])
			col.append(baked[i])
			if has_uv:
				uvs_out.append(uv_arr[i])
		if pos.size() >= cap:
			break
	if pos.is_empty():
		var faces: PackedVector3Array = mesh.get_faces()
		if not faces.is_empty():
			var nrm_dummy: Variant = null
			if faces.size() > cap:
				var strided: Dictionary = _stride_points(faces, null, null, nrm_dummy, cap)
				faces = strided["verts"]
			pos = faces
			col = _bake_point_colors(pos, null, null, img, tint)
			uvs_out = PackedVector2Array()
	return {"pos": pos, "col": col, "uvs": uvs_out}


static func _media_grid_samples(mi: MeshInstance3D) -> Dictionary:
	var size := Vector2(1.6, 1.0)
	if mi.mesh is PlaneMesh:
		size = (mi.mesh as PlaneMesh).size
	var n := maxi(MEDIA_POINT_GRID, 8)
	var count := n * n
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	var uvs := PackedVector2Array()
	pos.resize(count)
	col.resize(count)
	uvs.resize(count)
	var i := 0
	for y in n:
		var v := float(y) / float(n - 1)
		for x in n:
			var u := float(x) / float(n - 1)
			pos[i] = Vector3((u - 0.5) * size.x, (0.5 - v) * size.y, 0.0)
			col[i] = Color.WHITE
			uvs[i] = Vector2(u, v)
			i += 1
	return {"pos": pos, "col": col, "uvs": uvs}


static func _samples_from_scatter_mm(mmi: MultiMeshInstance3D, vert_cap: int = POINT_VERT_LIMIT) -> Dictionary:
	var empty := {"pos": PackedVector3Array(), "col": PackedColorArray(), "uvs": PackedVector2Array()}
	var src_mm: MultiMesh = mmi.multimesh
	if src_mm == null or src_mm.mesh == null or src_mm.instance_count <= 0:
		return empty
	var tmp := MeshInstance3D.new()
	tmp.mesh = src_mm.mesh
	tmp.material_override = mmi.material_override
	if is_media_instance(mmi):
		tmp.set_meta("media_screen", true)
	var proto_cap := mini(maxi(vert_cap / maxi(src_mm.instance_count, 1), 8), 240)
	var base: Dictionary = _samples_from_mi(tmp, proto_cap)
	tmp.free()
	var base_pos: PackedVector3Array = base["pos"]
	var base_col: PackedColorArray = base["col"]
	var base_uvs: PackedVector2Array = base["uvs"]
	if base_pos.is_empty():
		return empty
	var inst_n := src_mm.instance_count
	var vert_n := base_pos.size()
	var total := inst_n * vert_n
	var cap := maxi(vert_cap, 8)
	var step := 1
	if total > cap:
		step = maxi(1, int(ceili(float(total) / float(cap))))
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	var uvs := PackedVector2Array()
	var has_uv := base_uvs.size() == vert_n
	var k := 0
	for i in inst_n:
		var xf := src_mm.get_instance_transform(i)
		for j in vert_n:
			if (k % step) != 0:
				k += 1
				continue
			k += 1
			pos.append(xf * base_pos[j])
			col.append(base_col[j] if j < base_col.size() else Color.WHITE)
			if has_uv:
				uvs.append(base_uvs[j])
			if pos.size() >= cap:
				return {"pos": pos, "col": col, "uvs": uvs}
	return {"pos": pos, "col": col, "uvs": uvs}


static func _multimesh_from_samples(samples: Dictionary) -> MultiMesh:
	if samples.is_empty() or not samples.has("pos"):
		return null
	var pos: PackedVector3Array = samples["pos"]
	var n := pos.size()
	if n <= 0:
		return null
	var col: PackedColorArray = samples.get("col", PackedColorArray()) as PackedColorArray
	if col.size() != n:
		col = PackedColorArray()
		col.resize(n)
		col.fill(Color.WHITE)
	var uvs: PackedVector2Array = samples.get("uvs", PackedVector2Array()) as PackedVector2Array
	var use_uv := uvs.size() == n
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _pc_sprite_mesh()
	mm.instance_count = n
	var stride := 20
	var buf := PackedFloat32Array()
	buf.resize(n * stride)
	for i in n:
		var o := i * stride
		var p := pos[i]
		buf[o] = 1.0
		buf[o + 1] = 0.0
		buf[o + 2] = 0.0
		buf[o + 3] = p.x
		buf[o + 4] = 0.0
		buf[o + 5] = 1.0
		buf[o + 6] = 0.0
		buf[o + 7] = p.y
		buf[o + 8] = 0.0
		buf[o + 9] = 0.0
		buf[o + 10] = 1.0
		buf[o + 11] = p.z
		var c := col[i]
		buf[o + 12] = c.r
		buf[o + 13] = c.g
		buf[o + 14] = c.b
		buf[o + 15] = 1.0
		if use_uv:
			buf[o + 16] = uvs[i].x
			buf[o + 17] = uvs[i].y
		else:
			buf[o + 16] = 0.5
			buf[o + 17] = 0.5
		buf[o + 18] = 0.0
		buf[o + 19] = 0.0
	mm.buffer = buf
	return mm


static func _attach_overlay_sibling(src: GeometryInstance3D, overlay: GeometryInstance3D) -> void:
	## Sibling so src.visible = false does not hide the vertex overlay.
	overlay.set_meta(META_PC_SRC, src)
	overlay.set_meta("hs_pc_sib", true)
	var host := src.get_parent()
	if host == null:
		src.add_child(overlay)
	else:
		host.add_child(overlay)
	overlay.global_transform = src.global_transform
	src.set_meta(META_PC, overlay)
	_hide_original_pc_layers(src)


static func sync_pc_overlay_transforms(overlays: Array) -> void:
	for ov_any in overlays:
		if not is_live(ov_any) or not (ov_any is Node3D):
			continue
		var ov := ov_any as Node3D
		if not ov.has_meta(META_PC_SRC):
			continue
		var src_any: Variant = ov.get_meta(META_PC_SRC)
		if is_live(src_any) and src_any is Node3D:
			ov.global_transform = (src_any as Node3D).global_transform
			if src_any is GeometryInstance3D:
				_hide_original_pc_layers(src_any as GeometryInstance3D)


static func _hide_original_pc_layers(gi: GeometryInstance3D) -> void:
	## Hide the shaded mesh. Overlay is a sibling, so it keeps drawing.
	if gi == null or not is_instance_valid(gi):
		return
	if not gi.has_meta(META_PC_VIS):
		gi.set_meta(META_PC_VIS, gi.visible)
	if not gi.has_meta(META_PC_SHADOW):
		gi.set_meta(META_PC_SHADOW, gi.cast_shadow)
	gi.visible = false
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not gi.has_meta(META_PC_LAYERS):
		gi.set_meta(META_PC_LAYERS, gi.layers)
	gi.layers = 1 << PC_HIDE_LAYER_BIT


static func _restore_original_pc_layers(gi: GeometryInstance3D) -> void:
	if gi == null or not is_instance_valid(gi):
		return
	if gi.has_meta(META_PC_VIS):
		gi.visible = bool(gi.get_meta(META_PC_VIS))
		gi.remove_meta(META_PC_VIS)
	else:
		gi.visible = true
	if gi.has_meta(META_PC_XPAR):
		gi.transparency = float(gi.get_meta(META_PC_XPAR))
		gi.remove_meta(META_PC_XPAR)
	if gi.has_meta(META_PC_LAYERS):
		gi.layers = int(gi.get_meta(META_PC_LAYERS))
		gi.remove_meta(META_PC_LAYERS)
	if gi.has_meta(META_PC_SHADOW):
		gi.cast_shadow = int(gi.get_meta(META_PC_SHADOW))
		gi.remove_meta(META_PC_SHADOW)


static func _restore_point_overlay(gi: GeometryInstance3D) -> void:
	if gi.has_meta(META_PC):
		var existing: Variant = gi.get_meta(META_PC)
		if is_live(existing) and existing is Node:
			(existing as Node).queue_free()
		gi.remove_meta(META_PC)
	_restore_original_pc_layers(gi)


static func _prune_point_overlays(root: Node, active: Dictionary) -> void:
	var geos: Array = []
	collect_geometry(root, geos, false, false)
	for gi_any in geos:
		if not is_live(gi_any) or not (gi_any is GeometryInstance3D):
			continue
		var gi := gi_any as GeometryInstance3D
		if gi.has_meta(META_PC) and not active.has(gi.get_instance_id()):
			_restore_point_overlay(gi)


static func _mesh_to_points(mi: MeshInstance3D, dense_media: bool = true) -> ArrayMesh:
	if mi == null or mi.mesh == null:
		return null
	var live_tex := is_media_instance(mi)
	if live_tex and dense_media:
		return _media_grid_points(mi)
	var mesh: Mesh = mi.mesh
	var src_info: Dictionary = _albedo_source(mi)
	var tex_id := 0
	if (not live_tex) and src_info.get("tex") is Texture2D:
		tex_id = (src_info["tex"] as Texture2D).get_instance_id()
	var key := "%d_%d_%s" % [mesh.get_instance_id(), tex_id, "liveq01" if live_tex else "vcol01"]
	if _pc_mesh_cache.has(key):
		var cached: Variant = _pc_mesh_cache[key]
		if is_live(cached) and cached is ArrayMesh and (cached as ArrayMesh).get_surface_count() > 0:
			return cached as ArrayMesh
		_pc_mesh_cache.erase(key)
	var img: Image = null if live_tex else _albedo_image(src_info.get("tex") as Texture2D)
	var tint: Color = src_info.get("tint", Color.WHITE)
	var out := ArrayMesh.new()
	var total := 0
	for s in mesh.get_surface_count():
		var arrays: Array = _surface_arrays(mesh, s)
		if arrays.is_empty():
			continue
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if not (verts is PackedVector3Array) or (verts as PackedVector3Array).is_empty():
			continue
		var pv := verts as PackedVector3Array
		var colors: Variant = arrays[Mesh.ARRAY_COLOR]
		var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		var nrm: Variant = arrays[Mesh.ARRAY_NORMAL] if arrays.size() > Mesh.ARRAY_NORMAL else null
		if pv.size() > POINT_VERT_LIMIT:
			var strided: Dictionary = _stride_points(pv, colors, uvs, nrm, POINT_VERT_LIMIT)
			pv = strided["verts"]
			colors = strided["colors"]
			uvs = strided["uvs"]
			nrm = strided["normals"]
		total += pv.size()
		if total > POINT_VERT_LIMIT * 2:
			break
		var baked: PackedColorArray
		if live_tex:
			baked = PackedColorArray()
			baked.resize(pv.size())
			baked.fill(Color.WHITE)
		else:
			baked = _bake_point_colors(pv, uvs, colors, img, tint)
		var packed: Array = []
		packed.resize(Mesh.ARRAY_MAX)
		packed[Mesh.ARRAY_VERTEX] = pv
		packed[Mesh.ARRAY_COLOR] = baked
		if uvs is PackedVector2Array and (uvs as PackedVector2Array).size() == pv.size():
			packed[Mesh.ARRAY_TEX_UV] = uvs
		if nrm is PackedVector3Array and (nrm as PackedVector3Array).size() == pv.size():
			packed[Mesh.ARRAY_NORMAL] = nrm
		packed = _expand_points_to_quads(packed)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, packed, [], {}, 0)
	if out.get_surface_count() <= 0:
		return null
	if _pc_mesh_cache.size() > 256:
		_pc_mesh_cache.clear()
	_pc_mesh_cache[key] = out
	return out


static func _expand_points_to_quads(packed: Array) -> Array:
	## Four camera-facing corners per source vertex. UV2 holds ±1 offsets for shader size.
	if packed.is_empty() or packed.size() <= Mesh.ARRAY_VERTEX:
		return packed
	var verts_v: Variant = packed[Mesh.ARRAY_VERTEX]
	if not (verts_v is PackedVector3Array) or (verts_v as PackedVector3Array).is_empty():
		return packed
	var verts := verts_v as PackedVector3Array
	var n := verts.size()
	var has_col := packed[Mesh.ARRAY_COLOR] is PackedColorArray \
		and (packed[Mesh.ARRAY_COLOR] as PackedColorArray).size() == n
	var has_uv := packed[Mesh.ARRAY_TEX_UV] is PackedVector2Array \
		and (packed[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == n
	var has_n := packed[Mesh.ARRAY_NORMAL] is PackedVector3Array \
		and (packed[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() == n
	var cols: PackedColorArray = packed[Mesh.ARRAY_COLOR] as PackedColorArray if has_col else PackedColorArray()
	var uvs: PackedVector2Array = packed[Mesh.ARRAY_TEX_UV] as PackedVector2Array if has_uv else PackedVector2Array()
	var nrms: PackedVector3Array = packed[Mesh.ARRAY_NORMAL] as PackedVector3Array if has_n else PackedVector3Array()
	var out_v := PackedVector3Array()
	var out_c := PackedColorArray()
	var out_uv := PackedVector2Array()
	var out_uv2 := PackedVector2Array()
	var out_n := PackedVector3Array()
	var idx := PackedInt32Array()
	out_v.resize(n * 4)
	out_uv2.resize(n * 4)
	idx.resize(n * 6)
	if has_col:
		out_c.resize(n * 4)
	if has_uv:
		out_uv.resize(n * 4)
	if has_n:
		out_n.resize(n * 4)
	var corners: Array[Vector2] = [
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)
	]
	for i in n:
		var base := i * 4
		for k in 4:
			var dst := base + k
			out_v[dst] = verts[i]
			out_uv2[dst] = corners[k]
			if has_col:
				out_c[dst] = cols[i]
			if has_uv:
				out_uv[dst] = uvs[i]
			if has_n:
				out_n[dst] = nrms[i]
		var t := i * 6
		idx[t] = base
		idx[t + 1] = base + 1
		idx[t + 2] = base + 2
		idx[t + 3] = base
		idx[t + 4] = base + 2
		idx[t + 5] = base + 3
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = out_v
	out[Mesh.ARRAY_TEX_UV2] = out_uv2
	out[Mesh.ARRAY_INDEX] = idx
	if has_col:
		out[Mesh.ARRAY_COLOR] = out_c
	if has_uv:
		out[Mesh.ARRAY_TEX_UV] = out_uv
	if has_n:
		out[Mesh.ARRAY_NORMAL] = out_n
	return out


static func _surface_arrays(mesh: Mesh, surface: int) -> Array:
	if mesh == null:
		return []
	var key := "%d_%d" % [mesh.get_instance_id(), surface]
	if _pc_surf_cache.has(key):
		var cached: Variant = _pc_surf_cache[key]
		if cached is Array and _arrays_have_verts(cached as Array):
			return cached as Array
		_pc_surf_cache.erase(key)
	var arrays: Array = mesh.surface_get_arrays(surface)
	if _arrays_have_verts(arrays):
		_pc_cache_surf(key, arrays)
		return arrays
	## Compressed importer meshes often return empty arrays — SurfaceTool decompresses.
	var st := SurfaceTool.new()
	st.create_from(mesh, surface)
	var from_st: Array = st.commit_to_arrays()
	if _arrays_have_verts(from_st):
		_pc_cache_surf(key, from_st)
		return from_st
	var baked: ArrayMesh = st.commit()
	if baked != null and baked.get_surface_count() > 0:
		arrays = baked.surface_get_arrays(0)
		if _arrays_have_verts(arrays):
			_pc_cache_surf(key, arrays)
			return arrays
	var faces: PackedVector3Array = mesh.get_faces()
	if faces.is_empty():
		return []
	var packed: Array = []
	packed.resize(Mesh.ARRAY_MAX)
	packed[Mesh.ARRAY_VERTEX] = faces
	_pc_cache_surf(key, packed)
	return packed


static func _pc_cache_surf(key: String, arrays: Array) -> void:
	if _pc_surf_cache.size() > 128:
		_pc_surf_cache.clear()
	_pc_surf_cache[key] = arrays


static func _arrays_have_verts(arrays: Array) -> bool:
	if arrays.is_empty() or arrays.size() <= Mesh.ARRAY_VERTEX:
		return false
	var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
	return verts is PackedVector3Array and not (verts as PackedVector3Array).is_empty()


static func _stride_points(verts: PackedVector3Array, colors: Variant, uvs: Variant, normals: Variant, cap: int) -> Dictionary:
	var n := verts.size()
	var step := maxi(1, int(ceil(float(n) / float(max(cap, 1)))))
	var out_v := PackedVector3Array()
	var out_c := PackedColorArray()
	var out_uv := PackedVector2Array()
	var out_n := PackedVector3Array()
	var has_c := colors is PackedColorArray and (colors as PackedColorArray).size() == n
	var has_uv := uvs is PackedVector2Array and (uvs as PackedVector2Array).size() == n
	var has_n := normals is PackedVector3Array and (normals as PackedVector3Array).size() == n
	var i := 0
	while i < n:
		out_v.append(verts[i])
		if has_c:
			out_c.append((colors as PackedColorArray)[i])
		if has_uv:
			out_uv.append((uvs as PackedVector2Array)[i])
		if has_n:
			out_n.append((normals as PackedVector3Array)[i])
		i += step
	return {
		"verts": out_v,
		"colors": out_c if has_c else colors,
		"uvs": out_uv if has_uv else uvs,
		"normals": out_n if has_n else normals,
	}


static func _albedo_source(mi: MeshInstance3D) -> Dictionary:
	var alb := Color.WHITE
	var tex: Texture2D = null
	var src: Material = mi.material_override
	if src == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
		src = mi.get_active_material(0)
	if src is BaseMaterial3D:
		var sm0 := src as BaseMaterial3D
		alb = sm0.albedo_color
		tex = sm0.albedo_texture
	elif src is ShaderMaterial:
		var shm := src as ShaderMaterial
		var bound: Variant = shm.get_shader_parameter("tex_albedo")
		if bound == null:
			bound = shm.get_shader_parameter("albedo_tex")
		if bound is Texture2D:
			tex = bound as Texture2D
		var alb_c: Variant = shm.get_shader_parameter("albedo_color")
		if alb_c is Color:
			alb = alb_c as Color
		var modu: Variant = shm.get_shader_parameter("modulate")
		if modu is Color:
			alb *= modu as Color
	return {"tex": tex, "tint": alb}


static func bind_overlay_live_texture(overlay: GeometryInstance3D, source: GeometryInstance3D) -> void:
	## Copy the current albedo texture onto a point overlay so GIF/video frames keep moving.
	if not is_live(overlay) or not is_live(source):
		return
	var mat: Material = overlay.material_override
	if not (mat is ShaderMaterial):
		return
	var sm := mat as ShaderMaterial
	if not shader_usable(sm):
		return
	var src_mat: Material = source.material_override
	var tex: Texture2D = null
	var tint := Color.WHITE
	var exposure := 1.0
	if src_mat is ShaderMaterial:
		var shm := src_mat as ShaderMaterial
		var bound: Variant = shm.get_shader_parameter("tex_albedo")
		if bound == null:
			bound = shm.get_shader_parameter("albedo_tex")
		if bound is Texture2D:
			tex = bound as Texture2D
		var alb_c: Variant = shm.get_shader_parameter("albedo_color")
		if alb_c is Color:
			tint = alb_c as Color
		var modu: Variant = shm.get_shader_parameter("modulate")
		if modu is Color:
			tint *= modu as Color
		var exp: Variant = shm.get_shader_parameter("exposure_comp")
		if typeof(exp) == TYPE_FLOAT or typeof(exp) == TYPE_INT:
			exposure = float(exp)
	elif src_mat is BaseMaterial3D:
		var bm := src_mat as BaseMaterial3D
		tex = bm.albedo_texture
		tint = bm.albedo_color
	if tex != null:
		sm.set_shader_parameter("tex_albedo", tex)
		sm.set_shader_parameter("has_tex", 1.0)
		sm.set_shader_parameter("albedo_color", tint)
		sm.set_shader_parameter("exposure_comp", exposure)
	else:
		sm.set_shader_parameter("has_tex", 0.0)


static func _media_grid_points(mi: MeshInstance3D) -> ArrayMesh:
	## Denser UV lattice than the deform grid so a still/GIF reads as a point image.
	var size := Vector2(1.6, 1.0)
	if mi.mesh is PlaneMesh:
		size = (mi.mesh as PlaneMesh).size
	var n := maxi(MEDIA_POINT_GRID, 8)
	var key := "media_grid_%.4f_%.4f_%d_q01" % [size.x, size.y, n]
	if _pc_mesh_cache.has(key):
		var cached: Variant = _pc_mesh_cache[key]
		if is_live(cached) and cached is ArrayMesh and (cached as ArrayMesh).get_surface_count() > 0:
			return cached as ArrayMesh
		_pc_mesh_cache.erase(key)
	var count := n * n
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var nrm := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(count)
	uvs.resize(count)
	nrm.resize(count)
	cols.resize(count)
	var i := 0
	for y in n:
		var v := float(y) / float(n - 1)
		for x in n:
			var u := float(x) / float(n - 1)
			verts[i] = Vector3((u - 0.5) * size.x, (0.5 - v) * size.y, 0.0)
			uvs[i] = Vector2(u, v)
			nrm[i] = Vector3(0.0, 0.0, 1.0)
			cols[i] = Color.WHITE
			i += 1
	var packed: Array = []
	packed.resize(Mesh.ARRAY_MAX)
	packed[Mesh.ARRAY_VERTEX] = verts
	packed[Mesh.ARRAY_TEX_UV] = uvs
	packed[Mesh.ARRAY_NORMAL] = nrm
	packed[Mesh.ARRAY_COLOR] = cols
	packed = _expand_points_to_quads(packed)
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, packed, [], {}, 0)
	if _pc_mesh_cache.size() > 256:
		_pc_mesh_cache.clear()
	_pc_mesh_cache[key] = out
	return out


static func _albedo_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var tid := tex.get_instance_id()
	if _pc_img_cache.has(tid):
		var cached: Variant = _pc_img_cache[tid]
		if cached is Image:
			return cached as Image
		_pc_img_cache.erase(tid)
	var img: Image = tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8)
	if _pc_img_cache.size() > 32:
		_pc_img_cache.clear()
	_pc_img_cache[tid] = img
	return img


static func _bake_point_colors(verts: PackedVector3Array, uvs: Variant, vcols: Variant, img: Image, tint: Color) -> PackedColorArray:
	var n := verts.size()
	var out := PackedColorArray()
	out.resize(n)
	var has_uv := uvs is PackedVector2Array and (uvs as PackedVector2Array).size() == n
	var has_vc := vcols is PackedColorArray and (vcols as PackedColorArray).size() == n
	var uv_arr: PackedVector2Array = uvs as PackedVector2Array if has_uv else PackedVector2Array()
	var vc_arr: PackedColorArray = vcols as PackedColorArray if has_vc else PackedColorArray()
	for i in n:
		var c := tint
		if has_vc:
			c *= vc_arr[i]
		if img != null and has_uv:
			c *= _sample_tex_neighborhood(img, uv_arr[i])
		out[i] = Color(c.r, c.g, c.b, 1.0)
	if img != null and not has_uv:
		## No UVs: spread any vertex-color variation; otherwise keep tint (unique per-vertex if vcols).
		for i in n:
			if i > 0 and i + 1 < n and has_vc:
				out[i] = out[i].lerp(out[i - 1], 0.35)
	return out


static func _sample_tex_neighborhood(img: Image, uv: Vector2) -> Color:
	## Bilinear sample plus a tiny 3-tap kernel so each vertex picks up nearby texels.
	var a := _sample_bilinear(img, uv)
	var b := _sample_bilinear(img, uv + Vector2(0.004, 0.0))
	var c := _sample_bilinear(img, uv + Vector2(0.0, 0.004))
	var d := _sample_bilinear(img, uv + Vector2(-0.003, -0.003))
	return (a * 2.0 + b + c + d) * 0.2


static func _sample_bilinear(img: Image, uv: Vector2) -> Color:
	var w := img.get_width()
	var h := img.get_height()
	if w <= 1 or h <= 1:
		return img.get_pixel(0, 0)
	var fx := fposmod(uv.x, 1.0) * float(w - 1)
	var fy := fposmod(uv.y, 1.0) * float(h - 1)
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var x1 := mini(x0 + 1, w - 1)
	var y1 := mini(y0 + 1, h - 1)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var c00 := img.get_pixel(x0, y0)
	var c10 := img.get_pixel(x1, y0)
	var c01 := img.get_pixel(x0, y1)
	var c11 := img.get_pixel(x1, y1)
	return c00.lerp(c10, tx).lerp(c01.lerp(c11, tx), ty)


static func shader_usable(sm: ShaderMaterial) -> bool:
	return sm != null and is_instance_valid(sm) and sm.shader != null


static func set_shader_param(sm: ShaderMaterial, key: String, value: Variant) -> void:
	if not shader_usable(sm):
		return
	sm.set_shader_parameter(key, value)


static func make_point_deform_material(point_size: float, host: Node = null) -> ShaderMaterial:
	## Unshaded vertex dots + the same noise/cloth vertex displace as noise_deform.gdshader.
	var sm := ShaderMaterial.new()
	sm.shader = POINT_DEFORM_SHADER
	if not shader_usable(sm):
		return sm
	sm.set_shader_parameter("albedo_color", Color.WHITE)
	sm.set_shader_parameter("has_tex", 0.0)
	sm.set_shader_parameter("point_size", maxf(point_size, 1.0))
	sm.set_shader_parameter("viewport_size", _pc_vp_size(host) if host != null else Vector2(1280, 720))
	sm.set_shader_parameter("exposure_comp", 1.0)
	sm.set_shader_parameter("noise_amount", 0.0)
	sm.set_shader_parameter("noise_scale", 1.0)
	sm.set_shader_parameter("noise_axes", Vector3.ONE)
	sm.set_shader_parameter("noise_seed", Vector3.ZERO)
	sm.set_shader_parameter("time_sec", 0.0)
	sm.set_shader_parameter("cloth_amount", 0.0)
	sm.set_shader_parameter("cloth_stiffness", 0.55)
	sm.set_shader_parameter("cloth_wind", 0.0)
	sm.set_shader_parameter("cloth_gravity", 1.0)
	sm.set_shader_parameter("cloth_time", 0.0)
	return sm


static func is_point_deform_material(mat: Material) -> bool:
	if mat == null or not (mat is ShaderMaterial):
		return false
	var sh: Shader = (mat as ShaderMaterial).shader
	return sh == POINT_DEFORM_SHADER


static func ensure_point_deform_material(gi: GeometryInstance3D, point_size: float) -> ShaderMaterial:
	if gi == null or not is_instance_valid(gi):
		return null
	var mat: Material = gi.material_override
	if is_point_deform_material(mat):
		_stamp_point_size(gi, point_size)
		return mat as ShaderMaterial
	var sm := make_point_deform_material(point_size, gi)
	gi.material_override = sm
	return sm


static func mesh_vertex_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var n := 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if verts is PackedVector3Array:
			n += (verts as PackedVector3Array).size()
	return n


static func is_softbody_eligible(mi: MeshInstance3D) -> bool:
	if mi == null or not is_instance_valid(mi) or mi.mesh == null:
		return false
	if mi is SoftBody3D:
		return true
	if bool(mi.get_meta("media_screen", false)) or mi.get_parent() is FlythroughMediaProp:
		return false
	var n := mesh_vertex_count(mi.mesh)
	if n < 24 or n > SOFTBODY_VERT_LIMIT:
		return false
	if mi.mesh is PlaneMesh:
		var pm := mi.mesh as PlaneMesh
		if pm.size.x > SOFTBODY_MAX_PLANE or pm.size.y > SOFTBODY_MAX_PLANE:
			return false
		return pm.subdivide_width >= 4 and pm.subdivide_depth >= 4
	return n <= 900


static func pin_top_edge(soft: SoftBody3D) -> void:
	if soft == null or soft.mesh == null:
		return
	var arrays: Array = soft.mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return
	var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
	if not (verts is PackedVector3Array):
		return
	var pv := verts as PackedVector3Array
	if pv.is_empty():
		return
	var min_v := pv[0]
	var max_v := pv[0]
	for v in pv:
		min_v = Vector3(minf(min_v.x, v.x), minf(min_v.y, v.y), minf(min_v.z, v.z))
		max_v = Vector3(maxf(max_v.x, v.x), maxf(max_v.y, v.y), maxf(max_v.z, v.z))
	var span := max_v - min_v
	# Pin the "top" of a hanging sheet. Horizontal floors (tiny Y span) are not SoftBody.
	if span.y < maxf(span.x, span.z) * 0.12:
		return
	var max_y := max_v.y
	var row := span.y / 24.0 if span.y > 0.001 else 0.002
	var thresh := max_y - maxf(row, 0.002)
	var pins := PackedInt32Array()
	for i in pv.size():
		if pv[i].y >= thresh:
			pins.append(i)
	if pins.is_empty():
		pins.append(0)
	soft.pinned_points = pins


static func apply_softbody_wind(soft: SoftBody3D, wind: Vector3) -> void:
	if soft == null or not is_instance_valid(soft):
		return
	if wind.length_squared() < 1e-8:
		return
	var rid: RID = soft.get_rid()
	if not rid.is_valid():
		return
	var n := mesh_vertex_count(soft.mesh)
	if n <= 0:
		return
	var pinned: Dictionary = {}
	for idx in soft.pinned_points:
		pinned[int(idx)] = true
	# Tiny impulses — large forces explode Godot SoftBody into a fracture.
	var impulse := wind * (0.0024 / maxf(float(n), 1.0) * 48.0)
	if impulse.length() > 0.012:
		impulse = impulse.normalized() * 0.012
	var step := maxi(1, n / 40)
	var i := 0
	while i < n:
		if not pinned.has(i):
			PhysicsServer3D.soft_body_apply_point_impulse(rid, i, impulse)
		i += step


static func ensure_mesh_tangents(root: Node) -> void:
	## Normal-mapped materials need ARRAY_TANGENT. Some imported surfaces omit them
	## even with meshes/ensure_tangents=true (no UVs / failed gen).
	if not is_live(root):
		return
	if root is MeshInstance3D:
		_fix_mesh_instance_tangents(root as MeshInstance3D)
	var nodes: Array = root.find_children("*", "MeshInstance3D", true, false)
	for n in nodes:
		_fix_mesh_instance_tangents(n as MeshInstance3D)


static func _fix_mesh_instance_tangents(mi: MeshInstance3D) -> void:
	if mi == null or not is_instance_valid(mi) or mi.mesh == null:
		return
	if not _instance_needs_tangents(mi):
		return
	if not _mesh_missing_tangents(mi.mesh):
		return
	if mi.mesh is ArrayMesh:
		var fixed: ArrayMesh = _array_mesh_with_tangents(mi.mesh as ArrayMesh)
		if fixed != null and not _mesh_missing_tangents(fixed):
			mi.mesh = fixed
			return
	_disable_normal_maps(mi)


static func _instance_needs_tangents(mi: MeshInstance3D) -> bool:
	if _material_needs_tangents(mi.material_override):
		return true
	if mi.mesh == null:
		return false
	for s in mi.mesh.get_surface_count():
		if _material_needs_tangents(mi.get_active_material(s)):
			return true
	return false


static func _material_needs_tangents(mat: Material) -> bool:
	if mat == null:
		return false
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		return bm.normal_enabled or bm.normal_texture != null
	return false


static func _mesh_missing_tangents(mesh: Mesh) -> bool:
	if mesh == null or not (mesh is ArrayMesh):
		return false
	var am := mesh as ArrayMesh
	for s in am.get_surface_count():
		var arrays: Array = am.surface_get_arrays(s)
		if arrays.size() <= Mesh.ARRAY_TANGENT:
			return true
		var tangents: Variant = arrays[Mesh.ARRAY_TANGENT]
		if tangents == null:
			return true
		if tangents is PackedFloat32Array and (tangents as PackedFloat32Array).is_empty():
			return true
	return false


static func _array_mesh_with_tangents(src: ArrayMesh) -> ArrayMesh:
	if src == null:
		return null
	var id := src.get_instance_id()
	if _tangent_mesh_cache.has(id):
		var cached: ArrayMesh = _tangent_mesh_cache[id] as ArrayMesh
		if cached != null:
			return cached
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var st := SurfaceTool.new()
		st.create_from(src, s)
		var arrays: Array = src.surface_get_arrays(s)
		var has_uv := arrays.size() > Mesh.ARRAY_TEX_UV \
			and arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array \
			and not (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty()
		var has_n := arrays.size() > Mesh.ARRAY_NORMAL \
			and arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array \
			and not (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).is_empty()
		if not has_n:
			st.generate_normals()
		if has_uv:
			st.generate_tangents()
		out = st.commit(out)
	_tangent_mesh_cache[id] = out
	return out


static func _disable_normal_maps(mi: MeshInstance3D) -> void:
	if mi.material_override is BaseMaterial3D:
		var ov := (mi.material_override as BaseMaterial3D).duplicate() as BaseMaterial3D
		ov.normal_enabled = false
		ov.normal_texture = null
		mi.material_override = ov
	if mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(s)
		if not (mat is BaseMaterial3D):
			continue
		var bm := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
		bm.normal_enabled = false
		bm.normal_texture = null
		mi.set_surface_override_material(s, bm)


static func layer_mat_override_look(config: Dictionary) -> String:
	## Empty / Off = no per-item look (original materials).
	var raw := str(config.get("mat_override", config.get("material_override", ""))).strip_edges()
	if raw.is_empty():
		return ""
	var low := raw.to_lower()
	if low == "off" or low == "none" or low == "original":
		return ""
	return MaterialOverrideEffect.normalize_look(raw)


static func apply_material_override_on_root(root: Node, on: bool, look: String) -> void:
	## Stamp or restore only geometry under `root` (does not touch sibling layers).
	if not is_live(root):
		return
	var geos: Array = []
	collect_geometry(root, geos, true, true)
	if not on or str(look).strip_edges().is_empty():
		for gi_any in geos:
			if gi_any is GeometryInstance3D:
				_restore_material_override_one(gi_any as GeometryInstance3D)
		return
	var look_n := MaterialOverrideEffect.normalize_look(look)
	for gi_any2 in geos:
		if gi_any2 is GeometryInstance3D:
			_stamp_material_override(gi_any2 as GeometryInstance3D, look_n)


static func stamp_material_override_roots(roots: Array, look: String) -> void:
	## Global FX: stamp targeted roots only — never restore untargeted per-item looks.
	var look_n := MaterialOverrideEffect.normalize_look(look)
	for r_any in roots:
		if r_any is Node:
			apply_material_override_on_root(r_any as Node, true, look_n)


static func apply_material_override_layers(world: Node, roots: Array, on: bool, look: String) -> void:
	var look_n := MaterialOverrideEffect.normalize_look(look)
	if not on or look_n.is_empty():
		restore_material_override(world)
		return
	var geos: Array = []
	for r_any in roots:
		if r_any is Node:
			collect_geometry(r_any as Node, geos, true, true)
	var wanted: Dictionary = {}
	for gi_any in geos:
		if not (gi_any is GeometryInstance3D):
			continue
		var gi := gi_any as GeometryInstance3D
		wanted[gi.get_instance_id()] = true
		_stamp_material_override(gi, look_n)
	var all: Array = []
	collect_geometry(world, all, true, false)
	for gi2_any in all:
		if not (gi2_any is GeometryInstance3D):
			continue
		var gi2 := gi2_any as GeometryInstance3D
		if gi2.has_meta(META_MAT_OV) and not wanted.has(gi2.get_instance_id()):
			_restore_material_override_one(gi2)


static func geometry_has_mat_override(gi: GeometryInstance3D) -> bool:
	## True while a look is stamped — reactive emission must not duplicate/glow these.
	return is_live(gi) and gi.has_meta(META_MAT_OV)


static func restore_material_override(root: Node) -> void:
	if not is_live(root):
		return
	var geos: Array = []
	collect_geometry(root, geos, true, false)
	for gi_any in geos:
		if gi_any is GeometryInstance3D:
			_restore_material_override_one(gi_any as GeometryInstance3D)


static func _restore_material_override_one(gi: GeometryInstance3D) -> void:
	if not is_live(gi):
		return
	if gi.has_meta(META_MAT_OV):
		var backup: Variant = gi.get_meta(META_MAT_OV)
		gi.material_override = backup as Material if backup is Material else null
		gi.remove_meta(META_MAT_OV)
	elif _is_mat_ov_ours(gi.material_override):
		# Noise clear / tile copy can leave shared cladding with no backup meta.
		gi.material_override = null
	if gi.has_meta(META_MAT_OV_LOOK):
		gi.remove_meta(META_MAT_OV_LOOK)


static func _stamp_material_override(gi: GeometryInstance3D, look: String) -> void:
	if not is_live(gi):
		return
	# Point-cloud overlays keep their deform shader; solids stay hidden on the cull bit.
	if str(gi.name).begins_with("HSPointCloud"):
		return
	if _override_already_applied(gi, look):
		return
	if not gi.has_meta(META_MAT_OV):
		var prev: Material = gi.material_override
		if _is_mat_ov_ours(prev) or _is_np_wrap_material(prev):
			prev = null
		gi.set_meta(META_MAT_OV, prev)
	var mat := _make_override_material(gi, look)
	if mat == null:
		_restore_material_override_one(gi)
		return
	gi.set_meta(META_MAT_OV_LOOK, look)
	gi.material_override = mat
	# Drop stale Bend wrap backup so the next scan wraps this look, not the previous one.
	if gi.has_meta(META_NP_BACKUP):
		gi.remove_meta(META_NP_BACKUP)


static func _override_already_applied(gi: GeometryInstance3D, look: String) -> bool:
	if not gi.has_meta(META_MAT_OV):
		return false
	if str(gi.get_meta(META_MAT_OV_LOOK, "")) != look:
		return false
	var mat: Material = gi.material_override
	if mat == null or not is_instance_valid(mat):
		return false
	if _is_mat_ov_ours(mat):
		return true
	if _is_np_wrap_material(mat):
		return true
	if look == "Normal" and mat is ShaderMaterial \
			and (mat as ShaderMaterial).shader == MAT_OVERRIDE_VIZ_SHADER:
		return true
	return false


static func _is_np_wrap_material(mat: Material) -> bool:
	return mat != null and is_instance_valid(mat) and bool(mat.get_meta(META_NP_WRAP, false))


static func _is_mat_ov_ours(mat: Material) -> bool:
	return mat != null and is_instance_valid(mat) and mat.has_meta(META_MAT_OV_OURS)


static func _make_override_material(gi: GeometryInstance3D, look: String) -> Material:
	match look:
		"Normal":
			return _make_viz_material(gi)
		"White cladding", "Chrome", "Gold", "Shiny black":
			return _pbr_look_material(look)
		_:
			return null


static func _pbr_look_material(look: String) -> StandardMaterial3D:
	var m: StandardMaterial3D
	if _mat_ov_pbr.has(look) and _mat_ov_pbr[look] is StandardMaterial3D and is_instance_valid(_mat_ov_pbr[look]):
		m = _mat_ov_pbr[look] as StandardMaterial3D
	else:
		m = StandardMaterial3D.new()
		m.set_meta(META_MAT_OV_OURS, true)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		m.vertex_color_use_as_albedo = false
		_mat_ov_pbr[look] = m
	m.albedo_texture = null
	m.roughness_texture = null
	m.emission_enabled = false
	m.emission = Color.BLACK
	m.emission_energy_multiplier = 0.0
	m.emission_texture = null
	m.normal_enabled = false
	m.ao_enabled = false
	m.rim_enabled = false
	m.clearcoat_enabled = false
	m.anisotropy_enabled = false
	m.heightmap_enabled = false
	m.subsurf_scatter_enabled = false
	m.backlight_enabled = false
	m.refraction_enabled = false
	m.detail_enabled = false
	match look:
		"White cladding":
			# Dielectric, not a light. Keep off-white so HDRI + ACES does not bloom to strobes.
			m.albedo_color = Color(0.88, 0.89, 0.90)
			m.metallic = 0.0
			m.roughness = 0.48
			m.metallic_specular = 0.35
			m.metallic_texture = null
		"Chrome":
			# F0 near-white metal. Dummy MR tex keeps metallic=1 if nonlinear wrap copies this.
			m.albedo_color = Color(0.86, 0.87, 0.89)
			m.metallic = 1.0
			m.roughness = 0.08
			m.metallic_specular = 1.0
			m.metallic_texture = _metal_factor_tex()
		"Gold":
			m.albedo_color = Color(1.0, 0.766, 0.336)
			m.metallic = 1.0
			m.roughness = 0.18
			m.metallic_specular = 1.0
			m.metallic_texture = _metal_factor_tex()
		"Shiny black":
			# Dark grey F0 + moderate roughness: HDRI shows, fewer fireflies than mirror-black.
			m.albedo_color = Color(0.07, 0.07, 0.075)
			m.metallic = 1.0
			m.roughness = 0.22
			m.metallic_specular = 1.0
			m.metallic_texture = _metal_factor_tex()
	return m


static func _metal_factor_tex() -> Texture2D:
	## 1×1 white so NP wrap treats the look as having an MR map and keeps metallic=1.
	## Without it, wrap zeroes metallic (glTF chrome-wash guard) and chrome reads as white plastic.
	if _mat_ov_metal_tex != null and is_instance_valid(_mat_ov_metal_tex):
		return _mat_ov_metal_tex
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(1, 1, 1, 1))
	_mat_ov_metal_tex = ImageTexture.create_from_image(img)
	return _mat_ov_metal_tex


static func _make_viz_material(gi: GeometryInstance3D) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.set_meta(META_MAT_OV_OURS, true)
	sm.shader = MAT_OVERRIDE_VIZ_SHADER
	var ntex: Texture = _extract_normal_tex(gi)
	sm.set_shader_parameter("normal_tex", ntex)
	sm.set_shader_parameter("has_normal_tex", 1 if ntex != null else 0)
	return sm


static func _source_material(gi: GeometryInstance3D) -> Material:
	if gi.has_meta(META_MAT_OV):
		var backup: Variant = gi.get_meta(META_MAT_OV)
		if backup is Material and not _is_mat_ov_ours(backup as Material):
			return backup as Material
	if gi.material_override != null and not _is_mat_ov_ours(gi.material_override):
		return gi.material_override
	if gi is MeshInstance3D:
		var mi := gi as MeshInstance3D
		var active := mi.get_active_material(0)
		if active != null:
			return active
	elif gi is MultiMeshInstance3D:
		var mmi := gi as MultiMeshInstance3D
		if mmi.multimesh and mmi.multimesh.mesh and mmi.multimesh.mesh.get_surface_count() > 0:
			var mm_mat := mmi.multimesh.mesh.surface_get_material(0)
			if mm_mat != null:
				return mm_mat
	return null


static func _extract_normal_tex(gi: GeometryInstance3D) -> Texture:
	var src := _source_material(gi)
	if src is BaseMaterial3D:
		var bm := src as BaseMaterial3D
		if bm.normal_enabled and bm.normal_texture != null:
			return bm.normal_texture
	if src is ShaderMaterial:
		var sm := src as ShaderMaterial
		var flag: Variant = sm.get_shader_parameter("np_use_normal_tex")
		var tex: Variant = sm.get_shader_parameter("np_normal_tex")
		if tex is Texture and (flag == null or float(flag) > 0.5):
			return tex as Texture
	if gi is MeshInstance3D:
		var mi := gi as MeshInstance3D
		var surf := mi.get_active_material(0)
		if surf is BaseMaterial3D and (surf as BaseMaterial3D).normal_texture != null:
			return (surf as BaseMaterial3D).normal_texture
	return null
