extends RefCounted
class_name FlythroughLayerSlot

## Loads a file or primitive into a layer root.

const LAYER_ENVIRONMENT := "environment"
const LAYER_SCATTER := "scatter"
const LAYER_CENTERPIECE := "centerpiece"
const _MEDIA_PROP := preload("res://items/flythrough/media_prop.gd")
const _AssetCache := preload("res://core/asset_cache.gd")
const _SceneMeshFx := preload("res://core/scene_mesh_fx.gd")


static func clear_root(root: Node3D) -> void:
	if root == null:
		return
	for child in root.get_children():
		child.queue_free()


static func load_asset_into(parent: Node3D, path: String, opts: Dictionary = {}) -> Node3D:
	## Instantiates from AssetCache when possible (sync only on cold miss).
	if path.is_empty() or parent == null:
		return null
	var resolved := _resolve_res_path(path)
	if is_media_path(resolved):
		var role := str(opts.get("role", ""))
		var billboard := bool(opts.get("billboard", role != "environment"))
		var media_opts := {
			"billboard": billboard,
			"loop": bool(opts.get("loop", true)),
			"height": float(opts.get("height", 1.0)),
		}
		return _MEDIA_PROP.spawn(parent, resolved, media_opts)
	# Cached / threaded-loaded PackedScene.
	var cached: PackedScene = _AssetCache.get_scene(resolved)
	if cached != null:
		var inst: Node = cached.instantiate()
		parent.add_child(inst)
		_SceneMeshFx.ensure_mesh_tangents(inst)
		_SceneMeshFx.disable_nested_cameras(inst)
		if inst is Node3D:
			return inst as Node3D
		inst.queue_free()
	# Prefer Godot-imported PackedScene (glb/gltf/fbx) — also seeds cache.
	if ResourceLoader.exists(resolved):
		var packed := _AssetCache.peek_or_load_scene_sync(resolved)
		if packed != null:
			var instance: Node = packed.instantiate()
			parent.add_child(instance)
			_SceneMeshFx.ensure_mesh_tangents(instance)
			_SceneMeshFx.disable_nested_cameras(instance)
			if instance is Node3D:
				return instance as Node3D
			instance.queue_free()
	# Runtime GLTF/GLB parse (also works with absolute paths) — seeds cache.
	var abs_path := resolved
	if resolved.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(resolved)
	var lower := abs_path.to_lower()
	if (lower.ends_with(".glb") or lower.ends_with(".gltf")) and FileAccess.file_exists(abs_path):
		var packed2 := _AssetCache.peek_or_load_scene_sync(resolved)
		if packed2 != null:
			var scene: Node = packed2.instantiate()
			parent.add_child(scene)
			_SceneMeshFx.ensure_mesh_tangents(scene)
			_SceneMeshFx.disable_nested_cameras(scene)
			if scene is Node3D:
				return scene as Node3D
			scene.queue_free()
	push_warning("FlythroughLayerSlot: could not load %s" % path)
	return null


static func _resolve_res_path(path: String) -> String:
	var normalized := path.replace("\\", "/")
	if normalized.begins_with("res://") or normalized.begins_with("user://"):
		return normalized
	var project_root := ProjectSettings.globalize_path("res://").replace("\\", "/")
	if normalized.begins_with(project_root):
		return "res://" + normalized.substr(project_root.length()).lstrip("/")
	return normalized


static func resolve_source_string(config: Dictionary) -> String:
	if config.has("path") and str(config["path"]).strip_edges() != "":
		return str(config["path"])
	if config.has("source"):
		return str(config["source"])
	return ""


static func is_model_path(source: String) -> bool:
	var lower := source.to_lower()
	return lower.ends_with(".glb") or lower.ends_with(".gltf") or lower.ends_with(".fbx") \
		or lower.ends_with(".tscn")


static func is_media_path(source: String) -> bool:
	return MediaImport.is_media_extension(source)


static func is_file_path(source: String) -> bool:
	## Model or media file that can be spawned into a layer root.
	return is_model_path(source) or is_media_path(source)


static func is_primitive_source(source: String) -> bool:
	if source.begins_with("primitive:"):
		return true
	return source in [
		"box_corridor", "flat_plane", "cubes", "spheres", "torus", "icosphere",
		"hterrain_hills", "hterrain_mountains", "hterrain_canyon", "hills", "mountains", "canyon"
	]


static func normalize_primitive(source: String) -> String:
	if source.begins_with("primitive:"):
		return source.substr("primitive:".length())
	return source


static func fit_node_to_size(node: Node3D, target_max_dim: float) -> Vector3:
	if node == null or target_max_dim <= 0.001:
		return Vector3.ONE
	var aabb := compute_aabb(node)
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if longest <= 0.001:
		return node.scale
	var factor := target_max_dim / longest
	node.scale = node.scale * factor
	return node.scale


static func compute_aabb(root: Node3D, skip_meta: String = "") -> AABB:
	var pack: Array = [AABB(), true]
	_accum_aabb(root, Transform3D.IDENTITY, pack, skip_meta)
	if pack[1]:
		return AABB(Vector3(-2, -2, -30), Vector3(4, 4, 60))
	return pack[0]


static func _accum_aabb(node: Node, parent_xf: Transform3D, pack: Array, skip_meta: String = "") -> void:
	if skip_meta != "" and node.has_meta(skip_meta):
		return
	var local_xf := parent_xf
	if node is Node3D:
		local_xf = parent_xf * (node as Node3D).transform
	if node is VisualInstance3D:
		var vi := node as VisualInstance3D
		var local_aabb := vi.get_aabb()
		var corners: Array[Vector3] = [
			local_xf * local_aabb.position,
			local_xf * (local_aabb.position + Vector3(local_aabb.size.x, 0, 0)),
			local_xf * (local_aabb.position + Vector3(0, local_aabb.size.y, 0)),
			local_xf * (local_aabb.position + Vector3(0, 0, local_aabb.size.z)),
			local_xf * (local_aabb.position + Vector3(local_aabb.size.x, local_aabb.size.y, 0)),
			local_xf * (local_aabb.position + Vector3(local_aabb.size.x, 0, local_aabb.size.z)),
			local_xf * (local_aabb.position + Vector3(0, local_aabb.size.y, local_aabb.size.z)),
			local_xf * (local_aabb.position + local_aabb.size),
		]
		for c in corners:
			if pack[1]:
				pack[0] = AABB(c, Vector3.ZERO)
				pack[1] = false
			else:
				pack[0] = (pack[0] as AABB).expand(c)
	for child in node.get_children():
		_accum_aabb(child, local_xf, pack, skip_meta)


static func make_visual_tile_copy(source: Node3D, tile_name: String) -> Node3D:
	## Duplicate mesh only for the environment grid (corners included). No extra lights / WorldEnvironment.
	if source == null:
		return null
	var copy := source.duplicate() as Node3D
	if copy == null:
		return null
	copy.name = tile_name
	if copy.has_meta("hs_env_primary"):
		copy.remove_meta("hs_env_primary")
	copy.set_meta("hs_env_tile", true)
	strip_nested_lighting(copy)
	_SceneMeshFx.disable_nested_cameras(copy)
	return copy


static func strip_nested_lighting(root: Node) -> void:
	## Drop WorldEnvironment / lights from tiled copies so HDRI and stage lighting stay single.
	if root == null:
		return
	var doomed: Array[Node] = []
	_collect_nested_lighting(root, doomed)
	for n in doomed:
		if not is_instance_valid(n):
			continue
		var p := n.get_parent()
		if p:
			p.remove_child(n)
		n.free()


static func _collect_nested_lighting(node: Node, out: Array[Node]) -> void:
	if node is WorldEnvironment or node is Light3D or node is VoxelGI or node is LightmapGI:
		out.append(node)
		return
	if node is Camera3D:
		(node as Camera3D).current = false
	for child in node.get_children():
		_collect_nested_lighting(child, out)
