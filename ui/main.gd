extends Control

## Control surface: assets | preview | effects.
## Pop Out Stage undocks the live SubViewport into a real OS window (second monitor).

@onready var playlist_sidebar: PanelContainer = $Root/PlaylistSidebar
@onready var effects_sidebar: PanelContainer = $Root/EffectsSidebar
@onready var output_pane: PanelContainer = $Root/OutputPane
@onready var output_column: VBoxContainer = $Root/OutputPane/OutputColumn
@onready var present_button: Button = $Root/OutputPane/OutputColumn/OutputHeader/PresentButton
@onready var output_title: Label = $Root/OutputPane/OutputColumn/OutputHeader/OutputTitle
@onready var output_viewport_container: SubViewportContainer = $Root/OutputPane/OutputColumn/OutputViewportContainer
@onready var output_viewport: SubViewport = $Root/OutputPane/OutputColumn/OutputViewportContainer/OutputViewport
@onready var output_stack: Control = $Root/OutputPane/OutputColumn/OutputViewportContainer/OutputViewport/OutputStack
@onready var effect_stack: EffectStack = $Root/OutputPane/OutputColumn/OutputViewportContainer/OutputViewport/EffectStack

var _stage_window: Window
var _undock_placeholder: Control
var _stage_undocked: bool = false
## Edge-trigger latch for joypad playlist buttons (device_id:button -> held).
var _joy_held: Dictionary = {}


func _ready() -> void:
	# Ensure pop-out uses a real OS window that can leave the main monitor.
	get_tree().root.gui_embed_subwindows = false
	ShowDirector.bind_output(output_stack, effect_stack)
	present_button.pressed.connect(toggle_stage_undock)
	if playlist_sidebar.has_signal("present_requested"):
		playlist_sidebar.present_requested.connect(toggle_stage_undock)
	var win := get_window()
	win.size = Vector2i(1700, 950)
	win.min_size = Vector2i(1200, 700)
	win.close_requested.connect(_on_main_window_close_requested)
	set_process(true)
	# Let the first frame paint before session/stage apply (assets already warmed by BootLoader).
	call_deferred("_boot_stage")


func _boot_stage() -> void:
	# Last session overrides blank defaults (demo show.json stays untouched).
	if not _restore_last_session():
		_start_blank_stage()


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
	var effects: Variant = data.get("effects", ["ascii", "feedback", "glitch"])
	var cues: Variant = data.get("cues", [])
	ShowDirector.show_data = {
		"name": show_name,
		"items": [],
		"cues": cues if cues is Array else [],
		"effects": effects if effects is Array else ["ascii", "feedback", "glitch"],
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
	if effects_sidebar != null and effects_sidebar.has_method("apply_session_fx"):
		effects_sidebar.call("apply_session_fx", data)
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
	if sb.has("path_style") or sb.has("camera_path"):
		var style_val := FlythroughPathBuilder.normalize_style(
			str(sb.get("path_style", sb.get("camera_path", "auto")))
		)
		item.params["path_style"] = style_val
		item.params["camera_path"] = style_val
		ShowDirector.set_active_cue_param("path_style", style_val)
	if sb.has("env_scale"):
		var scale_val := maxf(float(sb["env_scale"]), 0.01)
		var env_cfg: Dictionary = (item.params.get("environment", {}) as Dictionary).duplicate(true)
		env_cfg["user_scale"] = scale_val
		item.params["environment"] = env_cfg
		ShowDirector.set_active_cue_param("env_scale", scale_val)
	if sb.has("scatter_global_scale") and (sb["scatter_global_scale"] is float or sb["scatter_global_scale"] is int):
		var gscale := clampf(float(sb["scatter_global_scale"]), 0.01, 100.0)
		var sc_cfg: Dictionary = (item.params.get("scatter", {}) as Dictionary).duplicate(true)
		sc_cfg["global_scale"] = gscale
		item.params["scatter"] = sc_cfg
		ShowDirector.set_active_cue_param("scatter_global_scale", gscale)


func _start_blank_stage() -> void:
	## Empty fly-through stage — pick assets from Env / Main / Scatter / Lighting tabs.
	ShowDirector.clear_playlist()
	ShowDirector.show_data = {"name": "HyperSpace", "items": [], "cues": [], "effects": ["ascii", "feedback", "glitch"]}
	ShowDirector.cues = []
	ShowDirector.add_item_from_dict({
		"id": "stage",
		"type": "scene3d",
		"path": "",
		"duration": ShowDirector.default_item_duration,
		"params": FlythroughAssetCatalog.blank_stage_params(),
	}, true)
	ShowDirector.show_loaded.emit("HyperSpace")


func toggle_stage_undock() -> void:
	if _stage_undocked:
		_dock_stage_window()
	else:
		_undock_stage_window()


## Backward-compatible alias (playlist signal / older callers).
func toggle_present_mode() -> void:
	toggle_stage_undock()


func _undock_stage_window() -> void:
	if _stage_undocked or _stage_window != null:
		return
	get_tree().root.gui_embed_subwindows = false

	_stage_window = Window.new()
	_stage_window.title = "HyperSpace — Stage"
	_stage_window.exclusive = false
	_stage_window.transient = false
	_stage_window.always_on_top = false
	_stage_window.unresizable = false
	_stage_window.borderless = false
	_stage_window.min_size = Vector2i(640, 360)

	var screen_idx := 1 if DisplayServer.get_screen_count() > 1 else 0
	var screen_pos := DisplayServer.screen_get_position(screen_idx)
	var screen_size := DisplayServer.screen_get_size(screen_idx)
	var win_size := Vector2i(
		clampi(1280, 640, maxi(640, screen_size.x - 80)),
		clampi(720, 360, maxi(360, screen_size.y - 80))
	)
	_stage_window.size = win_size
	if DisplayServer.get_screen_count() > 1:
		_stage_window.current_screen = screen_idx
		_stage_window.position = screen_pos + Vector2i(40, 40)
	else:
		var main_win := get_window()
		_stage_window.position = main_win.position + Vector2i(100, 60)

	get_tree().root.add_child(_stage_window)

	# Reparent the live stage (same SubViewport / effects / 3D world) into the OS window.
	# Do NOT TextureRect-mirror — that produced the gray Present feed.
	output_viewport_container.reparent(_stage_window)
	output_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	output_viewport_container.offset_left = 0.0
	output_viewport_container.offset_top = 0.0
	output_viewport_container.offset_right = 0.0
	output_viewport_container.offset_bottom = 0.0
	output_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	_show_undock_placeholder()

	_stage_window.close_requested.connect(_dock_stage_window)
	_stage_window.window_input.connect(_on_stage_window_input)
	_stage_window.visible = true
	_stage_window.grab_focus()
	_stage_undocked = true
	present_button.text = "Dock Stage"
	if output_title:
		output_title.text = "  Stage undocked — drag the Stage window to your projector / 2nd monitor"


func _dock_stage_window() -> void:
	if not _stage_undocked and _stage_window == null:
		return
	var win := _stage_window
	_stage_window = null
	_stage_undocked = false
	present_button.text = "Pop Out Stage"
	if output_title:
		output_title.text = "  Preview  —  Pop Out Stage = detach live scene window (Esc/F11 docks)"

	# Bring the live viewport back before freeing the window.
	if is_instance_valid(output_viewport_container):
		if output_viewport_container.get_parent() != output_column:
			output_viewport_container.reparent(output_column)
		# Restore VBox layout (clear full-rect window anchors).
		output_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		output_viewport_container.anchor_right = 0.0
		output_viewport_container.anchor_bottom = 0.0
		output_viewport_container.offset_left = 0.0
		output_viewport_container.offset_top = 0.0
		output_viewport_container.offset_right = 0.0
		output_viewport_container.offset_bottom = 0.0
		output_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		output_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		# Header is index 0; viewport should sit under it (placeholder removed next).
		if output_column.get_child_count() > 1:
			output_column.move_child(output_viewport_container, 1)
		output_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	_hide_undock_placeholder()

	if win != null and is_instance_valid(win):
		if win.window_input.is_connected(_on_stage_window_input):
			win.window_input.disconnect(_on_stage_window_input)
		if win.close_requested.is_connected(_dock_stage_window):
			win.close_requested.disconnect(_dock_stage_window)
		win.hide()
		win.queue_free()

	var main_win := get_window()
	if main_win:
		main_win.grab_focus()


func _show_undock_placeholder() -> void:
	_hide_undock_placeholder()
	_undock_placeholder = PanelContainer.new()
	_undock_placeholder.name = "UndockPlaceholder"
	_undock_placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_undock_placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := Label.new()
	title.text = "Stage window is popped out"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint := Label.new()
	hint.text = "Drag HyperSpace — Stage onto your second monitor.\nPlaylists (left) and effects (right) stay here."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(320, 0)
	var dock_btn := Button.new()
	dock_btn.text = "Dock Stage"
	dock_btn.pressed.connect(_dock_stage_window)
	col.add_child(title)
	col.add_child(hint)
	col.add_child(dock_btn)
	center.add_child(col)
	_undock_placeholder.add_child(center)
	output_column.add_child(_undock_placeholder)
	# Keep placeholder under header; viewport already left the column.
	if output_column.get_child_count() > 1:
		output_column.move_child(_undock_placeholder, 1)


func _hide_undock_placeholder() -> void:
	if _undock_placeholder != null and is_instance_valid(_undock_placeholder):
		_undock_placeholder.queue_free()
	_undock_placeholder = null


func _on_stage_window_input(event: InputEvent) -> void:
	## Stage window has OS focus — Escape / F11 must dock from here.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_F11:
			if _stage_window != null:
				_stage_window.set_input_as_handled()
			_dock_stage_window()


func _process(_delta: float) -> void:
	## Joypad edge poll so layer switching works even when Stage has OS focus.
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
				toggle_stage_undock()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if _stage_undocked:
					_dock_stage_window()
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
