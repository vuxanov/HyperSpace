extends Node3D
class_name FlythroughMediaProp

## Reusable 3D media screen — still image, GIF, or looping video on a quad.
## Uses preloaded emission shader (hint_default_black) so unbound samples are never white.
## Video frames come from MediaVideoPool (shared decode + throttled ImageTexture blit).
## GIF frames cycle manually into ImageTexture (AnimatedTexture does not animate as a shader uniform).


const DEFAULT_HEIGHT := 1.0
## Grid density so noise deform / cloth have vertices to move (QuadMesh is 2 tris).
const GRID_SUBDIV := 32
## Dim LDR so ACES does not blow screen content.
const EXPOSURE_COMP := 0.72
const FALLBACK_CHARCOAL := Color(0.08, 0.08, 0.1)
const FALLBACK_ERROR := Color(0.42, 0.08, 0.1)
## Soft cap GIF frame rate when source delays are tiny.
const GIF_MIN_FRAME_DUR := 0.04

const _MEDIA_SHADER: Shader = preload("res://effects/media_screen.gdshader")
const _VideoPool = preload("res://core/media_video_pool.gd")

var _mesh_inst: MeshInstance3D
var _soft: SoftBody3D
var _cloth_wind: Vector3 = Vector3.ZERO
var _mat: ShaderMaterial
var _loop: bool = true
var _source_path: String = ""
var _play_path: String = ""
var _video_pool_key: String = ""
var _billboard: bool = false
var _needs_video_process: bool = false
var _bound_tex: Texture2D = null
var _bound_aspect: float = 16.0 / 9.0
var _use_error_fallback: bool = false

## Manual GIF animation (shader-safe). Shared ImageTextures from MediaImport cache.
var _gif_frames: Array[ImageTexture] = []
var _gif_durations: Array[float] = []
var _gif_index: int = 0
var _gif_elapsed: float = 0.0
var _gif_bound_index: int = -1
var _needs_gif_process: bool = false
var _pending_gif_path: String = ""


static func spawn(parent: Node3D, path: String, opts: Dictionary = {}) -> Node3D:
	if parent == null or path.strip_edges().is_empty():
		return null
	var prop := FlythroughMediaProp.new()
	prop.name = "MediaProp_%s" % path.get_file().get_basename()
	parent.add_child(prop)
	prop.setup(path, opts)
	return prop


func setup(path: String, opts: Dictionary = {}) -> void:
	_source_path = path
	_loop = bool(opts.get("loop", true))
	_billboard = bool(opts.get("billboard", false))
	var height := float(opts.get("height", DEFAULT_HEIGHT))
	_ensure_mesh(height, _billboard)
	_show_fallback(false)
	_release_video()
	_gif_frames.clear()
	_gif_durations.clear()
	_needs_gif_process = false
	_needs_video_process = false
	_gif_bound_index = -1
	_pending_gif_path = ""
	var media_type := MediaImport.detect_type(path)
	if media_type.is_empty():
		push_warning("FlythroughMediaProp: unsupported media %s" % path)
		_show_fallback(true)
		return
	# Non-blocking prepare: use cached ogv if present; never sync-ffmpeg here.
	_play_path = MediaImport.prepare_path(path, media_type)
	# GIFs: only bind from cache — never sync-decode on apply (precache warms them).
	if media_type == "gif":
		if MediaImport.gif_cached(path):
			_bind_media(path, media_type)
		else:
			_show_fallback(false)
			_pending_gif_path = path
			set_process(true)
		return
	_bind_media(path, media_type)


func _bind_media_deferred(path: String, media_type: String) -> void:
	if not is_inside_tree() or path != _source_path:
		return
	_bind_media(path, media_type)


func _bind_media(path: String, media_type: String) -> void:
	var play_ext := _play_path.get_extension().to_lower()
	var ok := false
	if media_type == "video" or play_ext in ["ogv", "webm", "mp4", "mov", "avi"]:
		ok = _try_bind_video(_play_path)
		if not ok and media_type == "gif":
			ok = _try_bind_gif_frames(path)
		if not ok:
			ok = _try_bind_still(_play_path if media_type != "gif" else path)
	elif media_type == "gif":
		# Native frame cycling is reliable without ffmpeg; ogv is optional.
		ok = _try_bind_gif_frames(path)
		if not ok and play_ext in ["ogv", "webm", "mp4"]:
			ok = _try_bind_video(_play_path)
		if not ok:
			ok = _try_bind_still(path)
	else:
		ok = _try_bind_still(_play_path)
	if not ok:
		push_warning("FlythroughMediaProp: failed to bind media %s" % path)
		_show_fallback(true)
	else:
		# Re-apply after the mesh is fully in the Scene3D SubViewport tree.
		call_deferred("_rebind_texture")


func get_shared_material() -> Material:
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
	clone.set_meta("media_screen", true)
	clone.rotation = _mesh_inst.rotation
	parent.add_child(clone)
	return clone


func _ensure_mesh(height: float, billboard: bool) -> void:
	if _mesh_inst != null:
		return
	_mat = ShaderMaterial.new()
	_mat.shader = _MEDIA_SHADER
	_mat.set_shader_parameter("exposure_comp", EXPOSURE_COMP)
	_mat.set_shader_parameter("modulate", Color(1, 1, 1, 1))
	_mat.set_shader_parameter("has_tex", 0.0)
	_mat.set_shader_parameter("use_billboard", 1.0 if billboard else 0.0)
	_mat.set_shader_parameter("fallback_rgb", Vector3(FALLBACK_CHARCOAL.r, FALLBACK_CHARCOAL.g, FALLBACK_CHARCOAL.b))
	_mat.set_shader_parameter("tex_albedo", null)
	_mat.set_shader_parameter("deform_amount", 0.0)
	_mat.set_shader_parameter("cloth_amount", 0.0)
	_mat.render_priority = 16
	var plane := _make_grid_mesh(Vector2(height * (16.0 / 9.0), height))
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = plane
	_mesh_inst.material_override = _mat
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mesh_inst.set_meta("media_screen", true)
	# Quad faces +Z; camera-matched parent looks along -Z — flip when not billboarded.
	if not billboard:
		_mesh_inst.rotation_degrees.y = 180.0
	add_child(_mesh_inst)


func _show_fallback(is_error: bool) -> void:
	_use_error_fallback = is_error
	_bound_tex = null
	if _mat == null:
		return
	var c := FALLBACK_ERROR if is_error else FALLBACK_CHARCOAL
	_mat.set_shader_parameter("has_tex", 0.0)
	_mat.set_shader_parameter("tex_albedo", null)
	_mat.set_shader_parameter("fallback_rgb", Vector3(c.r, c.g, c.b))
	_mat.set_shader_parameter("exposure_comp", 1.0 if is_error else EXPOSURE_COMP)
	_mat.set_shader_parameter("modulate", Color(1, 1, 1, 1))


func _set_screen_texture(tex: Texture2D, aspect: float = -1.0) -> void:
	if _mat == null or tex == null:
		return
	_bound_tex = tex
	_use_error_fallback = false
	if aspect > 0.01:
		_bound_aspect = aspect
	_mat.set_shader_parameter("tex_albedo", tex)
	_mat.set_shader_parameter("has_tex", 1.0)
	_mat.set_shader_parameter("exposure_comp", EXPOSURE_COMP)
	_mat.set_shader_parameter("modulate", Color(1, 1, 1, 1))
	_mat.set_shader_parameter("fallback_rgb", Vector3(FALLBACK_CHARCOAL.r, FALLBACK_CHARCOAL.g, FALLBACK_CHARCOAL.b))
	if _bound_aspect > 0.01:
		_set_plane_size(-1.0, -1.0)


func _rebind_texture() -> void:
	if _mat == null:
		return
	if _bound_tex != null:
		_set_screen_texture(_bound_tex, _bound_aspect)
	elif _use_error_fallback:
		_show_fallback(true)
	else:
		_show_fallback(false)


func _try_bind_still(path: String) -> bool:
	var tex := MediaImport.load_texture(path)
	if tex == null:
		push_warning("FlythroughMediaProp: could not load image %s" % path)
		return false
	var aspect := 16.0 / 9.0
	var sz := tex.get_size()
	if sz.y > 0.0:
		aspect = sz.x / sz.y
	_set_screen_texture(tex, aspect)
	return true


func _try_bind_gif_frames(path: String) -> bool:
	## Cache-only — never sync-decode on the apply/bind path (playlist warm fills cache).
	if not MediaImport.gif_cached(path):
		return false
	var anim := MediaImport.load_gif_animation(path)
	if not bool(anim.get("ok", false)):
		return false
	var frames: Array = anim.get("frames", [])
	var durs: Array = anim.get("durations", [])
	if frames.is_empty():
		return false
	_gif_frames.clear()
	_gif_durations.clear()
	for i in frames.size():
		if frames[i] is ImageTexture:
			_gif_frames.append(frames[i] as ImageTexture)
			_gif_durations.append(float(durs[i]) if i < durs.size() else 0.08)
	if _gif_frames.is_empty():
		return false
	_gif_index = 0
	_gif_elapsed = 0.0
	_gif_bound_index = -1
	var first := _gif_frames[0]
	var aspect := 16.0 / 9.0
	var sz := first.get_size()
	if sz.y > 0.0:
		aspect = sz.x / sz.y
	_set_screen_texture(first, aspect)
	_gif_bound_index = 0
	if _gif_frames.size() > 1:
		_needs_gif_process = true
		set_process(true)
	return true


func _try_bind_gif(path: String) -> bool:
	return _try_bind_gif_frames(path)


func _try_bind_video(path: String) -> bool:
	var stream := MediaImport.load_video_stream(path)
	if stream == null:
		return false
	var got: Dictionary = _VideoPool.acquire(path, stream, _loop)
	if not bool(got.get("ok", false)):
		return false
	_video_pool_key = str(got.get("key", path))
	var frame_tex: ImageTexture = got.get("frame_tex") as ImageTexture
	if frame_tex == null:
		_VideoPool.release(_video_pool_key)
		_video_pool_key = ""
		return false
	var aspect := float(got.get("aspect", 16.0 / 9.0))
	_set_screen_texture(frame_tex, aspect)
	_needs_video_process = true
	set_process(true)
	return true


func _release_video() -> void:
	if not _video_pool_key.is_empty():
		_VideoPool.release(_video_pool_key)
		_video_pool_key = ""
	_needs_video_process = false


func _advance_gif(delta: float) -> void:
	if _gif_frames.size() <= 1:
		return
	_gif_elapsed += delta
	var dur := _gif_durations[_gif_index] if _gif_index < _gif_durations.size() else 0.08
	dur = maxf(dur, GIF_MIN_FRAME_DUR)
	var changed := false
	while _gif_elapsed >= dur:
		_gif_elapsed -= dur
		_gif_index = (_gif_index + 1) % _gif_frames.size()
		changed = true
		dur = _gif_durations[_gif_index] if _gif_index < _gif_durations.size() else 0.08
		dur = maxf(dur, GIF_MIN_FRAME_DUR)
	if changed and _gif_index != _gif_bound_index:
		_gif_bound_index = _gif_index
		# Shared material: only swap the texture uniform (clones already share _mat).
		_mat.set_shader_parameter("tex_albedo", _gif_frames[_gif_index])
		_bound_tex = _gif_frames[_gif_index]


func _process(delta: float) -> void:
	if not _pending_gif_path.is_empty():
		if MediaImport.gif_cached(_pending_gif_path):
			var p := _pending_gif_path
			_pending_gif_path = ""
			_bind_media(p, "gif")
		elif not _needs_gif_process and not _needs_video_process:
			# Keep process alive until warm finishes; charcoal stays visible.
			pass
	if _needs_gif_process:
		_advance_gif(delta)
	if _needs_video_process:
		_VideoPool.tick(delta)
		# Keep aspect in sync if the first real frame differs from seed.
		if not _video_pool_key.is_empty():
			var a := _VideoPool.aspect_for(_video_pool_key)
			if absf(a - _bound_aspect) > 0.01:
				_bound_aspect = a
				_set_plane_size(-1.0, -1.0)
	if not _needs_gif_process and not _needs_video_process and _pending_gif_path.is_empty():
		set_process(false)


func _make_grid_mesh(size: Vector2) -> PlaneMesh:
	var plane := PlaneMesh.new()
	plane.size = size
	plane.orientation = PlaneMesh.FACE_Z
	plane.subdivide_width = GRID_SUBDIV
	plane.subdivide_depth = GRID_SUBDIV
	return plane


func _current_plane_size() -> Vector2:
	if _mesh_inst and _mesh_inst.mesh is PlaneMesh:
		return (_mesh_inst.mesh as PlaneMesh).size
	return Vector2(DEFAULT_HEIGHT * 16.0 / 9.0, DEFAULT_HEIGHT)


func _set_plane_size(width: float, height: float) -> void:
	var cur := _current_plane_size()
	var h := height if height > 0.01 else cur.y
	var w := width if width > 0.01 else h * maxf(_bound_aspect, 0.1)
	var sz := Vector2(w, h)
	if _mesh_inst and _mesh_inst.mesh is PlaneMesh:
		(_mesh_inst.mesh as PlaneMesh).size = sz
	if _soft and is_instance_valid(_soft) and _soft.mesh is PlaneMesh:
		(_soft.mesh as PlaneMesh).size = sz


func set_deform_uniforms(params: Dictionary) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("deform_amount", float(params.get("deform_amount", 0.0)))
	_mat.set_shader_parameter("deform_scale", float(params.get("deform_scale", 1.0)))
	_mat.set_shader_parameter("deform_time", float(params.get("deform_time", 0.0)))
	_mat.set_shader_parameter("deform_axes", params.get("deform_axes", Vector3.ONE))
	_mat.set_shader_parameter("cloth_amount", float(params.get("cloth_amount", 0.0)))
	_mat.set_shader_parameter("cloth_stiffness", float(params.get("cloth_stiffness", 0.55)))
	_mat.set_shader_parameter("cloth_wind", float(params.get("cloth_wind", 0.0)))
	_mat.set_shader_parameter("cloth_time", float(params.get("cloth_time", 0.0)))


func has_active_softbody() -> bool:
	## Godot 4.7 SoftBody3D has no physics_enabled — presence of the node is the on-switch.
	return _soft != null and is_instance_valid(_soft)


func set_softbody_cloth(on: bool, stiffness: float, damping: float, wind: Vector3) -> void:
	## Real SoftBody on the tessellated grid. Billboard screens stay shader-only.
	_cloth_wind = wind
	if not on or _billboard:
		_teardown_softbody()
		return
	_ensure_softbody(stiffness, damping)
	if _soft and is_instance_valid(_soft):
		_soft.linear_stiffness = clampf(stiffness, 0.35, 1.0)
		_soft.damping_coefficient = clampf(maxf(damping, 0.18), 0.18, 1.0)
		_soft.drag_coefficient = 0.12 + clampf(damping, 0.0, 1.0) * 0.2
		_soft.process_mode = Node.PROCESS_MODE_INHERIT
	set_physics_process(true)


func _ensure_softbody(stiffness: float, damping: float) -> void:
	if _soft != null and is_instance_valid(_soft):
		return
	if _mesh_inst == null or _mesh_inst.mesh == null:
		return
	_soft = SoftBody3D.new()
	_soft.name = "MediaCloth"
	_soft.mesh = _mesh_inst.mesh.duplicate() if _mesh_inst.mesh else _mesh_inst.mesh
	_soft.material_override = _mat
	_soft.transform = _mesh_inst.transform
	_soft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_soft.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_soft.set_meta("media_screen", true)
	_soft.collision_layer = 0
	_soft.collision_mask = 0
	_soft.ray_pickable = false
	_soft.simulation_precision = 8
	_soft.total_mass = 1.4
	_soft.linear_stiffness = clampf(stiffness, 0.35, 1.0)
	_soft.damping_coefficient = clampf(maxf(damping, 0.18), 0.18, 1.0)
	_soft.drag_coefficient = 0.12 + clampf(damping, 0.0, 1.0) * 0.2
	_soft.pressure_coefficient = 0.0
	_soft.process_mode = Node.PROCESS_MODE_INHERIT
	add_child(_soft)
	SceneMeshFx.pin_top_edge(_soft)
	_mesh_inst.visible = false
	_mesh_inst.set_meta("hs_softbody_src", true)


func _teardown_softbody() -> void:
	set_physics_process(false)
	if _soft != null and is_instance_valid(_soft):
		_soft.queue_free()
	_soft = null
	if _mesh_inst and is_instance_valid(_mesh_inst):
		_mesh_inst.visible = true
		_mesh_inst.set_meta("hs_softbody_src", false)


func _physics_process(_delta: float) -> void:
	if _soft == null or not is_instance_valid(_soft):
		set_physics_process(false)
		return
	SceneMeshFx.apply_softbody_wind(_soft, _cloth_wind)


func _exit_tree() -> void:
	set_process(false)
	set_physics_process(false)
	_teardown_softbody()
	_needs_video_process = false
	_needs_gif_process = false
	_gif_frames.clear()
	_gif_durations.clear()
	_release_video()
	_bound_tex = null
