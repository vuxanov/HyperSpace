extends Control

## Control surface: assets | preview | effects.
## Present Mode opens a separate fullscreen OS window (projector feed, no UI).

@onready var playlist_sidebar: PanelContainer = $Root/PlaylistSidebar
@onready var effects_sidebar: PanelContainer = $Root/EffectsSidebar
@onready var output_pane: PanelContainer = $Root/OutputPane
@onready var present_button: Button = $Root/OutputPane/OutputColumn/OutputHeader/PresentButton
@onready var output_viewport: SubViewport = $Root/OutputPane/OutputColumn/OutputViewportContainer/OutputViewport
@onready var output_stack: Control = $Root/OutputPane/OutputColumn/OutputViewportContainer/OutputViewport/OutputStack
@onready var effect_stack: EffectStack = $Root/OutputPane/OutputColumn/OutputViewportContainer/OutputViewport/EffectStack

var _present_window: Window
var _present_rect: TextureRect
var _presenting: bool = false
## Edge-trigger latch for joypad playlist buttons (device_id:button -> held).
var _joy_held: Dictionary = {}


func _ready() -> void:
	ShowDirector.bind_output(output_stack, effect_stack)
	present_button.pressed.connect(toggle_present_mode)
	if playlist_sidebar.has_signal("present_requested"):
		playlist_sidebar.present_requested.connect(toggle_present_mode)
	# Last session overrides blank defaults (demo show.json stays untouched).
	if not _restore_last_session():
		_start_blank_stage()
	var win := get_window()
	win.size = Vector2i(1700, 950)
	win.min_size = Vector2i(1200, 700)
	win.close_requested.connect(_on_main_window_close_requested)
	set_process(true)


func _on_main_window_close_requested() -> void:
	if playlist_sidebar != null and playlist_sidebar.has_method("_save_session_now"):
		playlist_sidebar.call("_save_session_now")


func _restore_last_session() -> bool:
	## Reload playlist items + applied layers from user://hyperspace_session.json.
	var data := SessionStore.load_session()
	if data.is_empty():
		return false
	var raw_items: Variant = data.get("items", [])
	if not (raw_items is Array) or (raw_items as Array).is_empty():
		return false
	if playlist_sidebar != null and playlist_sidebar.has_method("begin_session_restore"):
		playlist_sidebar.call("begin_session_restore")
	ShowDirector.clear_playlist()
	var show_name := str(data.get("name", "HyperSpace"))
	var effects: Variant = data.get("effects", ["ascii", "particles", "feedback", "glitch"])
	var cues: Variant = data.get("cues", [])
	ShowDirector.show_data = {
		"name": show_name,
		"items": [],
		"cues": cues if cues is Array else [],
		"effects": effects if effects is Array else ["ascii", "particles", "feedback", "glitch"],
	}
	ShowDirector.cues = ShowDirector.show_data["cues"]
	var play_idx := int(data.get("current_index", 0))
	var first := true
	for item_data in raw_items:
		if not (item_data is Dictionary):
			continue
		ShowDirector.add_item_from_dict(item_data as Dictionary, first)
		first = false
	if ShowDirector.items.is_empty():
		if playlist_sidebar != null and playlist_sidebar.has_method("end_session_restore"):
			playlist_sidebar.call("end_session_restore")
		return false
	play_idx = clampi(play_idx, 0, ShowDirector.items.size() - 1)
	if ShowDirector.current_index != play_idx:
		ShowDirector.play_index(play_idx, Transition.Mode.CUT, 0.0)
	# Apply sidebar fly_speed / env_scale onto the live stage if present.
	_apply_session_sidebar_params(data)
	if playlist_sidebar != null and playlist_sidebar.has_method("end_session_restore"):
		playlist_sidebar.call("end_session_restore")
	ShowDirector.show_loaded.emit(show_name)
	return true


func _apply_session_sidebar_params(data: Dictionary) -> void:
	var sidebar: Variant = data.get("sidebar", {})
	if not (sidebar is Dictionary):
		return
	var sb: Dictionary = sidebar
	if ShowDirector.current_index < 0 or ShowDirector.current_index >= ShowDirector.items.size():
		return
	var item: PlaylistItem = ShowDirector.items[ShowDirector.current_index]
	if sb.has("fly_speed"):
		var speed_val := float(sb["fly_speed"])
		item.params["fly_speed"] = speed_val
		item.params["speed"] = speed_val
		ShowDirector.set_active_cue_param("fly_speed", speed_val)
	if sb.has("env_scale"):
		var scale_val := clampf(roundf(float(sb["env_scale"])), 1.0, 50.0)
		var env_cfg: Dictionary = (item.params.get("environment", {}) as Dictionary).duplicate(true)
		env_cfg["user_scale"] = scale_val
		item.params["environment"] = env_cfg
		ShowDirector.set_active_cue_param("env_scale", scale_val)


func _start_blank_stage() -> void:
	## Empty fly-through stage — pick assets from Env / Main / Scatter / Lighting tabs.
	ShowDirector.clear_playlist()
	ShowDirector.show_data = {"name": "HyperSpace", "items": [], "cues": [], "effects": ["ascii", "particles", "feedback", "glitch"]}
	ShowDirector.cues = []
	ShowDirector.add_item_from_dict({
		"id": "stage",
		"type": "scene3d",
		"path": "",
		"duration": ShowDirector.default_item_duration,
		"params": FlythroughAssetCatalog.blank_stage_params(),
	}, true)
	ShowDirector.show_loaded.emit("HyperSpace")


func toggle_present_mode() -> void:
	if _presenting:
		_close_present_window()
	else:
		_open_present_window()


func _open_present_window() -> void:
	if _present_window != null:
		return
	_present_window = Window.new()
	_present_window.title = "HyperSpace — Present"
	_present_window.exclusive = false
	_present_window.transient = false
	_present_window.always_on_top = false
	_present_window.unresizable = true
	_present_window.borderless = true
	# Prefer second monitor when available (projector / dual-display).
	var screen_idx := 1 if DisplayServer.get_screen_count() > 1 else 0
	_present_window.current_screen = screen_idx
	_present_window.position = DisplayServer.screen_get_position(screen_idx)
	_present_window.size = DisplayServer.screen_get_size(screen_idx)
	_present_rect = TextureRect.new()
	_present_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_present_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_present_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_present_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_present_rect.texture = output_viewport.get_texture()
	_present_window.add_child(_present_rect)
	get_tree().root.add_child(_present_window)
	_present_window.close_requested.connect(_close_present_window)
	_present_window.window_input.connect(_on_present_window_input)
	# Window defaults to hidden — must show for a real projector feed.
	_present_window.visible = true
	_present_window.mode = Window.MODE_FULLSCREEN
	_present_window.grab_focus()
	_presenting = true
	present_button.text = "Close Present"


func _close_present_window() -> void:
	if not _presenting and _present_window == null:
		return
	var win := _present_window
	_present_window = null
	_present_rect = null
	_presenting = false
	present_button.text = "Present Mode"
	if win != null and is_instance_valid(win):
		if win.window_input.is_connected(_on_present_window_input):
			win.window_input.disconnect(_on_present_window_input)
		if win.close_requested.is_connected(_close_present_window):
			win.close_requested.disconnect(_close_present_window)
		win.hide()
		win.queue_free()
	# Return keyboard focus to the editor window.
	var main_win := get_window()
	if main_win:
		main_win.grab_focus()


func _on_present_window_input(event: InputEvent) -> void:
	## Present window has OS focus — Escape / F11 must be handled here (main `_input` won't see them).
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_F11:
			if _present_window != null:
				_present_window.set_input_as_handled()
			_close_present_window()


func _process(_delta: float) -> void:
	## Joypad edge poll so layer switching works even when Present has OS focus.
	_poll_joypad_playlist_edges()


func _poll_joypad_playlist_edges() -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		_joy_held.clear()
		return
	for device_id in pads:
		_joy_edge(int(device_id), JOY_BUTTON_DPAD_LEFT, func() -> void: _cycle_main(-1))
		_joy_edge(int(device_id), JOY_BUTTON_DPAD_RIGHT, func() -> void: _cycle_main(1))
		_joy_edge(int(device_id), JOY_BUTTON_DPAD_UP, func() -> void: _cycle_env(-1))
		_joy_edge(int(device_id), JOY_BUTTON_DPAD_DOWN, func() -> void: _cycle_env(1))
		_joy_edge(int(device_id), JOY_BUTTON_LEFT_SHOULDER, func() -> void: _cycle_scatter(-1))
		_joy_edge(int(device_id), JOY_BUTTON_RIGHT_SHOULDER, func() -> void: _cycle_scatter(1))


func _joy_edge(device_id: int, button: int, on_press: Callable) -> void:
	var key := "%d:%d" % [device_id, button]
	var down := Input.is_joy_button_pressed(device_id, button)
	var was: bool = bool(_joy_held.get(key, false))
	_joy_held[key] = down
	if down and not was:
		on_press.call()


func _cycle_env(delta_i: int) -> void:
	if playlist_sidebar.has_method("cycle_environment"):
		playlist_sidebar.cycle_environment(delta_i)


func _cycle_main(delta_i: int) -> void:
	if playlist_sidebar.has_method("cycle_main"):
		playlist_sidebar.cycle_main(delta_i)


func _cycle_scatter(delta_i: int) -> void:
	if playlist_sidebar.has_method("cycle_scatter"):
		playlist_sidebar.cycle_scatter(delta_i)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F11:
				toggle_present_mode()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if _presenting:
					_close_present_window()
					get_viewport().set_input_as_handled()
			KEY_RIGHT:
				if playlist_sidebar.has_method("step_next"):
					playlist_sidebar.step_next()
				else:
					ShowDirector.next_item()
			KEY_LEFT:
				if playlist_sidebar.has_method("step_prev"):
					playlist_sidebar.step_prev()
				else:
					ShowDirector.prev_item()
			KEY_SPACE:
				if playlist_sidebar.has_method("toggle_tab_play"):
					playlist_sidebar.toggle_tab_play()
			KEY_DELETE:
				if ShowDirector.current_index >= 0:
					ShowDirector.remove_item_at(ShowDirector.current_index)
