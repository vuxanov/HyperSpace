extends RefCounted
class_name SceneMeshFx

## Shared 3D mesh FX helpers: fake point-cloud overlays, camera DOF/lens, SoftBody wrap.
## Used by Scene3DItem / FlythroughEnvironment so effects can "affect everything".

const SOFTBODY_VERT_LIMIT := 1600
const SOFTBODY_MAX_PLANE := 8.0
const POINT_MESH_LIMIT := 512
const POINT_VERT_LIMIT := 24000
## UV grid for a single image/GIF/video plane (scatter keeps source verts).
const MEDIA_POINT_GRID := 80
## Camera cull bit used to hide originals while the overlay child stays on layer 1.
const PC_HIDE_LAYER_BIT := 19
## Cached PRIMITIVE_POINTS meshes keyed by source Mesh instance_id (shared by scatter clones).
static var _pc_mesh_cache: Dictionary = {}
## ArrayMeshes after tangent generation (imported GLBs can still lack ARRAY_TANGENT).
static var _tangent_mesh_cache: Dictionary = {}

const META_PC := "hs_pc_overlay"
const META_PC_LAYERS := "hs_pc_layers"
const META_PC_SHADOW := "hs_pc_shadow"
const META_PC_CULL := "hs_pc_cull"
const META_CAM := "hs_cam_fx_backup"
const META_SOFT := "hs_softbody"
const META_SOFT_SRC := "hs_softbody_src"
const POINT_DEFORM_SHADER: Shader = preload("res://effects/point_cloud.gdshader")


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


static func fov_from_focal_mm(focal_mm: float) -> float:
	## Horizontal FOV for a 36mm full-frame sensor. Godot Camera3D.fov is 1..179.
	var f := clampf(focal_mm, 0.5, 4000.0)
	var fov := rad_to_deg(2.0 * atan(36.0 / (2.0 * maxf(f, 0.5))))
	return clampf(fov, 1.0, 179.0)


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
	var focus := float(params.get("focus_distance", 8.0))
	var bokeh := clampf(float(params.get("bokeh", 0.55)), 0.0, 1.5)
	var dof_extra := clampf(float(params.get("dof_amount", 0.0)), 0.0, 1.0)
	var lens := clampf(float(params.get("lens_distortion", 0.0)), 0.0, 1.0)
	var attr := CameraAttributesPractical.new()
	attr.dof_blur_far_enabled = bool(params.get("far_enabled", true))
	attr.dof_blur_near_enabled = bool(params.get("near_enabled", true))
	attr.dof_blur_far_distance = maxf(focus, 0.4)
	attr.dof_blur_near_distance = clampf(focus * 0.22, 0.15, maxf(focus - 0.2, 0.2))
	attr.dof_blur_far_transition = maxf(focus * 0.85, 1.0)
	attr.dof_blur_near_transition = maxf(focus * 0.28, 0.2)
	# Lower f-stop → more blur. Bokeh slider is an extra multiplier.
	var fstop := maxf(aperture, 0.7)
	var blur := clampf((1.0 / fstop) * 1.85 * bokeh + dof_extra * 0.55, 0.0, 1.0)
	attr.dof_blur_amount = blur
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
	include_media: bool = true
) -> Array:
	## Build overlays once per mesh (cached ArrayMesh). Returns overlay nodes for size-only updates.
	## Image/GIF/video screens use the same overlay path when include_media is true.
	if world == null:
		return []
	if not on:
		clear_point_cloud(world)
		return []
	# Hide originals from the camera; overlay children stay on layer 1 and still deform.
	_ensure_pc_camera_cull(find_camera(world))
	var overlays: Array = []
	var active: Dictionary = {}
	for root_any in layer_roots:
		if not is_live(root_any) or not (root_any is Node):
			continue
		var batch: Array = []
		collect_meshes(root_any as Node, batch, true, not include_media)
		_overlay_batch(batch, point_size, overlays, active)
	_prune_point_overlays(world, active)
	return overlays


static func _overlay_batch(meshes: Array, point_size: float, overlays: Array, active: Dictionary) -> void:
	var limit := mini(meshes.size(), POINT_MESH_LIMIT)
	for i in limit:
		var mi_any: Variant = meshes[i]
		if not is_live(mi_any) or not (mi_any is MeshInstance3D):
			continue
		var mi := mi_any as MeshInstance3D
		if mi.mesh == null:
			continue
		if bool(mi.get_meta("hs_softbody_src", false)):
			continue
		if active.has(mi.get_instance_id()):
			continue
		var overlay: MeshInstance3D = _ensure_point_overlay(mi, point_size)
		if overlay != null:
			overlays.append(overlay)
			active[mi.get_instance_id()] = true


static func update_overlay_point_size(overlays: Array, point_size: float) -> bool:
	## Updates point size on live overlays. Prunes freed/invalid refs in-place.
	## Returns true if any entries were removed (caller should rebuild).
	var sz := maxf(point_size, 1.0)
	var pruned := false
	var i := 0
	while i < overlays.size():
		var ov_any: Variant = overlays[i]
		if not is_live(ov_any) or not (ov_any is MeshInstance3D):
			overlays.remove_at(i)
			pruned = true
			continue
		var ov := ov_any as MeshInstance3D
		var parent := ov.get_parent()
		if is_live(parent) and parent is MeshInstance3D:
			_hide_original_pc_layers(parent as MeshInstance3D)
		var mat: Material = ov.material_override
		if mat is BaseMaterial3D:
			var bm := mat as BaseMaterial3D
			bm.use_point_size = true
			bm.point_size = sz
		elif mat is ShaderMaterial:
			set_shader_param(mat as ShaderMaterial, "point_size", sz)
		i += 1
	return pruned


static func clear_point_cloud(root: Node) -> void:
	if not is_live(root):
		return
	var camera: Camera3D = find_camera(root)
	_restore_pc_camera_cull(camera)
	var meshes: Array = []
	collect_meshes(root, meshes, false)
	for mi_any in meshes:
		if is_live(mi_any) and mi_any is MeshInstance3D:
			_restore_point_overlay(mi_any as MeshInstance3D)


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


static func _ensure_point_overlay(mi: MeshInstance3D, point_size: float) -> MeshInstance3D:
	var overlay: MeshInstance3D = null
	var media := is_media_instance(mi)
	if mi.has_meta(META_PC):
		var existing: Variant = mi.get_meta(META_PC)
		if is_live(existing) and existing is MeshInstance3D:
			overlay = existing as MeshInstance3D
	if overlay != null and (not overlay.has_meta("hs_pc_vcol") or (media and not overlay.has_meta("hs_pc_live_tex"))):
		overlay.queue_free()
		overlay = null
		mi.remove_meta(META_PC)
	if overlay == null:
		var points: ArrayMesh = _mesh_to_points(mi)
		if points == null:
			return null
		overlay = MeshInstance3D.new()
		overlay.name = "HSPointCloud"
		overlay.mesh = points
		overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		overlay.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		overlay.extra_cull_margin = 2.0
		overlay.layers = 1
		overlay.set_meta("hs_pc_vcol", true)
		overlay.material_override = make_point_deform_material(point_size)
		if media:
			overlay.set_meta("hs_pc_live_tex", true)
		mi.add_child(overlay)
		mi.set_meta(META_PC, overlay)
		_hide_original_pc_layers(mi)
		if media:
			bind_overlay_live_texture(overlay, mi)
	else:
		overlay.layers = 1
		_hide_original_pc_layers(mi)
		ensure_point_deform_material(overlay, point_size)
		update_overlay_point_size([overlay], point_size)
		if media:
			var want: ArrayMesh = _mesh_to_points(mi)
			if want != null and overlay.mesh != want:
				overlay.mesh = want
			bind_overlay_live_texture(overlay, mi)
	return overlay


static func _hide_original_pc_layers(mi: MeshInstance3D) -> void:
	## Cull-hide the shaded surface. Keep Node.visible so the overlay child still draws
	## and noise/cloth uniforms still stamp on the same instance.
	if mi == null or not is_instance_valid(mi):
		return
	if not mi.has_meta(META_PC_LAYERS):
		mi.set_meta(META_PC_LAYERS, mi.layers)
	if not mi.has_meta(META_PC_SHADOW):
		mi.set_meta(META_PC_SHADOW, mi.cast_shadow)
	mi.layers = 1 << PC_HIDE_LAYER_BIT
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _restore_original_pc_layers(mi: MeshInstance3D) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	if mi.has_meta(META_PC_LAYERS):
		mi.layers = int(mi.get_meta(META_PC_LAYERS))
		mi.remove_meta(META_PC_LAYERS)
	if mi.has_meta(META_PC_SHADOW):
		mi.cast_shadow = int(mi.get_meta(META_PC_SHADOW))
		mi.remove_meta(META_PC_SHADOW)


static func _restore_point_overlay(mi: MeshInstance3D) -> void:
	if mi.has_meta(META_PC):
		var existing: Variant = mi.get_meta(META_PC)
		if is_live(existing) and existing is Node:
			(existing as Node).queue_free()
		mi.remove_meta(META_PC)
	_restore_original_pc_layers(mi)


static func _prune_point_overlays(root: Node, active: Dictionary) -> void:
	var meshes: Array = []
	collect_meshes(root, meshes, false)
	for mi_any in meshes:
		if not is_live(mi_any) or not (mi_any is MeshInstance3D):
			continue
		var mi := mi_any as MeshInstance3D
		if mi.has_meta(META_PC) and not active.has(mi.get_instance_id()):
			_restore_point_overlay(mi)


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
	var key := "%d_%d_%s" % [mesh.get_instance_id(), tex_id, "live" if live_tex else "n"]
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
		out.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, packed)
	if out.get_surface_count() <= 0:
		return null
	if _pc_mesh_cache.size() > 256:
		_pc_mesh_cache.clear()
	_pc_mesh_cache[key] = out
	return out


static func _surface_arrays(mesh: Mesh, surface: int) -> Array:
	var arrays: Array = mesh.surface_get_arrays(surface)
	if _arrays_have_verts(arrays):
		return arrays
	## Compressed importer meshes often return empty arrays — SurfaceTool decompresses.
	var st := SurfaceTool.new()
	st.create_from(mesh, surface)
	var baked: ArrayMesh = st.commit()
	if baked != null and baked.get_surface_count() > 0:
		arrays = baked.surface_get_arrays(0)
		if _arrays_have_verts(arrays):
			return arrays
	var faces: PackedVector3Array = mesh.get_faces()
	if faces.is_empty():
		return []
	var packed: Array = []
	packed.resize(Mesh.ARRAY_MAX)
	packed[Mesh.ARRAY_VERTEX] = faces
	return packed


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
		sm.set_shader_parameter("albedo", tint)
		sm.set_shader_parameter("exposure_comp", exposure)
	else:
		sm.set_shader_parameter("has_tex", 0.0)


static func _media_grid_points(mi: MeshInstance3D) -> ArrayMesh:
	## Denser UV lattice than the deform grid so a still/GIF reads as a point image.
	var size := Vector2(1.6, 1.0)
	if mi.mesh is PlaneMesh:
		size = (mi.mesh as PlaneMesh).size
	var n := maxi(MEDIA_POINT_GRID, 8)
	var key := "media_grid_%.4f_%.4f_%d" % [size.x, size.y, n]
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
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, packed)
	if _pc_mesh_cache.size() > 256:
		_pc_mesh_cache.clear()
	_pc_mesh_cache[key] = out
	return out


static func _albedo_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8)
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


static func make_point_deform_material(point_size: float) -> ShaderMaterial:
	## Unshaded points + the same noise/cloth vertex displace as noise_deform.gdshader.
	var sm := ShaderMaterial.new()
	sm.shader = POINT_DEFORM_SHADER
	if not shader_usable(sm):
		return sm
	sm.set_shader_parameter("albedo", Color.WHITE)
	sm.set_shader_parameter("has_tex", 0.0)
	sm.set_shader_parameter("point_size", maxf(point_size, 1.0))
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
		set_shader_param(mat as ShaderMaterial, "point_size", maxf(point_size, 1.0))
		return mat as ShaderMaterial
	var sm := make_point_deform_material(point_size)
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
