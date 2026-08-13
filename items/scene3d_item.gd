extends Control
class_name Scene3DItem

## Displays a 3D environment via SubViewport → TextureRect.

const _SceneMeshFx := preload("res://core/scene_mesh_fx.gd")

var item_id: String = ""
var item_loop: bool = false

var _sub_viewport: SubViewport
var _texture_rect: TextureRect
var _environment: ReactiveEnvironment = null
var _alpha: float = 1.0
var _pending_path: String = ""
var _pending_params: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_texture_rect = TextureRect.new()
	_texture_rect.set_anchors_preset(PRESET_FULL_RECT)
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_texture_rect)
	_sub_viewport = SubViewport.new()
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub_viewport.size = Vector2i(1280, 720)
	# Isolated 3D world so WorldEnvironment / HDRI sky actually apply as background.
	_sub_viewport.own_world_3d = true
	_sub_viewport.transparent_bg = false
	_texture_rect.texture = _sub_viewport.get_texture()
	add_child(_sub_viewport)
	if not _pending_path.is_empty() or _pending_params.size() > 0:
		_load_scene(_pending_path, _pending_params)
	call_deferred("_sync_viewport_size")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_sync_viewport_size()


func _sync_viewport_size() -> void:
	if _sub_viewport == null:
		return
	var sx := int(size.x)
	var sy := int(size.y)
	if sx < 64 or sy < 64:
		return
	# Match panel size but soft-cap fill rate for post-FX stack.
	var target := Vector2i(clampi(sx, 640, 1600), clampi(sy, 360, 900))
	# Keep ~16:9-ish when panel is weirdly tall/wide.
	if float(target.x) / float(maxi(target.y, 1)) > 2.2:
		target.x = int(target.y * 16.0 / 9.0)
	if _sub_viewport.size != target:
		_sub_viewport.size = target


func _gui_input(event: InputEvent) -> void:
	_forward_look(event)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			accept_event()


func _input(event: InputEvent) -> void:
	# Captured mouse motion often arrives via _input rather than _gui_input.
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_forward_look(event)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		accept_event()


func _forward_look(event: InputEvent) -> void:
	if _environment and _environment.has_method("handle_look_input"):
		_environment.call("handle_look_input", event)


func configure(item: PlaylistItem) -> void:
	item_id = item.id
	item_loop = item.loop
	_pending_path = item.path
	_pending_params = item.params
	if _sub_viewport:
		_load_scene(item.path, item.params)


func _load_scene(scene_path: String, params: Dictionary) -> void:
	for child in _sub_viewport.get_children():
		child.queue_free()
	_environment = null
	if scene_path.is_empty():
		_create_fallback_environment(params)
		return
	if scene_path.ends_with(".tscn") and ResourceLoader.exists(scene_path):
		var packed: PackedScene = load(scene_path)
		if packed:
			var instance := packed.instantiate()
			_sub_viewport.add_child(instance)
			_SceneMeshFx.ensure_mesh_tangents(instance)
			if instance is ReactiveEnvironment:
				_environment = instance
			return
	if (scene_path.ends_with(".glb") or scene_path.ends_with(".gltf")) and FileAccess.file_exists(scene_path):
		var gltf := GLTFDocument.new()
		var state := GLTFState.new()
		var err := gltf.append_from_file(scene_path, state)
		if err == OK:
			var scene := gltf.generate_scene(state)
			_sub_viewport.add_child(scene)
			_SceneMeshFx.ensure_mesh_tangents(scene)
			return
	push_warning("Scene3DItem: could not load %s, using fallback" % scene_path)
	_create_fallback_environment(params)


func _create_fallback_environment(params: Dictionary) -> void:
	var style := str(params.get("style", "flythrough"))
	var env: ReactiveEnvironment = null
	match style:
		"demo", "stage":
			env = DemoEnvironment.new()
		"flythrough", "corridor", "tunnel", "city", _:
			env = FlythroughEnvironment.new()
	_sub_viewport.add_child(env)
	_environment = env
	if env is FlythroughEnvironment:
		(env as FlythroughEnvironment).configure_from_params(params)
	elif params.has("color") and _environment.has_method("set_cue_param"):
		_environment.set_cue_param("color", params["color"])


func set_flythrough_layer(layer_id: String, config: Dictionary) -> void:
	_pending_params["style"] = "flythrough"
	_pending_params[layer_id] = config.duplicate(true)
	if _environment != null and _environment.has_method("set_layer_source"):
		_environment.call("set_layer_source", layer_id, config)
		return
	# Wrong / missing env (e.g. DemoEnvironment) — rebuild as flythrough so lighting/HDRI apply.
	if _sub_viewport != null:
		_load_scene(_pending_path, _pending_params)


func restore_reactive_poses() -> void:
	if _environment != null and _environment.has_method("restore_reactive_poses"):
		_environment.call("restore_reactive_poses")


func reset_stage_to_defaults() -> void:
	if _environment != null and _environment.has_method("reset_stage_to_defaults"):
		_environment.call("reset_stage_to_defaults")
		if _pending_params.has("speed") or _pending_params.has("fly_speed"):
			_pending_params["speed"] = 2.0
			_pending_params["fly_speed"] = 2.0
		return
	# Non-flythrough fallback: drop reactive leftovers if the env knows how.
	restore_reactive_poses()


func set_layer_alpha(alpha: float) -> void:
	_alpha = alpha
	modulate.a = alpha


func apply_audio_state(state: AudioState) -> void:
	if _environment:
		_environment.apply_audio_state(state)


func get_path_progress() -> float:
	if _environment != null and _environment.has_method("get_path_progress"):
		return float(_environment.call("get_path_progress"))
	return 0.0


func get_fly_speed() -> float:
	if _environment != null and _environment.has_method("get_fly_speed"):
		return float(_environment.call("get_fly_speed"))
	if _environment != null and _environment.get("fly_speed") != null:
		return float(_environment.get("fly_speed"))
	return 0.0


func apply_kinect_state(state: KinectState) -> void:
	if _environment:
		_environment.apply_kinect_state(state)


func set_cue_param(key: String, value: Variant) -> void:
	_pending_params[key] = value
	if key == "fly_speed" or key == "speed":
		_pending_params["fly_speed"] = float(value)
		_pending_params["speed"] = float(value)
	elif key == "path_style" or key == "camera_path":
		var style := FlythroughPathBuilder.normalize_style(str(value))
		_pending_params["path_style"] = style
		_pending_params["camera_path"] = style
	if _environment:
		_environment.set_cue_param(key, value)


func set_wireframe(on: bool) -> void:
	if _sub_viewport == null:
		return
	_sub_viewport.debug_draw = (
		SubViewport.DEBUG_DRAW_WIREFRAME if on else SubViewport.DEBUG_DRAW_DISABLED
	)


func set_cloth(on: bool, params: Dictionary = {}) -> void:
	if _environment != null and _environment.has_method("set_cloth"):
		_environment.call("set_cloth", on, params)
		return
	if _sub_viewport:
		_generic_cloth(on, params)


func set_point_cloud(on: bool, params: Dictionary = {}) -> void:
	if _environment != null and _environment.has_method("set_point_cloud"):
		_environment.call("set_point_cloud", on, params)
		return
	if _sub_viewport:
		var size := clampf(float(params.get("point_size", 6.0)), 1.0, 64.0)
		var targets: Dictionary = SceneMeshFx.pc_targets_from(params)
		var want_layers := bool(targets.get("target_environment", true)) \
			or bool(targets.get("target_main", true)) \
			or bool(targets.get("target_scatter", true))
		if not on or not want_layers:
			SceneMeshFx.clear_point_cloud(_sub_viewport)
			return
		var roots: Array = [_sub_viewport] if want_layers else []
		SceneMeshFx.apply_point_cloud_layers(_sub_viewport, roots, true, size, false)


func set_camera_fx(on: bool, params: Dictionary = {}) -> void:
	if _environment != null and _environment.has_method("set_camera_fx"):
		_environment.call("set_camera_fx", on, params)
		return
	if _sub_viewport:
		var cam := SceneMeshFx.find_camera(_sub_viewport)
		SceneMeshFx.apply_camera_fx(cam, on, params)


func _generic_cloth(on: bool, params: Dictionary) -> void:
	## Fallback for non-flythrough envs: shader uniforms on any ShaderMaterial + SoftBody on grids.
	var meshes: Array = []
	SceneMeshFx.collect_meshes(_sub_viewport, meshes)
	var amt := float(params.get("amount", 0.7)) if on else 0.0
	var stiff := float(params.get("stiffness", 0.55))
	var wind := float(params.get("wind", 0.55)) if on else 0.0
	for mi_any in meshes:
		if not (mi_any is MeshInstance3D):
			continue
		var mi := mi_any as MeshInstance3D
		if str(mi.name).begins_with("HSPointCloud"):
			continue
		var mat := mi.material_override
		if mat is ShaderMaterial:
			var sm := mat as ShaderMaterial
			sm.set_shader_parameter("cloth_amount", amt)
			sm.set_shader_parameter("cloth_stiffness", stiff)
			sm.set_shader_parameter("cloth_wind", wind)
			sm.set_shader_parameter("cloth_time", float(Time.get_ticks_msec()) * 0.001)
		if mi.get_parent() is FlythroughMediaProp:
			(mi.get_parent() as FlythroughMediaProp).set_softbody_cloth(
				on, stiff, float(params.get("damping", 0.28)), Vector3(wind * 2.0, 0.2, wind)
			)


func start_item() -> void:
	visible = true
	modulate.a = _alpha
	if _sub_viewport:
		_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if _environment:
		_environment.set_process(true)
		_environment.on_item_started()


func stop_item() -> void:
	visible = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _environment:
		_environment.on_item_stopped()
