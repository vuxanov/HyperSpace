extends Node3D
class_name FlythroughMediaProp

## Reusable 3D media screen — still image, GIF, or looping video on a quad.


const DEFAULT_HEIGHT := 1.0
const VIDEO_VIEW_SIZE := Vector2i(1280, 720)

var _mesh_inst: MeshInstance3D
var _viewport: SubViewport
var _player: VideoStreamPlayer
var _mat: StandardMaterial3D
var _loop: bool = true
var _source_path: String = ""
var _play_path: String = ""


static func spawn(parent: Node3D, path: String, opts: Dictionary = {}) -> Node3D:
	if parent == null or path.strip_edges().is_empty():
		return null
	var script: GDScript = load("res://items/flythrough/media_prop.gd") as GDScript
	if script == null:
		return null
	var prop: Node3D = script.new() as Node3D
	prop.name = "MediaProp_%s" % path.get_file().get_basename()
	parent.add_child(prop)
	if prop.has_method("setup"):
		prop.call("setup", path, opts)
	return prop


func setup(path: String, opts: Dictionary = {}) -> void:
	_source_path = path
	_loop = bool(opts.get("loop", true))
	var billboard := bool(opts.get("billboard", false))
	var height := float(opts.get("height", DEFAULT_HEIGHT))
	_ensure_mesh(height, billboard)
	var media_type := MediaImport.detect_type(path)
	if media_type.is_empty():
		push_warning("FlythroughMediaProp: unsupported media %s" % path)
		return
	_play_path = MediaImport.prepare_path(path, media_type)
	var play_ext := _play_path.get_extension().to_lower()
	if media_type == "video" or play_ext in ["ogv", "webm", "mp4", "mov", "avi"]:
		if not _try_bind_video(_play_path):
			_try_bind_still(_play_path if media_type != "gif" else path)
	elif media_type == "gif":
		if play_ext in ["ogv", "webm", "mp4"] and _try_bind_video(_play_path):
			pass
		else:
			_try_bind_still(path)
	else:
		_try_bind_still(_play_path)


func get_shared_material() -> StandardMaterial3D:
	return _mat


func get_quad_mesh() -> Mesh:
	if _mesh_inst:
		return _mesh_inst.mesh
	return null


func make_mesh_clone(parent: Node3D) -> MeshInstance3D:
	## Scatter-friendly clone sharing the same animated / still material.
	if parent == null or _mesh_inst == null or _mat == null:
		return null
	var clone := MeshInstance3D.new()
	clone.mesh = _mesh_inst.mesh
	clone.material_override = _mat
	clone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(clone)
	return clone


func _ensure_mesh(height: float, billboard: bool) -> void:
	if _mesh_inst != null:
		return
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if billboard:
		_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(height * (16.0 / 9.0), height)
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = quad
	_mesh_inst.material_override = _mat
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_inst)


func _set_albedo(tex: Texture2D, aspect: float = -1.0) -> void:
	if _mat == null or tex == null:
		return
	_mat.albedo_texture = tex
	_mat.albedo_color = Color.WHITE
	if aspect > 0.01 and _mesh_inst and _mesh_inst.mesh is QuadMesh:
		var q := _mesh_inst.mesh as QuadMesh
		var h := q.size.y
		q.size = Vector2(h * aspect, h)


func _try_bind_still(path: String) -> bool:
	var tex := MediaImport.load_texture(path)
	if tex == null:
		push_warning("FlythroughMediaProp: could not load image %s" % path)
		return false
	var aspect := 16.0 / 9.0
	var sz := tex.get_size()
	if sz.y > 0.0:
		aspect = sz.x / sz.y
	_set_albedo(tex, aspect)
	return true


func _try_bind_video(path: String) -> bool:
	var stream := MediaImport.load_video_stream(path)
	if stream == null:
		return false
	if _viewport == null:
		_viewport = SubViewport.new()
		_viewport.name = "MediaViewport"
		_viewport.size = VIDEO_VIEW_SIZE
		_viewport.disable_3d = true
		_viewport.transparent_bg = true
		_viewport.handle_input_locally = false
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(_viewport)
	if _player == null:
		_player = VideoStreamPlayer.new()
		_player.name = "VideoPlayer"
		_player.expand = true
		_player.size = Vector2(VIDEO_VIEW_SIZE)
		_player.autoplay = false
		_player.finished.connect(_on_video_finished)
		_viewport.add_child(_player)
	_player.stream = stream
	_player.play()
	_set_albedo(_viewport.get_texture(), 16.0 / 9.0)
	return true


func _on_video_finished() -> void:
	if _loop and _player != null and _player.stream != null:
		_player.play()


func _exit_tree() -> void:
	if _player != null:
		_player.stop()
