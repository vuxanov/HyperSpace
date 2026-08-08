extends PanelContainer

## Left sidebar — playlist, autoplay, media import, fly-through layer slots.

signal present_requested

@onready var show_label: Label = $Margin/Column/Header/ShowLabel
@onready var item_label: Label = $Margin/Column/Header/ItemLabel
@onready var prev_button: Button = $Margin/Column/Transport/PrevButton
@onready var play_button: Button = $Margin/Column/Transport/PlayButton
@onready var next_button: Button = $Margin/Column/Transport/NextButton
@onready var present_button: Button = $Margin/Column/Transport/PresentButton
@onready var default_duration: SpinBox = $Margin/Column/AutoplayRow/DefaultDuration
@onready var playlist_list: VBoxContainer = $Margin/Column/Scroll/PlaylistList
@onready var add_media_button: Button = $Margin/Column/AddRow/AddMediaButton
@onready var add_env_button: MenuButton = $Margin/Column/AddRow/AddEnvButton
@onready var clear_button: Button = $Margin/Column/ClearButton
@onready var file_dialog: FileDialog = $FileDialog
@onready var layer_file_dialog: FileDialog = $LayerFileDialog
@onready var fly_section: VBoxContainer = $Margin/Column/FlythroughSection
@onready var env_label: Label = $Margin/Column/FlythroughSection/EnvLayerRow/EnvLabel
@onready var scatter_label: Label = $Margin/Column/FlythroughSection/ScatterLayerRow/ScatterLabel
@onready var center_label: Label = $Margin/Column/FlythroughSection/CenterLayerRow/CenterLabel
@onready var env_file_btn: Button = $Margin/Column/FlythroughSection/EnvLayerRow/EnvFileBtn
@onready var scatter_file_btn: Button = $Margin/Column/FlythroughSection/ScatterLayerRow/ScatterFileBtn
@onready var center_file_btn: Button = $Margin/Column/FlythroughSection/CenterLayerRow/CenterFileBtn
@onready var env_prim_btn: MenuButton = $Margin/Column/FlythroughSection/EnvLayerRow/EnvPrimBtn
@onready var scatter_prim_btn: MenuButton = $Margin/Column/FlythroughSection/ScatterLayerRow/ScatterPrimBtn
@onready var center_prim_btn: MenuButton = $Margin/Column/FlythroughSection/CenterLayerRow/CenterPrimBtn

var _selected_index: int = -1
var _rebuilding: bool = false
var _layer_pick: String = ""  # environment | scatter | centerpiece


func _ready() -> void:
	prev_button.pressed.connect(func() -> void: ShowDirector.prev_item(Transition.Mode.CUT, 0.0))
	next_button.pressed.connect(func() -> void: ShowDirector.next_item(Transition.Mode.CUT, 0.0))
	play_button.pressed.connect(_on_play_pressed)
	present_button.pressed.connect(func() -> void: present_requested.emit())
	add_media_button.pressed.connect(_on_add_media)
	var env_popup := add_env_button.get_popup()
	env_popup.clear()
	env_popup.add_item("Fly-through (3 layers)", 0)
	env_popup.add_item("Stage (rings + cube)", 1)
	env_popup.id_pressed.connect(_on_add_env_id)
	clear_button.pressed.connect(_on_clear)
	default_duration.value_changed.connect(_on_default_duration)
	file_dialog.file_selected.connect(_on_file_selected)
	layer_file_dialog.file_selected.connect(_on_layer_file_selected)
	env_file_btn.pressed.connect(func() -> void: _pick_layer_file("environment"))
	scatter_file_btn.pressed.connect(func() -> void: _pick_layer_file("scatter"))
	center_file_btn.pressed.connect(func() -> void: _pick_layer_file("centerpiece"))
	_setup_primitive_menus()
	ShowDirector.show_loaded.connect(_on_show_loaded)
	ShowDirector.item_changed.connect(_on_item_changed)
	ShowDirector.playlist_changed.connect(_rebuild_playlist)
	ShowDirector.autoplay_changed.connect(_on_autoplay_changed)
	default_duration.value = ShowDirector.default_item_duration
	_rebuild_playlist()
	_refresh_flythrough_section()


func _setup_primitive_menus() -> void:
	var env_pop := env_prim_btn.get_popup()
	env_pop.clear()
	env_pop.add_item("Box corridor", 0)
	env_pop.add_item("Flat plane", 1)
	env_pop.id_pressed.connect(_on_env_primitive)
	var sc_pop := scatter_prim_btn.get_popup()
	sc_pop.clear()
	sc_pop.add_item("Cubes", 0)
	sc_pop.add_item("Spheres", 1)
	sc_pop.id_pressed.connect(_on_scatter_primitive)
	var c_pop := center_prim_btn.get_popup()
	c_pop.clear()
	c_pop.add_item("Torus", 0)
	c_pop.add_item("Icosphere", 1)
	c_pop.id_pressed.connect(_on_center_primitive)


func _on_show_loaded(show_name: String) -> void:
	show_label.text = show_name
	_rebuild_playlist()
	_refresh_flythrough_section()


func _on_item_changed(item_id: String, index: int) -> void:
	_selected_index = index
	var dur := ShowDirector.get_current_item_duration()
	item_label.text = "Playing: %s  (%.1fs)" % [item_id, dur]
	_rebuild_playlist()
	_refresh_flythrough_section()


func _on_autoplay_changed(playing: bool) -> void:
	play_button.text = "■ Stop" if playing else "▶ Play"


func _on_play_pressed() -> void:
	if ShowDirector.items.is_empty():
		return
	if ShowDirector.current_index < 0:
		ShowDirector.play_index(0, Transition.Mode.CUT, 0.0)
	ShowDirector.toggle_autoplay()


func _on_default_duration(value: float) -> void:
	ShowDirector.default_item_duration = value


func _rebuild_playlist() -> void:
	_rebuilding = true
	for child in playlist_list.get_children():
		child.queue_free()
	for i in ShowDirector.items.size():
		var item: PlaylistItem = ShowDirector.items[i]
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var play_btn := Button.new()
		var src := str(item.params.get("source_type", item.type))
		if str(item.params.get("style", "")) == "flythrough":
			src = "flythrough"
		play_btn.text = "%d. [%s] %s" % [i + 1, src, item.id]
		play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		play_btn.toggle_mode = true
		play_btn.button_pressed = (i == _selected_index) or (i == ShowDirector.current_index)
		play_btn.pressed.connect(_on_row_play.bind(i))
		var dur := SpinBox.new()
		dur.min_value = 0.5
		dur.max_value = 600.0
		dur.step = 0.5
		dur.custom_minimum_size = Vector2(72, 0)
		dur.suffix = "s"
		dur.value = item.duration if item.duration > 0.0 else ShowDirector.default_item_duration
		dur.value_changed.connect(_on_row_duration.bind(i))
		var del_btn := Button.new()
		del_btn.text = "✕"
		del_btn.custom_minimum_size = Vector2(36, 0)
		del_btn.tooltip_text = "Remove from playlist"
		del_btn.pressed.connect(_on_row_delete.bind(i))
		row.add_child(play_btn)
		row.add_child(dur)
		row.add_child(del_btn)
		playlist_list.add_child(row)
	_rebuilding = false
	_refresh_flythrough_section()


func _flythrough_index() -> int:
	var idx := _selected_index if _selected_index >= 0 else ShowDirector.current_index
	if idx < 0 or idx >= ShowDirector.items.size():
		return -1
	var item: PlaylistItem = ShowDirector.items[idx]
	if item.type == "scene3d" and str(item.params.get("style", "flythrough")) == "flythrough":
		return idx
	if item.type == "scene3d" and str(item.params.get("style", "")) in ["corridor", "tunnel", "city", ""]:
		# Treat legacy animated styles as flythrough-editable once selected.
		if str(item.params.get("style", "")) != "demo":
			return idx
	return -1


func _refresh_flythrough_section() -> void:
	var idx := _flythrough_index()
	var enabled := idx >= 0
	fly_section.modulate.a = 1.0 if enabled else 0.45
	env_file_btn.disabled = not enabled
	scatter_file_btn.disabled = not enabled
	center_file_btn.disabled = not enabled
	env_prim_btn.disabled = not enabled
	scatter_prim_btn.disabled = not enabled
	center_prim_btn.disabled = not enabled
	if not enabled:
		env_label.text = "Environment"
		scatter_label.text = "Scatter"
		center_label.text = "Centerpiece"
		return
	var item: PlaylistItem = ShowDirector.items[idx]
	env_label.text = "Env: " + _short_layer(item.params.get("environment", {"source": "primitive:box_corridor"}))
	scatter_label.text = "Scatter: " + _short_layer(item.params.get("scatter", {"source": "primitive:cubes"}))
	center_label.text = "Center: " + _short_layer(item.params.get("centerpiece", {"source": "primitive:torus"}))


func _short_layer(config: Variant) -> String:
	if config is Dictionary:
		var d: Dictionary = config
		if d.has("path") and str(d["path"]).strip_edges() != "":
			return str(d["path"]).get_file()
		if d.has("source"):
			return str(d["source"]).replace("primitive:", "")
	return "?"


func _on_row_play(index: int) -> void:
	_selected_index = index
	ShowDirector.play_index(index, Transition.Mode.CUT, 0.0)


func _on_row_duration(value: float, index: int) -> void:
	if _rebuilding:
		return
	ShowDirector.set_item_duration(index, value)


func _on_row_delete(index: int) -> void:
	ShowDirector.remove_item_at(index)
	_selected_index = ShowDirector.current_index
	if ShowDirector.items.is_empty():
		item_label.text = "No item playing"
		ShowDirector.set_autoplay(false)
	_refresh_flythrough_section()


func _on_add_media() -> void:
	file_dialog.title = "Add Media (GIF / video / image / 3D)"
	file_dialog.popup_centered()


func _default_flythrough_params() -> Dictionary:
	return {
		"style": "flythrough",
		"speed": 2.0,
		"environment": {"source": "primitive:box_corridor"},
		"scatter": {"source": "primitive:cubes", "count": 36},
		"centerpiece": {"source": "primitive:torus"},
	}


func _on_add_env_id(id: int) -> void:
	if id == 1:
		ShowDirector.add_item_from_dict({
			"id": "stage",
			"type": "scene3d",
			"path": "",
			"duration": ShowDirector.default_item_duration,
			"params": {"style": "demo", "color": "#3366cc"},
		}, true)
		return
	ShowDirector.add_item_from_dict({
		"id": "flythrough",
		"type": "scene3d",
		"path": "",
		"duration": ShowDirector.default_item_duration,
		"params": _default_flythrough_params(),
	}, true)
	_selected_index = ShowDirector.current_index
	_refresh_flythrough_section()


func _pick_layer_file(layer_id: String) -> void:
	if _flythrough_index() < 0:
		return
	_layer_pick = layer_id
	layer_file_dialog.title = "Choose %s model" % layer_id
	layer_file_dialog.popup_centered()


func _on_layer_file_selected(path: String) -> void:
	var idx := _flythrough_index()
	if idx < 0 or _layer_pick.is_empty():
		return
	var resolved := MediaImport.to_project_or_absolute(path)
	var config: Dictionary = {"path": resolved}
	if _layer_pick == "scatter":
		config["count"] = 36
	ShowDirector.set_flythrough_layer(_layer_pick, config, idx)
	_layer_pick = ""
	_refresh_flythrough_section()


func _on_env_primitive(id: int) -> void:
	var src := "primitive:box_corridor" if id == 0 else "primitive:flat_plane"
	_apply_primitive("environment", {"source": src})


func _on_scatter_primitive(id: int) -> void:
	var src := "primitive:cubes" if id == 0 else "primitive:spheres"
	_apply_primitive("scatter", {"source": src, "count": 36})


func _on_center_primitive(id: int) -> void:
	var src := "primitive:torus" if id == 0 else "primitive:icosphere"
	_apply_primitive("centerpiece", {"source": src})


func _apply_primitive(layer_id: String, config: Dictionary) -> void:
	var idx := _flythrough_index()
	if idx < 0:
		return
	# Ensure style is flythrough when applying layers to legacy items.
	var item: PlaylistItem = ShowDirector.items[idx]
	item.params["style"] = "flythrough"
	ShowDirector.set_flythrough_layer(layer_id, config, idx)
	_refresh_flythrough_section()


func _on_file_selected(path: String) -> void:
	var data := MediaImport.build_item_dict(path, ShowDirector.default_item_duration)
	if data.is_empty():
		push_warning("Unsupported media: %s" % path)
		return
	ShowDirector.add_item_from_dict(data, true)


func _on_clear() -> void:
	ShowDirector.set_autoplay(false)
	ShowDirector.clear_playlist()
	_selected_index = -1
	item_label.text = "No item playing"
	_refresh_flythrough_section()
