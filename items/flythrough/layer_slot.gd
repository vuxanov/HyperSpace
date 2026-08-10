extends RefCounted
class_name FlythroughLayerSlot

## Loads a file or primitive into a layer root.

const LAYER_ENVIRONMENT := "environment"
const LAYER_SCATTER := "scatter"
const LAYER_CENTERPIECE := "centerpiece"


static func clear_root(root: Node3D) -> void:
	if root == null:
		return
	for child in root.get_children():
		child.queue_free()


static func load_asset_into(parent: Node3D, path: String) -> Node3D:
	if path.is_empty() or parent == null:
		return null
	var resolved := _resolve_res_path(path)
	# Prefer Godot-imported PackedScene (glb/gltf/fbx).
	if ResourceLoader.exists(resolved):
		var res: Resource = load(resolved)
		if res is PackedScene:
			var instance: Node = (res as PackedScene).instantiate()
			parent.add_child(instance)
			if instance is Node3D:
				return instance as Node3D
			instance.queue_free()
	# Runtime GLTF/GLB parse (also works with absolute paths).
	var abs_path := resolved
	if resolved.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(resolved)
	var lower := abs_path.to_lower()
	if (lower.ends_with(".glb") or lower.ends_with(".gltf")) and FileAccess.file_exists(abs_path):
		var gltf := GLTFDocument.new()
		var state := GLTFState.new()
		var err := gltf.append_from_file(abs_path, state)
		if err == OK:
			var scene := gltf.generate_scene(state)
			parent.add_child(scene)
			if scene is Node3D:
				return scene as Node3D
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


static func is_file_path(source: String) -> bool:
	var lower := source.to_lower()
	return lower.ends_with(".glb") or lower.ends_with(".gltf") or lower.ends_with(".fbx") \
		or lower.ends_with(".tscn")


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


static func compute_aabb(root: Node3D) -> AABB:
	var pack: Array = [AABB(), true]
	_accum_aabb(root, Transform3D.IDENTITY, pack)
	if pack[1]:
		return AABB(Vector3(-2, -2, -30), Vector3(4, 4, 60))
	return pack[0]


static func _accum_aabb(node: Node, parent_xf: Transform3D, pack: Array) -> void:
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
		_accum_aabb(child, local_xf, pack)
