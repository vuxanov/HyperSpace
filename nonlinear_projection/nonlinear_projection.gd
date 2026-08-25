extends Node

## Autoload: camera-space nonlinear projection on the existing gameplay Camera3D.
## Enable from Effects → Nonlinear camera (optional F4). Disable restores original materials.

const WRAP_SHADER: Shader = preload("res://nonlinear_projection/nonlinear_projection_spatial.gdshader")
const NPSettings := preload("res://nonlinear_projection/nonlinear_projection_settings.gd")
const META_BACKUP := "np_mat_backup"
const META_CULL := "np_cull_backup"
const META_WRAP := "np_wrapped_mat"
const META_WRAP_VER := "np_wrap_ver"
const WRAP_VERSION := 8

var settings = NPSettings.new()

@export var enabled: bool = false:
	set(v):
		enabled = v
		settings.enabled = v
		_push_uniforms()
		if v:
			call_deferred("_scan_worlds")
		else:
			restore_all()

@export_range(0.0, 2.0, 0.01) var distortion_strength: float = 1.0:
	set(v):
		distortion_strength = v
		settings.distortion_strength = v
		_push_uniforms()

@export_range(0.0, 400.0, 0.5) var transition_start: float = 4.0:
	set(v):
		transition_start = v
		settings.transition_start = v
		_push_uniforms()

@export_range(1.0, 800.0, 0.5) var transition_end: float = 35.0:
	set(v):
		transition_end = maxf(v, settings.transition_start + 0.5)
		settings.transition_end = transition_end
		_push_uniforms()

@export_range(0.0, 120.0, 0.5) var max_bend_angle_deg: float = 90.0:
	set(v):
		max_bend_angle_deg = clampf(v, 0.0, 120.0)
		settings.max_bend_angle_deg = max_bend_angle_deg
		_push_uniforms()

@export var easing: int = 1:
	set(v):
		easing = v
		settings.easing = v
		_push_uniforms()

@export_range(0.0, 3.0, 0.01) var vertical_scale: float = 1.0:
	set(v):
		vertical_scale = v
		settings.vertical_scale = v
		_push_uniforms()

@export_range(0.0, 4.0, 0.01) var horizontal_scale: float = 1.0:
	set(v):
		horizontal_scale = v
		settings.horizontal_scale = v
		_push_uniforms()

@export_range(0.0, 4.0, 0.01) var far_horizontal_scale: float = 1.0:
	set(v):
		far_horizontal_scale = v
		settings.far_horizontal_scale = v
		_push_uniforms()

@export var debug_visualize: bool = false:
	set(v):
		debug_visualize = v
		settings.debug_visualize = v
		_push_uniforms()

var _mat_cache: Dictionary = {}
var _scan_accum: float = 0.0
var _globals_ready: bool = false
var _cached_cam: Camera3D


func _enter_tree() -> void:
	_ensure_globals()
	_push_uniforms()


func _ready() -> void:
	var tree := get_tree()
	if tree:
		if not tree.node_added.is_connected(_on_node_added):
			tree.node_added.connect(_on_node_added)
	_push_uniforms()
	call_deferred("_scan_worlds")


func _input(event: InputEvent) -> void:
	_handle_hotkey(event)


func _unhandled_input(event: InputEvent) -> void:
	_handle_hotkey(event)


func _handle_hotkey(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key != KEY_F4 and key != KEY_F3:
		return
	var focus := get_viewport().gui_get_focus_owner() if get_viewport() else null
	if focus is LineEdit or focus is TextEdit:
		return
	# _input + _unhandled_input can both see the same key; only honor once per frame.
	var frame := Engine.get_process_frames()
	if frame == int(get_meta("_np_hotkey_frame", -1)):
		return
	set_meta("_np_hotkey_frame", frame)
	if key == KEY_F4:
		toggle_enabled()
		get_viewport().set_input_as_handled()
	elif key == KEY_F3:
		toggle_debug()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_sync_camera_uniform()
	_push_uniforms()
	_scan_accum += delta
	if _scan_accum >= 0.35:
		_scan_accum = 0.0
		_cached_cam = null
		if enabled:
			_scan_worlds()
		else:
			restore_all()


func set_enabled(on: bool) -> void:
	enabled = on


func toggle_enabled() -> void:
	enabled = not enabled


func toggle_debug() -> void:
	debug_visualize = not debug_visualize


func apply_settings(s: Resource) -> void:
	if s == null:
		return
	settings = s
	enabled = bool(s.get("enabled"))
	distortion_strength = float(s.get("distortion_strength"))
	transition_start = float(s.get("transition_start"))
	transition_end = float(s.get("transition_end"))
	max_bend_angle_deg = float(s.get("max_bend_angle_deg"))
	easing = int(s.get("easing"))
	vertical_scale = float(s.get("vertical_scale"))
	horizontal_scale = float(s.get("horizontal_scale"))
	far_horizontal_scale = float(s.get("far_horizontal_scale"))
	debug_visualize = bool(s.get("debug_visualize"))
	_push_uniforms()


func apply_to_material(mat: Material) -> Material:
	if mat == null:
		return mat
	if _material_has_warp(mat):
		return mat
	if not (mat is BaseMaterial3D):
		return mat
	var key := mat.get_instance_id()
	if _mat_cache.has(key):
		var cached: Variant = _mat_cache[key]
		if cached is ShaderMaterial and is_instance_valid(cached) and int((cached as ShaderMaterial).get_meta(META_WRAP_VER, 0)) == WRAP_VERSION:
			_copy_base_to_shader(cached as ShaderMaterial, mat)
			return cached as ShaderMaterial
		_mat_cache.erase(key)
	var wrapped := _make_wrap_material(mat)
	_mat_cache[key] = wrapped
	return wrapped


func restore_all() -> void:
	var roots := _world_roots()
	for root in roots:
		_restore_tree(root)
		_stamp_tree(root)
	_mat_cache.clear()


func _on_node_added(node: Node) -> void:
	if enabled and node is GeometryInstance3D:
		_apply_to_geometry(node as GeometryInstance3D)


func _scan_worlds() -> void:
	if not enabled:
		restore_all()
		return
	for root in _world_roots():
		_scan_tree(root)
		_stamp_tree(root)


func _scan_tree(node: Node) -> void:
	if node is GeometryInstance3D:
		_apply_to_geometry(node as GeometryInstance3D)
	for child in node.get_children():
		_scan_tree(child)


func _stamp_tree(node: Node) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		_stamp_instance(gi)
		if gi.material_override is ShaderMaterial and _material_has_warp(gi.material_override):
			_stamp_wrap_locals(gi.material_override as ShaderMaterial)
		if gi is MeshInstance3D and gi.mesh != null:
			var mi := gi as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_surface_override_material(s)
				if mat == null:
					mat = mi.get_active_material(s)
				if mat is ShaderMaterial and _material_has_warp(mat):
					_stamp_wrap_locals(mat as ShaderMaterial)
	for child in node.get_children():
		_stamp_tree(child)


func _restore_tree(node: Node) -> void:
	if node is GeometryInstance3D:
		_restore_geometry(node as GeometryInstance3D)
	for child in node.get_children():
		_restore_tree(child)


func _apply_to_geometry(gi: GeometryInstance3D) -> void:
	if not is_instance_valid(gi) or not gi.is_inside_tree():
		return
	if gi is GPUParticles3D:
		return
	if gi is Label3D or gi is Sprite3D:
		return
	var parent := gi.get_parent()
	if parent is GPUParticles3D:
		return
	_ensure_cull(gi)
	if gi is MeshInstance3D:
		_apply_mesh(gi as MeshInstance3D)
	else:
		_apply_gi_override(gi)
	_stamp_instance(gi)


func _apply_mesh(mi: MeshInstance3D) -> void:
	if mi.material_override != null:
		_apply_gi_override(mi)
		return
	if mi.mesh == null:
		return
	var surf_count := mi.mesh.get_surface_count()
	if mi.has_meta(META_BACKUP):
		_resync_mesh_surfaces(mi)
		return
	for s in surf_count:
		var current := mi.get_surface_override_material(s)
		if current == null:
			current = mi.get_active_material(s)
		if current is ShaderMaterial:
			if _material_has_warp(current):
				_stamp_wrap_locals(current as ShaderMaterial)
			continue
		if current == null:
			current = mi.mesh.surface_get_material(s)
		if current == null or not (current is BaseMaterial3D):
			continue
		var wrapped: Material = apply_to_material(current)
		if wrapped == current:
			continue
		if not mi.has_meta(META_BACKUP):
			var surfaces: Array = []
			var sources: Array = []
			for i in surf_count:
				var ov: Material = mi.get_surface_override_material(i)
				if ov != null and _material_has_warp(ov):
					ov = null
				surfaces.append(ov)
				var src: Material = mi.mesh.surface_get_material(i)
				if src != null and _material_has_warp(src):
					src = null
				if src == null:
					src = mi.get_active_material(i)
				if src != null and _material_has_warp(src):
					src = mi.mesh.surface_get_material(i)
				sources.append(src)
			mi.set_meta(META_BACKUP, {
				"override": null,
				"surfaces": surfaces,
				"source_override": null,
				"source_surfaces": sources,
			})
		mi.set_surface_override_material(s, wrapped)


func _resync_mesh_surfaces(mi: MeshInstance3D) -> void:
	if not mi.has_meta(META_BACKUP):
		return
	var backup: Dictionary = mi.get_meta(META_BACKUP)
	var sources: Array = backup.get("source_surfaces", [])
	for s in sources.size():
		var src: Variant = sources[s]
		if not (src is BaseMaterial3D) or not is_instance_valid(src):
			continue
		var ov := mi.get_surface_override_material(s)
		if ov is ShaderMaterial and _material_has_warp(ov) and int(ov.get_meta(META_WRAP_VER, 0)) == WRAP_VERSION:
			_copy_base_to_shader(ov as ShaderMaterial, src as Material)
		else:
			mi.set_surface_override_material(s, apply_to_material(src as Material))


func _apply_gi_override(gi: GeometryInstance3D) -> void:
	var current: Material = gi.material_override
	if current == null:
		return
	if _material_has_warp(current):
		if current is ShaderMaterial:
			_stamp_wrap_locals(current as ShaderMaterial)
		if gi.has_meta(META_BACKUP):
			_resync_override(gi)
		return
	if not (current is BaseMaterial3D):
		return
	var wrapped := apply_to_material(current)
	if wrapped == current:
		return
	if not gi.has_meta(META_BACKUP):
		gi.set_meta(META_BACKUP, {
			"override": current,
			"surfaces": [],
			"source_override": current,
			"source_surfaces": [],
		})
	gi.material_override = wrapped


func _resync_override(gi: GeometryInstance3D) -> void:
	if not gi.has_meta(META_BACKUP):
		return
	var backup: Dictionary = gi.get_meta(META_BACKUP)
	var src: Variant = backup.get("source_override")
	if src is BaseMaterial3D and is_instance_valid(src) and gi.material_override is ShaderMaterial:
		var ov := gi.material_override as ShaderMaterial
		if int(ov.get_meta(META_WRAP_VER, 0)) == WRAP_VERSION:
			_copy_base_to_shader(ov, src as Material)
		else:
			gi.material_override = apply_to_material(src as Material)


func _restore_geometry(gi: GeometryInstance3D) -> void:
	if gi.has_meta(META_CULL):
		gi.extra_cull_margin = float(gi.get_meta(META_CULL))
		gi.remove_meta(META_CULL)
	if not gi.has_meta(META_BACKUP):
		return
	var backup: Dictionary = gi.get_meta(META_BACKUP)
	gi.material_override = backup.get("override", null)
	if gi is MeshInstance3D:
		var mi := gi as MeshInstance3D
		var surfaces: Array = backup.get("surfaces", [])
		for s in surfaces.size():
			mi.set_surface_override_material(s, surfaces[s])
	gi.remove_meta(META_BACKUP)


func _ensure_cull(gi: GeometryInstance3D) -> void:
	if not gi.has_meta(META_CULL):
		gi.set_meta(META_CULL, gi.extra_cull_margin)
	var want := float(settings.extra_cull_margin)
	if enabled:
		gi.extra_cull_margin = maxf(float(gi.get_meta(META_CULL)), want)
	else:
		gi.extra_cull_margin = float(gi.get_meta(META_CULL))


func _make_wrap_material(base: Material) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.resource_local_to_scene = true
	sm.shader = WRAP_SHADER
	sm.set_meta(META_WRAP, true)
	sm.set_meta(META_WRAP_VER, WRAP_VERSION)
	_copy_base_to_shader(sm, base)
	return sm


func _copy_base_to_shader(sm: ShaderMaterial, base: Material) -> void:
	if sm == null or sm.shader == null or base == null:
		return
	if not (base is BaseMaterial3D):
		return
	var bm := base as BaseMaterial3D
	sm.shader = WRAP_SHADER
	sm.set_meta(META_WRAP, true)
	sm.set_meta(META_WRAP_VER, WRAP_VERSION)
	sm.set_shader_parameter("np_albedo_color", bm.albedo_color)
	sm.set_shader_parameter("np_uv_scale", bm.uv1_scale)
	sm.set_shader_parameter("np_uv_offset", bm.uv1_offset)
	sm.set_shader_parameter("np_use_triplanar", 1.0 if bm.uv1_triplanar else 0.0)
	sm.set_shader_parameter("np_use_vertex_color", 1.0 if bm.vertex_color_use_as_albedo else 0.0)
	sm.set_shader_parameter("np_roughness", bm.roughness)
	var has_mr: bool = bm.metallic_texture != null or bm.roughness_texture != null
	# glTF metallicFactor defaults to 1. Without an MR map that chrome-washes albedo.
	sm.set_shader_parameter("np_metallic", bm.metallic if has_mr else 0.0)
	_set_tex(sm, "np_albedo_tex", "np_use_albedo_tex", bm.albedo_texture)
	var orm: Texture = bm.metallic_texture
	if orm == null:
		orm = bm.roughness_texture
	if orm == null and bm.ao_enabled:
		orm = bm.ao_texture
	_set_tex(sm, "np_orm_tex", "np_use_orm_tex", orm)
	sm.set_shader_parameter("np_orm_rough_ch", float(_channel_index(bm.roughness_texture_channel)))
	sm.set_shader_parameter("np_orm_metal_ch", float(_channel_index(bm.metallic_texture_channel)))
	sm.set_shader_parameter("np_orm_ao_ch", float(_channel_index(bm.ao_texture_channel)))
	sm.set_shader_parameter("np_use_ao", 1.0 if bm.ao_enabled and bm.ao_texture != null else 0.0)
	sm.set_shader_parameter("np_ao_light_affect", bm.ao_light_affect)
	if bm.normal_enabled:
		_set_tex(sm, "np_normal_tex", "np_use_normal_tex", bm.normal_texture)
		sm.set_shader_parameter("np_normal_scale", bm.normal_scale)
	else:
		_set_tex(sm, "np_normal_tex", "np_use_normal_tex", null)
		sm.set_shader_parameter("np_normal_scale", 1.0)
	var emit_on := bm.emission_enabled
	sm.set_shader_parameter("np_emission_color", bm.emission)
	sm.set_shader_parameter("np_emission_energy", bm.emission_energy_multiplier if emit_on else 0.0)
	_set_tex(sm, "np_emission_tex", "np_use_emission_tex", bm.emission_texture if emit_on else null)
	var alpha_on := bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	sm.set_shader_parameter("np_alpha_blend", 1.0 if alpha_on else 0.0)
	sm.next_pass = bm.next_pass
	_stamp_wrap_locals(sm)


func _stamp_instance(gi: GeometryInstance3D) -> void:
	if gi == null or not is_instance_valid(gi):
		return
	gi.set_instance_shader_parameter("np_u_enabled", 1.0 if enabled else 0.0)
	gi.set_instance_shader_parameter("np_u_distortion_strength", distortion_strength)
	gi.set_instance_shader_parameter("np_u_transition_start", transition_start)
	gi.set_instance_shader_parameter("np_u_transition_end", maxf(transition_end, transition_start + 0.5))
	gi.set_instance_shader_parameter("np_u_max_bend_angle", deg_to_rad(max_bend_angle_deg))
	gi.set_instance_shader_parameter("np_u_easing_mode", float(easing))
	gi.set_instance_shader_parameter("np_u_vertical_scale", vertical_scale)
	gi.set_instance_shader_parameter("np_u_horizontal_scale", horizontal_scale)
	gi.set_instance_shader_parameter("np_u_far_horizontal_scale", far_horizontal_scale)
	gi.set_instance_shader_parameter("np_u_near_z_epsilon", settings.near_z_epsilon)
	gi.set_instance_shader_parameter("np_u_debug", 1.0 if debug_visualize else 0.0)
	gi.set_instance_shader_parameter("np_u_gameplay_only", 1.0 if settings.gameplay_camera_only else 0.0)
	if is_instance_valid(_cached_cam):
		gi.set_instance_shader_parameter("np_u_camera_world_pos", _cached_cam.global_position)


func _stamp_wrap_locals(sm: ShaderMaterial) -> void:
	if sm == null:
		return
	sm.set_shader_parameter("np_u_enabled", 1.0 if enabled else 0.0)
	sm.set_shader_parameter("np_u_distortion_strength", distortion_strength)
	sm.set_shader_parameter("np_u_transition_start", transition_start)
	sm.set_shader_parameter("np_u_transition_end", maxf(transition_end, transition_start + 0.5))
	sm.set_shader_parameter("np_u_max_bend_angle", deg_to_rad(max_bend_angle_deg))
	sm.set_shader_parameter("np_u_easing_mode", float(easing))
	sm.set_shader_parameter("np_u_vertical_scale", vertical_scale)
	sm.set_shader_parameter("np_u_horizontal_scale", horizontal_scale)
	sm.set_shader_parameter("np_u_far_horizontal_scale", far_horizontal_scale)
	sm.set_shader_parameter("np_u_near_z_epsilon", settings.near_z_epsilon)
	sm.set_shader_parameter("np_u_debug", 1.0 if debug_visualize else 0.0)
	sm.set_shader_parameter("np_u_gameplay_only", 1.0 if settings.gameplay_camera_only else 0.0)
	if is_instance_valid(_cached_cam):
		sm.set_shader_parameter("np_u_camera_world_pos", _cached_cam.global_position)


func _set_tex(sm: ShaderMaterial, tex_name: String, flag_name: String, tex: Texture) -> void:
	if tex is Texture2D:
		sm.set_shader_parameter(tex_name, tex)
		sm.set_shader_parameter(flag_name, 1.0)
	else:
		sm.set_shader_parameter(tex_name, null)
		sm.set_shader_parameter(flag_name, 0.0)


func _channel_index(ch: int) -> int:
	return clampi(ch, 0, 4)


func _material_has_warp(mat: Material) -> bool:
	if mat == null:
		return false
	if bool(mat.get_meta(META_WRAP, false)):
		return true
	if not (mat is ShaderMaterial):
		return false
	var sh: Shader = (mat as ShaderMaterial).shader
	if sh == null:
		return false
	if sh == WRAP_SHADER:
		return true
	var code := sh.code
	return code.contains("np_warp_vertex_and_normal") or code.contains("nonlinear_projection.gdshaderinc")


func _world_roots() -> Array[Node]:
	var roots: Array[Node] = []
	var director := get_node_or_null("/root/ShowDirector")
	if director:
		var item: Variant = director.get("current_item_node")
		if item is Node:
			_collect_subviewports(item as Node, roots)
			if roots.is_empty():
				roots.append(item as Node)
	if roots.is_empty():
		var cam := _find_gameplay_camera()
		if cam:
			roots.append(cam.get_parent() if cam.get_parent() else cam)
	return roots


func _collect_subviewports(node: Node, out: Array[Node]) -> void:
	if node is SubViewport:
		out.append(node)
	for child in node.get_children():
		_collect_subviewports(child, out)


func _find_gameplay_camera() -> Camera3D:
	for root in _world_roots_shallow():
		var found := _find_camera(root)
		if found:
			return found
	var tree := get_tree()
	if tree and tree.root:
		var current := _find_current_camera(tree.root)
		if current:
			return current
	return get_viewport().get_camera_3d() if get_viewport() else null


func _find_current_camera(node: Node) -> Camera3D:
	if node is Camera3D and (node as Camera3D).current:
		return node as Camera3D
	for child in node.get_children():
		var found := _find_current_camera(child)
		if found:
			return found
	return null


func _world_roots_shallow() -> Array[Node]:
	var roots: Array[Node] = []
	var director := get_node_or_null("/root/ShowDirector")
	if director:
		var item: Variant = director.get("current_item_node")
		if item is Node:
			_collect_subviewports(item as Node, roots)
			if roots.is_empty():
				roots.append(item as Node)
	return roots


func _find_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node as Camera3D
	for child in node.get_children():
		var found := _find_camera(child)
		if found:
			return found
	return null


func _sync_camera_uniform() -> void:
	if not is_instance_valid(_cached_cam) or not _cached_cam.is_inside_tree():
		_cached_cam = _find_gameplay_camera()


func _ensure_globals() -> void:
	_globals_ready = true


func _push_uniforms() -> void:
	_push_wrap_locals()
	for root in _world_roots():
		_stamp_tree(root)


func _push_wrap_locals() -> void:
	for key in _mat_cache.keys():
		var cached: Variant = _mat_cache[key]
		if cached is ShaderMaterial and is_instance_valid(cached):
			_stamp_wrap_locals(cached as ShaderMaterial)
