extends Control
class_name Scene3DItem

## Displays a 3D environment via SubViewport → TextureRect.

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
	_sub_viewport.size = Vector2i(1920, 1080)
	_texture_rect.texture = _sub_viewport.get_texture()
	add_child(_sub_viewport)
	if not _pending_path.is_empty() or _pending_params.size() > 0:
		_load_scene(_pending_path, _pending_params)


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
	if _environment and _environment.has_method("set_layer_source"):
		_environment.call("set_layer_source", layer_id, config)


func set_layer_alpha(alpha: float) -> void:
	_alpha = alpha
	modulate.a = alpha


func apply_audio_state(state: AudioState) -> void:
	if _environment:
		_environment.apply_audio_state(state)


func apply_kinect_state(state: KinectState) -> void:
	if _environment:
		_environment.apply_kinect_state(state)


func set_cue_param(key: String, value: Variant) -> void:
	if _environment:
		_environment.set_cue_param(key, value)


func start_item() -> void:
	visible = true
	modulate.a = _alpha
	if _environment:
		_environment.on_item_started()


func stop_item() -> void:
	visible = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _environment:
		_environment.on_item_stopped()
