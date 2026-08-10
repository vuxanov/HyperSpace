extends Control

## Control surface: assets | preview | effects.
## Present Mode opens a separate fullscreen window for the projector.

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


func _ready() -> void:
	ShowDirector.bind_output(output_stack, effect_stack)
	present_button.pressed.connect(toggle_present_mode)
	if playlist_sidebar.has_signal("present_requested"):
		playlist_sidebar.present_requested.connect(toggle_present_mode)
	_start_blank_stage()
	var win := get_window()
	win.size = Vector2i(1700, 950)
	win.min_size = Vector2i(1200, 700)


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
	_present_window.always_on_top = false
	# Prefer second monitor when available.
	var screen_idx := 1 if DisplayServer.get_screen_count() > 1 else 0
	var screen_pos := DisplayServer.screen_get_position(screen_idx)
	var screen_size := DisplayServer.screen_get_size(screen_idx)
	_present_window.position = screen_pos
	_present_window.size = screen_size
	_present_window.mode = Window.MODE_FULLSCREEN
	_present_rect = TextureRect.new()
	_present_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_present_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_present_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_present_rect.texture = output_viewport.get_texture()
	_present_window.add_child(_present_rect)
	get_tree().root.add_child(_present_window)
	_present_window.close_requested.connect(_close_present_window)
	_presenting = true
	present_button.text = "Close Present"


func _close_present_window() -> void:
	if _present_window != null:
		_present_window.queue_free()
		_present_window = null
		_present_rect = null
	_presenting = false
	present_button.text = "Present Mode"


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F11:
				toggle_present_mode()
			KEY_ESCAPE:
				if _presenting:
					_close_present_window()
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
