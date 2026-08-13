extends Control

## Performer control — left playlist editor, right effects / audio reactivity.

@onready var show_label: Label = $Root/Header/HeaderMargin/HeaderRow/ShowLabel
@onready var item_label: Label = $Root/Header/HeaderMargin/HeaderRow/ItemLabel
@onready var prev_button: Button = $Root/Header/HeaderMargin/HeaderRow/PrevButton
@onready var next_button: Button = $Root/Header/HeaderMargin/HeaderRow/NextButton

@onready var playlist_list: VBoxContainer = $Root/Body/PlaylistPane/PlaylistMargin/PlaylistColumn/PlaylistScroll/PlaylistList
@onready var add_env_button: Button = $Root/Body/PlaylistPane/PlaylistMargin/PlaylistColumn/AddRow/AddEnvButton
@onready var add_video_button: Button = $Root/Body/PlaylistPane/PlaylistMargin/PlaylistColumn/AddRow/AddVideoButton
@onready var add_image_button: Button = $Root/Body/PlaylistPane/PlaylistMargin/PlaylistColumn/AddRow/AddImageButton
@onready var play_selected_button: Button = $Root/Body/PlaylistPane/PlaylistMargin/PlaylistColumn/PlaylistActions/PlaySelectedButton
@onready var remove_button: Button = $Root/Body/PlaylistPane/PlaylistMargin/PlaylistColumn/PlaylistActions/RemoveButton
@onready var clear_button: Button = $Root/Body/PlaylistPane/PlaylistMargin/PlaylistColumn/PlaylistActions/ClearButton

@onready var intensity_slider: HSlider = $Root/Body/EffectsPane/EffectsMargin/EffectsColumn/AudioSection/IntensitySlider
@onready var sensitivity_slider: HSlider = $Root/Body/EffectsPane/EffectsMargin/EffectsColumn/AudioSection/SensitivitySlider
@onready var energy_bar: ProgressBar = $Root/Body/EffectsPane/EffectsMargin/EffectsColumn/AudioSection/EnergyBar
@onready var bass_bar: ProgressBar = $Root/Body/EffectsPane/EffectsMargin/EffectsColumn/AudioSection/BassBar

@onready var ascii_toggle: CheckButton = $Root/Body/EffectsPane/EffectsMargin/EffectsColumn/FxSection/AsciiToggle
@onready var ascii_density_slider: HSlider = $Root/Body/EffectsPane/EffectsMargin/EffectsColumn/FxSection/AsciiDensitySlider
@onready var particles_toggle: CheckButton = $Root/Body/EffectsPane/EffectsMargin/EffectsColumn/FxSection/ParticlesToggle
@onready var feedback_toggle: CheckButton = $Root/Body/EffectsPane/EffectsMargin/EffectsColumn/FxSection/FeedbackToggle
@onready var cue_container: HFlowContainer = $Root/Body/EffectsPane/EffectsMargin/EffectsColumn/CueSection/CueContainer

@onready var file_dialog: FileDialog = $FileDialog

var _selected_index: int = -1
var _pending_add_type: String = ""
var _file_pick_handled: bool = false
var _env_color_index: int = 0

const ENV_COLORS: Array[String] = [
	"#3366cc", "#cc6633", "#22aa88", "#aa3388", "#cccc33", "#4488ff"
]


func _ready() -> void:
	prev_button.pressed.connect(_on_prev)
	next_button.pressed.connect(_on_next)
	add_env_button.pressed.connect(_on_add_env)
	add_video_button.pressed.connect(_on_add_video)
	add_image_button.pressed.connect(_on_add_image)
	play_selected_button.pressed.connect(_on_play_selected)
	remove_button.pressed.connect(_on_remove)
	clear_button.pressed.connect(_on_clear)
	intensity_slider.value_changed.connect(_on_intensity_changed)
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	ascii_toggle.toggled.connect(_on_ascii_toggled)
	ascii_density_slider.value_changed.connect(_on_ascii_density_changed)
	particles_toggle.toggled.connect(_on_particles_toggled)
	feedback_toggle.toggled.connect(_on_feedback_toggled)
	file_dialog.file_selected.connect(_on_file_selected)
	file_dialog.files_selected.connect(_on_files_selected)
	ShowDirector.show_loaded.connect(_on_show_loaded)
	ShowDirector.item_changed.connect(_on_item_changed)
	ShowDirector.playlist_changed.connect(_rebuild_playlist)
	ShowDirector.cue_triggered.connect(_on_cue_triggered)
	AudioAnalyzer.state_updated.connect(_on_audio_state)
	_rebuild_playlist()
	_rebuild_cue_buttons()


func _on_show_loaded(show_name: String) -> void:
	show_label.text = show_name
	_rebuild_playlist()
	_rebuild_cue_buttons()


func _on_item_changed(item_id: String, index: int) -> void:
	_selected_index = index
	item_label.text = "Playing: %s" % item_id
	_rebuild_playlist()


func _on_cue_triggered(cue_id: String) -> void:
	item_label.text = "Cue: %s" % cue_id


func _on_audio_state(state: AudioState) -> void:
	energy_bar.value = clampf(state.energy, 0.0, 1.0)
	bass_bar.value = clampf(state.bass, 0.0, 1.0)


func _rebuild_playlist() -> void:
	for child in playlist_list.get_children():
		child.queue_free()
	for i in ShowDirector.items.size():
		var item: PlaylistItem = ShowDirector.items[i]
		var row := Button.new()
		row.text = "%d. [%s]  %s" % [i + 1, item.type, item.id]
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.toggle_mode = true
		row.button_pressed = (i == _selected_index) or (i == ShowDirector.current_index)
		row.pressed.connect(_on_playlist_row_pressed.bind(i))
		playlist_list.add_child(row)


func _rebuild_cue_buttons() -> void:
	for child in cue_container.get_children():
		child.queue_free()
	for cue in ShowDirector.cues:
		if cue is Dictionary:
			var cue_id := str(cue.get("id", ""))
			var btn := Button.new()
			btn.text = cue_id
			btn.custom_minimum_size = Vector2(96, 36)
			btn.pressed.connect(_on_cue_pressed.bind(cue_id))
			cue_container.add_child(btn)


func _on_playlist_row_pressed(index: int) -> void:
	_selected_index = index
	_rebuild_playlist()


func _on_play_selected() -> void:
	if _selected_index >= 0:
		ShowDirector.play_index(_selected_index, Transition.Mode.CROSSFADE, 1.0)


func _on_prev() -> void:
	ShowDirector.prev_item()


func _on_next() -> void:
	ShowDirector.next_item()


func _on_add_env() -> void:
	var color: String = ENV_COLORS[_env_color_index % ENV_COLORS.size()]
	_env_color_index += 1
	ShowDirector.add_item_from_dict({
		"id": "env",
		"type": "scene3d",
		"path": "",
		"params": {"color": color},
	}, true)


func _on_add_video() -> void:
	_pending_add_type = "video"
	_file_pick_handled = false
	file_dialog.title = "Add Video / GIF"
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_dialog.filters = PackedStringArray([
		"*.webm,*.mp4,*.ogv,*.mov,*.avi,*.gif ; Video & GIF",
		"*.gif ; GIF",
	])
	file_dialog.popup_centered()


func _on_add_image() -> void:
	_pending_add_type = "image"
	_file_pick_handled = false
	file_dialog.title = "Add Image / GIF"
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_dialog.filters = PackedStringArray([
		"*.png,*.jpg,*.jpeg,*.svg,*.webp,*.bmp,*.gif ; Images & GIF",
	])
	file_dialog.popup_centered()


func _on_file_selected(path: String) -> void:
	_on_files_selected(PackedStringArray([path]))


func _on_files_selected(paths: PackedStringArray) -> void:
	if _file_pick_handled or _pending_add_type.is_empty() or paths.is_empty():
		return
	_file_pick_handled = true
	var add_type := _pending_add_type
	_pending_add_type = ""
	for path in paths:
		var item := MediaImport.build_item_dict(path)
		if item.is_empty():
			# Fallback for forced type from button.
			var res_path := MediaImport.to_project_or_absolute(path)
			item = {
				"id": path.get_file().get_basename(),
				"type": add_type,
				"path": res_path,
				"loop": add_type == "video",
			}
		elif add_type == "image" and str(item.get("type", "")) == "video":
			# Keep GIF→video when adding from image button if converted.
			pass
		ShowDirector.add_item_from_dict(item, path == paths[paths.size() - 1])


func _on_remove() -> void:
	var index := _selected_index
	if index < 0:
		index = ShowDirector.current_index
	if index >= 0:
		ShowDirector.remove_item_at(index)
		_selected_index = ShowDirector.current_index


func _on_clear() -> void:
	ShowDirector.clear_playlist()
	_selected_index = -1
	item_label.text = "No item playing"


func _on_cue_pressed(cue_id: String) -> void:
	ShowDirector.trigger_cue(cue_id)


func _on_intensity_changed(value: float) -> void:
	AudioAnalyzer.master_intensity = value


func _on_sensitivity_changed(value: float) -> void:
	AudioAnalyzer.band_sensitivity = value


func _on_ascii_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("ascii", enabled, {
		"intensity": intensity_slider.value,
		"density": ascii_density_slider.value,
	})


func _on_ascii_density_changed(value: float) -> void:
	if ascii_toggle.button_pressed:
		ShowDirector.set_effect("ascii", true, {
			"intensity": intensity_slider.value,
			"density": value,
		})


func _on_particles_toggled(_enabled: bool) -> void:
	pass


func _on_feedback_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("feedback", enabled, {"intensity": intensity_slider.value})
