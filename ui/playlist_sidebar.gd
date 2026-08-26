extends PanelContainer

## Left sidebar — icon tabs for Env / Main / Scatter / Lighting with independent timers.

signal present_requested

const TAB_ENV := 0
const TAB_MAIN := 1
const TAB_SCATTER := 2
const TAB_LIGHT := 3
const _AssetCache := preload("res://core/asset_cache.gd")
const _BootCache := preload("res://core/boot_cache.gd")
const SliderSpinLinkScr := preload("res://ui/slider_spin_link.gd")
const CycleRandomScr := preload("res://ui/cycle_random.gd")

@onready var show_label: Label = $Margin/Column/Header/ShowLabel
@onready var status_label: Label = $Margin/Column/Header/StatusLabel
@onready var fly_speed: SpinBox = $Margin/Column/Header/FlyRow/FlySpeed
@onready var path_style: OptionButton = $Margin/Column/Header/PathRow/PathStyle
@onready var reset_defaults_btn: Button = $Margin/Column/Header/ResetDefaultsBtn
@onready var asset_tabs: TabContainer = $Margin/Column/AssetTabs

@onready var env_list: VBoxContainer = $Margin/Column/AssetTabs/Environments/EnvScroll/EnvList
@onready var main_list: VBoxContainer = $"Margin/Column/AssetTabs/Main character/MainScroll/MainList"
@onready var scatter_list: VBoxContainer = $Margin/Column/AssetTabs/Scattering/ScatterScroll/ScatterList
@onready var light_list: VBoxContainer = $Margin/Column/AssetTabs/Lighting/LightScroll/LightList

@onready var env_file_btn: Button = $Margin/Column/AssetTabs/Environments/EnvAddRow/EnvFileBtn
@onready var main_file_btn: Button = $"Margin/Column/AssetTabs/Main character/MainAddRow/MainFileBtn"
@onready var scatter_file_btn: Button = $Margin/Column/AssetTabs/Scattering/ScatterAddRow/ScatterFileBtn

@onready var env_play_btn: Button = $Margin/Column/AssetTabs/Environments/EnvControls/EnvPlayBtn
@onready var main_play_btn: Button = $"Margin/Column/AssetTabs/Main character/MainControls/MainPlayBtn"
@onready var scatter_play_btn: Button = $Margin/Column/AssetTabs/Scattering/ScatterControls/ScatterPlayBtn
@onready var light_play_btn: Button = $Margin/Column/AssetTabs/Lighting/LightControls/LightPlayBtn

@onready var env_duration: SpinBox = $Margin/Column/AssetTabs/Environments/EnvControls/EnvDuration
@onready var env_scale: SpinBox = $Margin/Column/AssetTabs/Environments/EnvScaleRow/EnvScale
@onready var main_duration: SpinBox = $"Margin/Column/AssetTabs/Main character/MainControls/MainDuration"
@onready var scatter_duration: SpinBox = $Margin/Column/AssetTabs/Scattering/ScatterControls/ScatterDuration
@onready var scatter_layout: OptionButton = $Margin/Column/AssetTabs/Scattering/ScatterLayoutRow/ScatterLayout
@onready var scatter_density: SpinBox = $Margin/Column/AssetTabs/Scattering/ScatterDensityRow/ScatterDensity
@onready var scatter_global_scale: SpinBox = $Margin/Column/AssetTabs/Scattering/ScatterGlobalScaleRow/ScatterGlobalScale
@onready var light_duration: SpinBox = $Margin/Column/AssetTabs/Lighting/LightControls/LightDuration

@onready var clear_button: Button = $Margin/Column/ClearButton
@onready var layer_file_dialog: FileDialog = $LayerFileDialog

## Working asset lists per category (catalog + user File adds).
var _env_entries: Array[Dictionary] = []
var _main_entries: Array[Dictionary] = []
var _scatter_entries: Array[Dictionary] = []
var _light_entries: Array[Dictionary] = []
## Selected index per category (-1 = none).
var _sel_env: int = -1
var _sel_main: int = -1
var _sel_scatter: int = -1
var _sel_light: int = -1
## Independent autoplay per category.
var _autoplay: Array[bool] = [false, false, false, false]
var _shuffle_slots: Dictionary = {}
var _elapsed: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _layer_pick: String = ""  # environment | scatter | centerpiece | replace_*
var _replace_tab: int = -1
var _replace_index: int = -1
var _file_pick_handled: bool = false
var _rebuilding: bool = false
## Avoid full list rebuild storms while applying a layer (playlist_changed fires from ShowDirector).
var _suppress_playlist_ui: bool = false
## Debounced autosave of playlist + stage session.
var _autosave_timer: Timer
var _restoring_session: bool = false
var _session_restored: bool = false
## Full playlist precache before Play / after show load.
var _warming: bool = false
var _warm_paths: Array = []
var _warm_total: int = 0
var _warm_done: int = 0
var _pending_play_tab: int = -1
var _warm_ready: bool = false
const WARM_GIF_PER_FRAME := 1
const WARM_TIMEOUT_SEC := 90.0
var _warm_elapsed: float = 0.0
## Edit-item modal (rename / replace / scale / offset).
var _edit_dialog: AcceptDialog
var _edit_name: LineEdit
var _edit_asset_label: Label
var _edit_replace_btn: Button
var _edit_scale_row: HBoxContainer
var _edit_scale_slider: HSlider
var _edit_scale_spin: SpinBox
var _edit_offset_box: VBoxContainer
var _edit_offset_x: HSlider
var _edit_offset_y: HSlider
var _edit_offset_z: HSlider
var _edit_tab: int = -1
var _edit_index: int = -1
var _edit_scale_busy: bool = false
var _edit_offset_busy: bool = false
var _edit_from_modal_replace: bool = false
var _edit_tile_box: HBoxContainer
var _edit_tile_x: SpinBox
var _edit_tile_y: SpinBox
var _edit_tile_z: SpinBox
var _edit_tile_hint: Label
var _edit_tile_busy: bool = false
var _edit_mat_row: HBoxContainer
var _edit_mat_opt: OptionButton
var _edit_mat_busy: bool = false
var _edit_blend_row: HBoxContainer
var _edit_blend_opt: OptionButton
var _edit_blend_busy: bool = false
## Avoid scatter rebuild when restoring/syncing layout+density UI.
var _scatter_settings_busy: bool = false
var _env_tile_x: SpinBox
var _env_tile_y: SpinBox
var _env_tile_z: SpinBox
var _env_tile_hint: Label
var _env_tile_busy: bool = false


func _ready() -> void:
	clear_button.pressed.connect(_on_clear)
	if reset_defaults_btn:
		reset_defaults_btn.pressed.connect(_on_reset_to_defaults)
		reset_defaults_btn.tooltip_text = "Reset every left-panel customization (scale, offset, grid, material, blend, scatter, path) plus effects. Playlist assets stay."
	ShowDirector.stage_defaults_restored.connect(_sync_fly_speed_from_stage)
	ShowDirector.stage_defaults_restored.connect(_sync_path_style_from_stage)
	ShowDirector.stage_defaults_restored.connect(_sync_scatter_settings_from_stage)
	ShowDirector.stage_defaults_restored.connect(_sync_env_scale_from_stage)
	ShowDirector.stage_defaults_restored.connect(_sync_env_tiles_from_stage)
	env_file_btn.pressed.connect(func() -> void: _pick_layer_file("environment"))
	main_file_btn.pressed.connect(func() -> void: _pick_layer_file("centerpiece"))
	scatter_file_btn.pressed.connect(func() -> void: _pick_layer_file("scatter"))
	var light_file_btn: Button = $Margin/Column/AssetTabs/Lighting/LightAddRow/LightFileBtn
	if light_file_btn:
		light_file_btn.disabled = false
		light_file_btn.tooltip_text = "Add an HDR / EXR panorama for IBL lighting"
		light_file_btn.pressed.connect(func() -> void: _pick_layer_file("lighting"))
	env_play_btn.pressed.connect(func() -> void: _toggle_tab_autoplay(TAB_ENV))
	main_play_btn.pressed.connect(func() -> void: _toggle_tab_autoplay(TAB_MAIN))
	scatter_play_btn.pressed.connect(func() -> void: _toggle_tab_autoplay(TAB_SCATTER))
	light_play_btn.pressed.connect(func() -> void: _toggle_tab_autoplay(TAB_LIGHT))
	_fill_path_style_options()
	_fill_scatter_layout_options()
	_setup_preset_shuffles()
	SliderSpinLinkScr.replace_spin_with_driven(fly_speed, func(_v: float = 0.0) -> void:
		_on_fly_speed_changed(SliderSpinLinkScr.eval_spin(fly_speed))
	, 1.0, 0.0, 40.0)
	SliderSpinLinkScr.replace_spin_with_driven(env_scale, func(_v: float = 0.0) -> void:
		_on_env_scale_changed(SliderSpinLinkScr.eval_spin(env_scale))
	, 1.0, 0.0, 10.0)
	if scatter_density:
		SliderSpinLinkScr.replace_spin_with_driven(scatter_density, func(_v: float = 0.0) -> void:
			_on_scatter_density_changed(SliderSpinLinkScr.eval_spin(scatter_density))
		, 1.0, 1.0, 2000.0)
	if scatter_global_scale:
		SliderSpinLinkScr.replace_spin_with_driven(scatter_global_scale, func(_v: float = 0.0) -> void:
			_on_scatter_global_scale_changed(SliderSpinLinkScr.eval_spin(scatter_global_scale))
		, 1.0, 0.1, 5.0)
	SliderSpinLinkScr.replace_spin_with_driven(env_duration, func(_v: float = 0.0) -> void: _schedule_autosave(), 1.0, 1.0, 60.0)
	SliderSpinLinkScr.replace_spin_with_driven(main_duration, func(_v: float = 0.0) -> void: _schedule_autosave(), 1.0, 1.0, 60.0)
	SliderSpinLinkScr.replace_spin_with_driven(scatter_duration, func(_v: float = 0.0) -> void: _schedule_autosave(), 1.0, 1.0, 60.0)
	SliderSpinLinkScr.replace_spin_with_driven(light_duration, func(_v: float = 0.0) -> void: _schedule_autosave(), 1.0, 1.0, 60.0)
	if status_label:
		status_label.visible = false
		status_label.text = ""
	if path_style:
		path_style.item_selected.connect(_on_path_style_selected)
	if scatter_layout:
		scatter_layout.item_selected.connect(_on_scatter_layout_selected)
	layer_file_dialog.file_selected.connect(_on_layer_file_selected)
	layer_file_dialog.files_selected.connect(_on_layer_files_selected)
	ShowDirector.show_loaded.connect(_on_show_loaded)
	ShowDirector.item_changed.connect(_on_item_changed)
	ShowDirector.playlist_changed.connect(_on_playlist_changed)
	_setup_autosave_timer()
	_setup_edit_dialog()
	_hide_env_panel_extras()
	_setup_tab_icons()
	_load_catalog_entries()
	_restore_sidebar_from_session()
	_rebuild_all_lists()
	_refresh_status()
	_sync_fly_speed_from_stage()
	_sync_path_style_from_stage()
	_sync_env_scale_from_stage()
	_sync_env_tiles_from_stage()
	_sync_scatter_settings_from_stage()
	_update_all_play_buttons()
	_start_warm_all(-1)
	set_process(true)


func _notification(what: int) -> void:
	# Prefer Main window close_requested + debounced autosave; EXIT_TREE is unsafe
	# because child SpinBoxes may already be freed.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_session_now()


func _setup_autosave_timer() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = 0.35
	_autosave_timer.one_shot = true
	_autosave_timer.timeout.connect(_save_session_now)
	add_child(_autosave_timer)


func _setup_edit_dialog() -> void:
	_edit_dialog = AcceptDialog.new()
	_edit_dialog.title = "Edit item"
	_edit_dialog.min_size = Vector2i(440, 560)
	_edit_dialog.ok_button_text = "Done"
	_edit_dialog.dialog_hide_on_ok = true
	add_child(_edit_dialog)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_edit_dialog.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var name_lbl := Label.new()
	name_lbl.text = "Name"
	col.add_child(name_lbl)
	_edit_name = LineEdit.new()
	_edit_name.placeholder_text = "Display name"
	col.add_child(_edit_name)

	var asset_lbl := Label.new()
	asset_lbl.text = "Asset"
	col.add_child(asset_lbl)
	var asset_row := HBoxContainer.new()
	asset_row.add_theme_constant_override("separation", 8)
	col.add_child(asset_row)
	_edit_asset_label = Label.new()
	_edit_asset_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_asset_label.clip_text = true
	_edit_asset_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	asset_row.add_child(_edit_asset_label)
	_edit_replace_btn = Button.new()
	_edit_replace_btn.text = "Replace…"
	_edit_replace_btn.tooltip_text = "Choose another file for this item"
	_edit_replace_btn.pressed.connect(_on_edit_replace_pressed)
	asset_row.add_child(_edit_replace_btn)

	_edit_scale_row = HBoxContainer.new()
	_edit_scale_row.add_theme_constant_override("separation", 8)
	col.add_child(_edit_scale_row)
	var scale_lbl := Label.new()
	scale_lbl.text = "Scale"
	_edit_scale_row.add_child(scale_lbl)
	_edit_scale_slider = HSlider.new()
	_edit_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_scale_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_edit_scale_slider.min_value = 0.1
	_edit_scale_slider.max_value = 20.0
	_edit_scale_slider.step = 0.1
	_edit_scale_row.add_child(_edit_scale_slider)
	SliderSpinLinkScr.attach_driven(_edit_scale_slider, func(_v: float = 0.0) -> void:
		if _edit_scale_busy:
			return
		_commit_edit_scale()
	, 1.0)

	_edit_offset_box = VBoxContainer.new()
	_edit_offset_box.add_theme_constant_override("separation", 6)
	col.add_child(_edit_offset_box)
	_edit_offset_x = _make_edit_offset_slider(_edit_offset_box, "Offset X")
	_edit_offset_y = _make_edit_offset_slider(_edit_offset_box, "Offset Y")
	_edit_offset_z = _make_edit_offset_slider(_edit_offset_box, "Offset Z")
	_edit_offset_y.tooltip_text = "Move this item up/down so it does not clip through the environment."
	_edit_offset_x.tooltip_text = "Move this item left/right in world space."
	_edit_offset_z.tooltip_text = "Move this item forward/back in world space. For the main item this is camera depth."

	_edit_tile_box = HBoxContainer.new()
	_edit_tile_box.add_theme_constant_override("separation", 8)
	col.add_child(_edit_tile_box)
	var tile_lbl := Label.new()
	tile_lbl.text = "Grid"
	tile_lbl.custom_minimum_size = Vector2(72, 0)
	tile_lbl.tooltip_text = "Full environment grid including corners. Integers 1–100 per axis. 2×2 = 4 meshes. Spawn caps at %d." % FlythroughAssetCatalog.ENV_TILE_INSTANCE_MAX
	_edit_tile_box.add_child(tile_lbl)
	_edit_tile_x = _make_edit_tile_spin("X")
	_edit_tile_y = _make_edit_tile_spin("Y")
	_edit_tile_z = _make_edit_tile_spin("Z")
	_edit_tile_box.add_child(_edit_tile_x)
	_edit_tile_box.add_child(_edit_tile_y)
	_edit_tile_box.add_child(_edit_tile_z)
	_edit_tile_hint = Label.new()
	_edit_tile_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_edit_tile_hint.add_theme_font_size_override("font_size", 12)
	col.add_child(_edit_tile_hint)

	_edit_mat_row = HBoxContainer.new()
	_edit_mat_row.name = "EditMatOverrideRow"
	_edit_mat_row.add_theme_constant_override("separation", 8)
	_edit_mat_row.visible = false
	col.add_child(_edit_mat_row)
	var mat_lbl := Label.new()
	mat_lbl.text = "Material"
	mat_lbl.custom_minimum_size = Vector2(72, 0)
	mat_lbl.tooltip_text = "Replace this 3D object's materials with the same looks as Effects → Material Override. Off keeps the original."
	_edit_mat_row.add_child(mat_lbl)
	_edit_mat_opt = OptionButton.new()
	_edit_mat_opt.name = "EditMatOverride"
	_edit_mat_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_mat_opt.add_item("Off")
	for look_n in MaterialOverrideEffect.LOOK_NAMES:
		_edit_mat_opt.add_item(str(look_n))
	_edit_mat_opt.select(0)
	_edit_mat_opt.tooltip_text = "White cladding, Chrome, Gold, Normal (normal map), Shiny black. Off restores this item's originals."
	_edit_mat_opt.item_selected.connect(func(_i: int) -> void:
		if _edit_mat_busy:
			return
		_commit_edit_mat_override()
	)
	_edit_mat_row.add_child(_edit_mat_opt)

	_edit_blend_row = HBoxContainer.new()
	_edit_blend_row.name = "EditBlendRow"
	_edit_blend_row.add_theme_constant_override("separation", 8)
	_edit_blend_row.visible = false
	col.add_child(_edit_blend_row)
	var blend_lbl := Label.new()
	blend_lbl.text = "Blend"
	blend_lbl.custom_minimum_size = Vector2(72, 0)
	blend_lbl.tooltip_text = "How this image / GIF / video composites with the scene (Photoshop-style)."
	_edit_blend_row.add_child(blend_lbl)
	_edit_blend_opt = OptionButton.new()
	_edit_blend_opt.name = "EditBlendMode"
	_edit_blend_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for blend_n in FlythroughMediaProp.BLEND_NAMES:
		_edit_blend_opt.add_item(str(blend_n))
	_edit_blend_opt.select(0)
	_edit_blend_opt.tooltip_text = "Normal, Multiply, Overlay, Screen, Add, Subtract, Premultiplied."
	_edit_blend_opt.item_selected.connect(func(_i: int) -> void:
		if _edit_blend_busy:
			return
		_commit_edit_blend()
	)
	_edit_blend_row.add_child(_edit_blend_opt)

	_edit_dialog.confirmed.connect(_on_edit_dialog_confirmed)
	_edit_dialog.canceled.connect(_on_edit_dialog_closed)
	_edit_dialog.visibility_changed.connect(func() -> void:
		if _edit_dialog != null and not _edit_dialog.visible:
			_commit_edit_scale()
			_commit_edit_offset()
			_commit_edit_tiles()
			_commit_edit_mat_override()
			_commit_edit_blend()
	)


func _is_scale_expr(raw: Variant) -> bool:
	if raw == null or not (raw is String):
		return false
	var t := str(raw).strip_edges()
	return not t.is_empty() and not t.is_valid_float()


func _eval_driven_value(raw: Variant, fallback: float = 1.0) -> float:
	var hub := get_node_or_null("/root/DriverHub")
	if hub != null and hub.has_method("eval_value"):
		return float(hub.call("eval_value", raw, fallback))
	if raw is float or raw is int:
		return float(raw)
	if raw is String and str(raw).strip_edges().is_valid_float():
		return str(raw).strip_edges().to_float()
	return fallback


func _entry_scale_snapshot(entry: Dictionary) -> float:
	if entry.has("user_scale") and not _is_scale_expr(entry["user_scale"]):
		return maxf(float(entry["user_scale"]), 0.0)
	var cfg: Dictionary = entry.get("config", {}) as Dictionary
	if cfg.has("user_scale") and not _is_scale_expr(cfg["user_scale"]):
		return maxf(float(cfg["user_scale"]), 0.0)
	if cfg.has("scale"):
		return maxf(float(cfg["scale"]), 0.0)
	return 1.0


func _entry_scale_expr(entry: Dictionary) -> String:
	var e := ""
	if entry.has("user_scale_expr"):
		e = str(entry["user_scale_expr"]).strip_edges()
	if e.is_empty():
		var cfg: Dictionary = entry.get("config", {}) as Dictionary
		if cfg.has("user_scale_expr"):
			e = str(cfg["user_scale_expr"]).strip_edges()
	if e.is_empty() and _is_scale_expr(entry.get("user_scale", null)):
		e = str(entry["user_scale"]).strip_edges()
	if e.is_empty():
		var cfg2: Dictionary = entry.get("config", {}) as Dictionary
		if _is_scale_expr(cfg2.get("user_scale", null)):
			e = str(cfg2["user_scale"]).strip_edges()
	if e.is_empty() or e.is_valid_float():
		return ""
	return e


func _entry_scale_raw(entry: Dictionary) -> Variant:
	var expr := _entry_scale_expr(entry)
	if not expr.is_empty():
		return expr
	return _entry_scale_snapshot(entry)


func _entry_user_scale(entry: Dictionary) -> float:
	var snapshot := _entry_scale_snapshot(entry)
	var expr := _entry_scale_expr(entry)
	if not expr.is_empty():
		return maxf(_eval_driven_value(expr, snapshot), 0.0)
	return snapshot


func _set_entry_user_scale(entry: Dictionary, scale_val: float, scale_raw: Variant = null) -> void:
	var expr := ""
	if scale_raw == null:
		expr = _entry_scale_expr(entry)
	elif _is_scale_expr(scale_raw):
		expr = str(scale_raw).strip_edges()
	var s: float
	if expr.is_empty():
		s = maxf(scale_val, 0.0)
	else:
		# Live eval must not ratchet/reset the stored numeric base.
		s = _entry_scale_snapshot(entry)
		if s <= 0.0:
			s = 1.0
	entry["user_scale"] = s
	var cfg: Dictionary = (entry.get("config", {}) as Dictionary).duplicate(true)
	cfg["user_scale"] = s
	if expr.is_empty():
		entry.erase("user_scale_expr")
		cfg.erase("user_scale_expr")
	else:
		entry["user_scale_expr"] = expr
		cfg["user_scale_expr"] = expr
	entry["config"] = cfg


func _stamp_scale_on_cfg(cfg: Dictionary, entry: Dictionary, scale_val: float) -> void:
	var expr := _entry_scale_expr(entry)
	if expr.is_empty():
		cfg["user_scale"] = maxf(scale_val, 0.0)
		cfg.erase("user_scale_expr")
	else:
		var base := _entry_scale_snapshot(entry)
		cfg["user_scale"] = base if base > 0.0 else 1.0
		cfg["user_scale_expr"] = expr


func _make_edit_offset_slider(parent: VBoxContainer, title: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = title
	lbl.custom_minimum_size = Vector2(72, 0)
	row.add_child(lbl)
	var sl := HSlider.new()
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.min_value = -80.0
	sl.max_value = 80.0
	sl.step = 0.1
	sl.value = 0.0
	row.add_child(sl)
	SliderSpinLinkScr.attach_driven(sl, func(_v: float = 0.0) -> void:
		if _edit_offset_busy:
			return
		_commit_edit_offset()
	, 1.0)
	return sl


func _entry_user_offset(entry: Dictionary) -> Vector3:
	var raw: Variant = entry.get("user_offset", null)
	if raw == null:
		var cfg: Dictionary = entry.get("config", {}) as Dictionary
		raw = cfg.get("user_offset", {})
	if raw is Vector3:
		return raw as Vector3
	if raw is Dictionary:
		var d: Dictionary = raw
		return Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))
	return Vector3.ZERO


func _offset_to_dict(offset: Vector3) -> Dictionary:
	return {"x": offset.x, "y": offset.y, "z": offset.z}


func _set_entry_user_offset(entry: Dictionary, offset: Vector3) -> void:
	var d := _offset_to_dict(offset)
	entry["user_offset"] = d
	var cfg: Dictionary = entry.get("config", {}) as Dictionary
	if cfg.is_empty():
		entry["config"] = {"user_offset": d}
		return
	cfg["user_offset"] = d


func _stamp_offset_on_cfg(cfg: Dictionary, entry: Dictionary) -> void:
	cfg["user_offset"] = _offset_to_dict(_entry_user_offset(entry))


func _entry_source_path(entry: Dictionary) -> String:
	var cfg: Dictionary = entry.get("config", {}) as Dictionary
	return FlythroughLayerSlot.resolve_source_string(cfg)


func _entry_is_media(entry: Dictionary) -> bool:
	return FlythroughLayerSlot.is_media_path(_entry_source_path(entry))


func _entry_shows_mat_override(tab: int, entry: Dictionary) -> bool:
	if tab == TAB_LIGHT:
		return false
	return not _entry_is_media(entry)


func _entry_shows_blend(tab: int, entry: Dictionary) -> bool:
	if tab == TAB_LIGHT:
		return false
	return _entry_is_media(entry)


func _entry_mat_override(entry: Dictionary) -> String:
	var raw: Variant = entry.get("mat_override", null)
	if raw == null:
		var cfg: Dictionary = entry.get("config", {}) as Dictionary
		raw = cfg.get("mat_override", cfg.get("material_override", ""))
	return SceneMeshFx.layer_mat_override_look({"mat_override": raw})


func _set_entry_mat_override(entry: Dictionary, look: String) -> void:
	var n := str(look).strip_edges()
	if n.is_empty() or n.to_lower() == "off" or n.to_lower() == "none":
		entry.erase("mat_override")
		var cfg_off: Dictionary = (entry.get("config", {}) as Dictionary).duplicate(true)
		cfg_off.erase("mat_override")
		cfg_off.erase("material_override")
		entry["config"] = cfg_off
		return
	var look_n := MaterialOverrideEffect.normalize_look(n)
	entry["mat_override"] = look_n
	var cfg: Dictionary = (entry.get("config", {}) as Dictionary).duplicate(true)
	cfg["mat_override"] = look_n
	entry["config"] = cfg


func _stamp_mat_override_on_cfg(cfg: Dictionary, entry: Dictionary) -> void:
	var look := _entry_mat_override(entry)
	if look.is_empty():
		cfg.erase("mat_override")
		cfg.erase("material_override")
	else:
		cfg["mat_override"] = look


func _entry_blend_mode(entry: Dictionary) -> String:
	var raw: Variant = entry.get("blend_mode", null)
	if raw == null:
		var cfg: Dictionary = entry.get("config", {}) as Dictionary
		raw = cfg.get("blend_mode", "Normal")
	return FlythroughMediaProp.normalize_blend(raw)


func _set_entry_blend_mode(entry: Dictionary, blend: String) -> void:
	var n := FlythroughMediaProp.normalize_blend(blend)
	entry["blend_mode"] = n
	var cfg: Dictionary = (entry.get("config", {}) as Dictionary).duplicate(true)
	cfg["blend_mode"] = n
	entry["config"] = cfg


func _stamp_blend_on_cfg(cfg: Dictionary, entry: Dictionary) -> void:
	if not _entry_is_media(entry):
		return
	cfg["blend_mode"] = _entry_blend_mode(entry)


func _layer_id_for_tab(tab: int) -> String:
	match tab:
		TAB_MAIN:
			return "centerpiece"
		TAB_SCATTER:
			return "scatter"
		_:
			return "environment"


func _sync_edit_mat_blend_rows(tab: int, entry: Dictionary) -> void:
	var show_mat := _entry_shows_mat_override(tab, entry)
	var show_blend := _entry_shows_blend(tab, entry)
	if _edit_mat_row:
		_edit_mat_row.visible = show_mat
	if _edit_blend_row:
		_edit_blend_row.visible = show_blend
	if show_mat and _edit_mat_opt:
		_edit_mat_busy = true
		var look := _entry_mat_override(entry)
		var idx := 0
		if not look.is_empty():
			var found := MaterialOverrideEffect.LOOK_NAMES.find(look)
			if found >= 0:
				idx = found + 1
		_edit_mat_opt.select(idx)
		_edit_mat_busy = false
	if show_blend and _edit_blend_opt:
		_edit_blend_busy = true
		var blend := _entry_blend_mode(entry)
		var bidx := FlythroughMediaProp.BLEND_NAMES.find(blend)
		_edit_blend_opt.select(bidx if bidx >= 0 else 0)
		_edit_blend_busy = false


func _make_edit_tile_spin(axis: String) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = 1
	sp.max_value = FlythroughAssetCatalog.ENV_TILE_GRID_MAX
	sp.step = 1
	sp.value = 3 if axis != "Y" else 1
	sp.prefix = axis
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.tooltip_text = "Cells along %s (1–%d). X=3 and Z=3 is a 3×3 ground grid — 9 meshes including corners. Spawn caps at %d meshes total." % [axis, FlythroughAssetCatalog.ENV_TILE_GRID_MAX, FlythroughAssetCatalog.ENV_TILE_INSTANCE_MAX]
	sp.value_changed.connect(func(_v: float) -> void:
		if _edit_tile_busy:
			return
		_commit_edit_tiles()
	)
	return sp


func _hide_env_panel_extras() -> void:
	## Env tab: no helper prose, no global Env scale. Grid stays in per-item Edit.
	var scale_row: Control = get_node_or_null("Margin/Column/AssetTabs/Environments/EnvScaleRow") as Control
	if scale_row:
		scale_row.visible = false
	var hint: Label = get_node_or_null("Margin/Column/AssetTabs/Environments/EnvHint") as Label
	if hint:
		hint.visible = false
		hint.text = ""


func _setup_env_tile_controls() -> void:
	## Grid lives in per-item Edit only — do not add a duplicate row on the env tab.
	return


func _make_sidebar_tile_spin(axis: String) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = 1
	sp.max_value = FlythroughAssetCatalog.ENV_TILE_GRID_MAX
	sp.step = 1
	sp.value = 3 if axis != "Y" else 1
	sp.prefix = axis
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.tooltip_text = "Cells along %s (1–%d). X=3 and Z=3 is a 3×3 ground grid — 9 meshes including corners. Spawn caps at %d meshes total." % [axis, FlythroughAssetCatalog.ENV_TILE_GRID_MAX, FlythroughAssetCatalog.ENV_TILE_INSTANCE_MAX]
	sp.value_changed.connect(func(_v: float) -> void: _on_env_tile_changed())
	return sp


func _sidebar_tile_counts() -> Vector3i:
	return Vector3i(
		_spin_tile_count(_env_tile_x),
		_spin_tile_count(_env_tile_y),
		_spin_tile_count(_env_tile_z)
	)


func _spin_tile_count(sp: SpinBox) -> int:
	if sp == null:
		return 1
	return FlythroughAssetCatalog.clamp_env_tile_count(sp.value)


func _env_tile_grid_label(counts: Vector3i) -> String:
	var gx: int = FlythroughAssetCatalog.clamp_env_tile_count(counts.x)
	var gy: int = FlythroughAssetCatalog.clamp_env_tile_count(counts.y)
	var gz: int = FlythroughAssetCatalog.clamp_env_tile_count(counts.z)
	var n: int = gx * gy * gz
	if gy <= 1:
		return "%d×%d = %d" % [gx, gz, n]
	return "%d×%d×%d = %d" % [gx, gy, gz, n]


func _env_tile_hint_text(counts: Vector3i) -> String:
	var requested := _env_tile_grid_label(counts)
	var spawn := FlythroughAssetCatalog.env_tile_counts_for_spawn(counts)
	var clamped := Vector3i(
		FlythroughAssetCatalog.clamp_env_tile_count(counts.x),
		FlythroughAssetCatalog.clamp_env_tile_count(counts.y),
		FlythroughAssetCatalog.clamp_env_tile_count(counts.z)
	)
	if spawn == clamped:
		return requested
	return "%s → %s (max %d meshes)" % [requested, _env_tile_grid_label(spawn), FlythroughAssetCatalog.ENV_TILE_INSTANCE_MAX]


func _refresh_edit_tile_hint(counts: Vector3i) -> void:
	if _edit_tile_hint == null or not is_instance_valid(_edit_tile_hint):
		return
	_edit_tile_hint.text = _env_tile_hint_text(counts)


func _entry_has_tiles(entry: Dictionary) -> bool:
	if entry.has("tile_x") or entry.has("tile_y") or entry.has("tile_z"):
		return true
	var cfg: Dictionary = entry.get("config", {}) as Dictionary
	return cfg.has("tile_x") or cfg.has("tile_y") or cfg.has("tile_z")


func _entry_tile_counts(entry: Dictionary) -> Vector3i:
	var cfg: Dictionary = entry.get("config", {}) as Dictionary
	var merged: Dictionary = cfg.duplicate()
	if entry.has("tile_x"):
		merged["tile_x"] = entry["tile_x"]
	if entry.has("tile_y"):
		merged["tile_y"] = entry["tile_y"]
	if entry.has("tile_z"):
		merged["tile_z"] = entry["tile_z"]
	if entry.has("tile_cells"):
		merged["tile_cells"] = entry["tile_cells"]
	return FlythroughAssetCatalog.env_tile_counts_from(merged)


func _set_entry_tile_counts(entry: Dictionary, counts: Vector3i) -> void:
	counts = FlythroughAssetCatalog.stamp_env_tile_counts(entry, counts)
	var cfg: Dictionary
	if entry.get("config", null) is Dictionary:
		cfg = (entry["config"] as Dictionary).duplicate(true)
	else:
		cfg = {}
	FlythroughAssetCatalog.stamp_env_tile_counts(cfg, counts)
	entry["config"] = cfg


func _stamp_tiles_on_cfg(cfg: Dictionary, entry: Dictionary) -> void:
	var counts := _entry_tile_counts(entry)
	if not _entry_has_tiles(entry):
		if _env_tile_x != null:
			counts = _sidebar_tile_counts()
			_set_entry_tile_counts(entry, counts)
		else:
			counts = FlythroughAssetCatalog.default_env_tile_counts()
	FlythroughAssetCatalog.stamp_env_tile_counts(cfg, counts)


func _entry_asset_caption(entry: Dictionary) -> String:
	var cfg: Dictionary = entry.get("config", {}) as Dictionary
	if cfg.has("path") and str(cfg["path"]).strip_edges() != "":
		return str(cfg["path"]).get_file()
	if cfg.has("hdri_path") and str(cfg["hdri_path"]).strip_edges() != "":
		return str(cfg["hdri_path"]).get_file()
	if cfg.has("source"):
		return str(cfg["source"]).replace("primitive:", "")
	if cfg.has("preset"):
		return str(cfg["preset"]).replace("_", " ")
	return str(entry.get("label", "Asset"))


func _open_edit_item(tab: int, index: int) -> void:
	var entries := _entries_for_tab(tab)
	if index < 0 or index >= entries.size() or _edit_dialog == null:
		return
	_edit_tab = tab
	_edit_index = index
	var entry: Dictionary = entries[index]
	_edit_name.text = str(entry.get("label", "Asset"))
	_edit_asset_label.text = _entry_asset_caption(entry)
	_edit_asset_label.tooltip_text = _edit_asset_label.text
	var show_scale := tab != TAB_LIGHT
	_edit_scale_row.visible = show_scale
	if _edit_offset_box:
		_edit_offset_box.visible = show_scale
	if _edit_tile_box:
		_edit_tile_box.visible = (tab == TAB_ENV)
	if _edit_tile_hint:
		_edit_tile_hint.visible = (tab == TAB_ENV)
	if show_scale:
		if tab == TAB_ENV:
			_edit_scale_slider.min_value = 0.1
			_edit_scale_slider.max_value = 200.0
			_edit_scale_slider.step = 0.1
		else:
			_edit_scale_slider.min_value = 0.1
			_edit_scale_slider.max_value = 200.0
			_edit_scale_slider.step = 0.1
		_edit_scale_busy = true
		var raw: Variant = _entry_scale_raw(entry)
		if raw is String:
			SliderSpinLinkScr.set_expr(_edit_scale_slider, str(raw), false)
		else:
			SliderSpinLinkScr.set_expr(_edit_scale_slider, str(snappedf(float(raw), 0.001)), false)
		_edit_scale_busy = false
		_edit_offset_busy = true
		var off := _entry_user_offset(entry)
		if _edit_offset_x:
			SliderSpinLinkScr.set_expr(_edit_offset_x, str(snappedf(off.x, 0.001)), false)
		if _edit_offset_y:
			SliderSpinLinkScr.set_expr(_edit_offset_y, str(snappedf(off.y, 0.001)), false)
		if _edit_offset_z:
			SliderSpinLinkScr.set_expr(_edit_offset_z, str(snappedf(off.z, 0.001)), false)
		_edit_offset_busy = false
		if tab == TAB_ENV:
			_edit_tile_busy = true
			var tiles := _entry_tile_counts(entry)
			if not _entry_has_tiles(entry):
				tiles = _sidebar_tile_counts()
			if _edit_tile_x:
				_edit_tile_x.value = FlythroughAssetCatalog.env_tile_grid_size(tiles.x)
			if _edit_tile_y:
				_edit_tile_y.value = FlythroughAssetCatalog.env_tile_grid_size(tiles.y)
			if _edit_tile_z:
				_edit_tile_z.value = FlythroughAssetCatalog.env_tile_grid_size(tiles.z)
			_edit_tile_busy = false
			_refresh_edit_tile_hint(tiles)
	_sync_edit_mat_blend_rows(tab, entry)
	_edit_dialog.popup_centered()


func _on_edit_replace_pressed() -> void:
	if _edit_tab < 0 or _edit_index < 0:
		return
	_edit_from_modal_replace = true
	_pick_replace(_edit_tab, _edit_index)


func _commit_edit_scale() -> void:
	if _edit_tab < 0 or _edit_index < 0 or _edit_tab == TAB_LIGHT:
		return
	if _edit_scale_slider == null or not is_instance_valid(_edit_scale_slider):
		return
	var entries := _entries_for_tab(_edit_tab)
	if _edit_index >= entries.size():
		return
	var entry: Dictionary = entries[_edit_index]
	var raw: Variant = SliderSpinLinkScr.param_of(_edit_scale_slider)
	var scale_val := maxf(SliderSpinLinkScr.eval_of(_edit_scale_slider), 0.0)
	_set_entry_user_scale(entry, scale_val, raw)
	# Live on stage when this row is the applied selection.
	if _selection_for_tab(_edit_tab) == _edit_index:
		_push_live_scale(_edit_tab, scale_val)
	_schedule_autosave()


func _commit_edit_offset() -> void:
	if _edit_tab < 0 or _edit_index < 0 or _edit_tab == TAB_LIGHT:
		return
	if _edit_offset_y == null or not is_instance_valid(_edit_offset_y):
		return
	var entries := _entries_for_tab(_edit_tab)
	if _edit_index >= entries.size():
		return
	var entry: Dictionary = entries[_edit_index]
	var offset := Vector3(
		SliderSpinLinkScr.eval_of(_edit_offset_x, 0.0) if _edit_offset_x else 0.0,
		SliderSpinLinkScr.eval_of(_edit_offset_y, 0.0),
		SliderSpinLinkScr.eval_of(_edit_offset_z, 0.0) if _edit_offset_z else 0.0
	)
	_set_entry_user_offset(entry, offset)
	if _selection_for_tab(_edit_tab) == _edit_index:
		_push_live_offset(_edit_tab, offset)
	_schedule_autosave()


func _commit_edit_mat_override() -> void:
	if _edit_tab < 0 or _edit_index < 0 or _edit_tab == TAB_LIGHT:
		return
	if _edit_mat_opt == null or not is_instance_valid(_edit_mat_opt):
		return
	var entries := _entries_for_tab(_edit_tab)
	if _edit_index >= entries.size():
		return
	var entry: Dictionary = entries[_edit_index]
	if not _entry_shows_mat_override(_edit_tab, entry):
		return
	var idx := _edit_mat_opt.selected
	var look := "Off"
	if idx > 0 and idx <= MaterialOverrideEffect.LOOK_NAMES.size():
		look = str(MaterialOverrideEffect.LOOK_NAMES[idx - 1])
	_set_entry_mat_override(entry, look)
	if _selection_for_tab(_edit_tab) == _edit_index:
		_push_live_mat_override(_edit_tab, look)
	_schedule_autosave()


func _commit_edit_blend() -> void:
	if _edit_tab < 0 or _edit_index < 0 or _edit_tab == TAB_LIGHT:
		return
	if _edit_blend_opt == null or not is_instance_valid(_edit_blend_opt):
		return
	var entries := _entries_for_tab(_edit_tab)
	if _edit_index >= entries.size():
		return
	var entry: Dictionary = entries[_edit_index]
	if not _entry_shows_blend(_edit_tab, entry):
		return
	var bidx := _edit_blend_opt.selected
	var blend := "Normal"
	if bidx >= 0 and bidx < FlythroughMediaProp.BLEND_NAMES.size():
		blend = str(FlythroughMediaProp.BLEND_NAMES[bidx])
	_set_entry_blend_mode(entry, blend)
	if _selection_for_tab(_edit_tab) == _edit_index:
		_push_live_blend(_edit_tab, blend)
	_schedule_autosave()


func _commit_edit_tiles() -> void:
	if _edit_tab != TAB_ENV or _edit_index < 0:
		return
	if _edit_tile_x == null or not is_instance_valid(_edit_tile_x):
		return
	var entries := _entries_for_tab(_edit_tab)
	if _edit_index >= entries.size():
		return
	var counts := Vector3i(
		_spin_tile_count(_edit_tile_x),
		_spin_tile_count(_edit_tile_y),
		_spin_tile_count(_edit_tile_z)
	)
	_set_entry_tile_counts(entries[_edit_index], counts)
	_refresh_edit_tile_hint(counts)
	if _selection_for_tab(TAB_ENV) == _edit_index:
		_push_live_tiles(counts)
		_sync_env_tile_spins(counts)
	_schedule_autosave()


func _push_live_offset(tab: int, offset: Vector3) -> void:
	var idx := _ensure_stage()
	if idx < 0 or idx >= ShowDirector.items.size():
		return
	var params: Dictionary = ShowDirector.items[idx].params
	var packed := _offset_to_dict(offset)
	match tab:
		TAB_ENV:
			var env_cfg: Dictionary = (params.get("environment", {}) as Dictionary).duplicate(true)
			env_cfg["user_offset"] = packed
			params["environment"] = env_cfg
			ShowDirector.set_active_cue_param("env_offset", packed)
		TAB_MAIN:
			var main_cfg: Dictionary = (params.get("centerpiece", {}) as Dictionary).duplicate(true)
			main_cfg["user_offset"] = packed
			params["centerpiece"] = main_cfg
			ShowDirector.set_active_cue_param("centerpiece_offset", packed)
		TAB_SCATTER:
			var sc_cfg: Dictionary = (params.get("scatter", {}) as Dictionary).duplicate(true)
			sc_cfg["user_offset"] = packed
			params["scatter"] = sc_cfg
			ShowDirector.set_active_cue_param("scatter_offset", packed)


func _push_live_mat_override(tab: int, look: String) -> void:
	var idx := _ensure_stage()
	if idx < 0 or idx >= ShowDirector.items.size():
		return
	var params: Dictionary = ShowDirector.items[idx].params
	var layer := _layer_id_for_tab(tab)
	var cfg: Dictionary = (params.get(layer, {}) as Dictionary).duplicate(true)
	var n := str(look).strip_edges()
	if n.is_empty() or n.to_lower() == "off" or n.to_lower() == "none":
		cfg.erase("mat_override")
		cfg.erase("material_override")
		n = "Off"
	else:
		n = MaterialOverrideEffect.normalize_look(n)
		cfg["mat_override"] = n
	params[layer] = cfg
	match tab:
		TAB_ENV:
			ShowDirector.set_active_cue_param("env_mat_override", n)
		TAB_MAIN:
			ShowDirector.set_active_cue_param("centerpiece_mat_override", n)
		TAB_SCATTER:
			ShowDirector.set_active_cue_param("scatter_mat_override", n)


func _push_live_blend(tab: int, blend: String) -> void:
	var idx := _ensure_stage()
	if idx < 0 or idx >= ShowDirector.items.size():
		return
	var params: Dictionary = ShowDirector.items[idx].params
	var layer := _layer_id_for_tab(tab)
	var cfg: Dictionary = (params.get(layer, {}) as Dictionary).duplicate(true)
	var n := FlythroughMediaProp.normalize_blend(blend)
	cfg["blend_mode"] = n
	params[layer] = cfg
	match tab:
		TAB_ENV:
			ShowDirector.set_active_cue_param("env_blend", n)
		TAB_MAIN:
			ShowDirector.set_active_cue_param("centerpiece_blend", n)
		TAB_SCATTER:
			ShowDirector.set_active_cue_param("scatter_blend", n)


func _push_live_scale(tab: int, scale_val: float) -> void:
	var idx := _ensure_stage()
	if idx < 0:
		return
	var expr := ""
	var sel := _selection_for_tab(tab)
	var entries := _entries_for_tab(tab)
	if sel >= 0 and sel < entries.size():
		expr = _entry_scale_expr(entries[sel])
	match tab:
		TAB_ENV:
			if env_scale:
				if expr.is_empty():
					SliderSpinLinkScr.set_spin_driven(env_scale, scale_val)
				else:
					var sl := SliderSpinLinkScr.slider_of_spin(env_scale)
					if sl == null or SliderSpinLinkScr.expr_of(sl) != expr:
						SliderSpinLinkScr.set_spin_driven(env_scale, expr)
			if idx < ShowDirector.items.size():
				var params: Dictionary = ShowDirector.items[idx].params
				var env_cfg: Dictionary = (params.get("environment", {}) as Dictionary).duplicate(true)
				if expr.is_empty():
					env_cfg["user_scale"] = scale_val
					env_cfg.erase("user_scale_expr")
				else:
					env_cfg["user_scale_expr"] = expr
					if not env_cfg.has("user_scale") or float(env_cfg.get("user_scale", 0.0)) <= 0.0:
						env_cfg["user_scale"] = 1.0
				params["environment"] = env_cfg
			ShowDirector.set_active_cue_param("env_scale", scale_val)
		TAB_MAIN:
			if idx < ShowDirector.items.size():
				var params_m: Dictionary = ShowDirector.items[idx].params
				var main_cfg: Dictionary = (params_m.get("centerpiece", {}) as Dictionary).duplicate(true)
				if expr.is_empty():
					main_cfg["user_scale"] = scale_val
					main_cfg.erase("user_scale_expr")
				else:
					main_cfg["user_scale_expr"] = expr
					if not main_cfg.has("user_scale") or float(main_cfg.get("user_scale", 0.0)) <= 0.0:
						main_cfg["user_scale"] = 1.0
				params_m["centerpiece"] = main_cfg
			ShowDirector.set_active_cue_param("centerpiece_scale", scale_val)
		TAB_SCATTER:
			if idx < ShowDirector.items.size():
				var params_s: Dictionary = ShowDirector.items[idx].params
				var sc_cfg: Dictionary = (params_s.get("scatter", {}) as Dictionary).duplicate(true)
				if expr.is_empty():
					sc_cfg["user_scale"] = scale_val
					sc_cfg.erase("user_scale_expr")
				else:
					sc_cfg["user_scale_expr"] = expr
					if not sc_cfg.has("user_scale") or float(sc_cfg.get("user_scale", 0.0)) <= 0.0:
						sc_cfg["user_scale"] = 1.0
				params_s["scatter"] = sc_cfg
			ShowDirector.set_active_cue_param("scatter_scale", scale_val)


func _on_edit_dialog_confirmed() -> void:
	_commit_edit_scale()
	_commit_edit_offset()
	_commit_edit_mat_override()
	_commit_edit_blend()
	if _edit_tab < 0 or _edit_index < 0:
		_clear_edit_dialog_target()
		return
	var entries := _entries_for_tab(_edit_tab)
	if _edit_index >= entries.size():
		_clear_edit_dialog_target()
		return
	var entry: Dictionary = entries[_edit_index]
	var new_name := _edit_name.text.strip_edges()
	if new_name.is_empty():
		new_name = str(entry.get("label", "Asset"))
	if str(entry.get("label", "")) != new_name:
		entry["label"] = new_name
		_rebuild_all_lists()
		_refresh_status()
		_schedule_autosave()
	_clear_edit_dialog_target()


func _on_edit_dialog_closed() -> void:
	_commit_edit_scale()
	_commit_edit_offset()
	_commit_edit_mat_override()
	_commit_edit_blend()
	_clear_edit_dialog_target()


func _clear_edit_dialog_target() -> void:
	_edit_tab = -1
	_edit_index = -1
	_edit_from_modal_replace = false


func _schedule_autosave() -> void:
	if _restoring_session or _autosave_timer == null:
		return
	_autosave_timer.start()


func _save_session_now() -> void:
	if _restoring_session:
		return
	if _autosave_timer != null and is_instance_valid(_autosave_timer) and not _autosave_timer.is_stopped():
		_autosave_timer.stop()
	var payload := build_session_payload()
	SessionStore.save_session(payload)


func build_session_payload() -> Dictionary:
	## Snapshot sidebar working lists + live stage for next launch.
	var env_dur := 8.0
	var main_dur := 8.0
	var scatter_dur := 8.0
	var light_dur := 8.0
	var scale_val := 1.0
	var speed_val := 12.0
	var path_style_val := FlythroughPathBuilder.STYLE_AUTO
	var scatter_layout_val := "random"
	var scatter_density_val := 18
	var scatter_global_scale_val := 1.0
	var tab_idx := 0
	if env_duration != null and is_instance_valid(env_duration):
		env_dur = SliderSpinLinkScr.eval_spin(env_duration, 8.0)
	if main_duration != null and is_instance_valid(main_duration):
		main_dur = SliderSpinLinkScr.eval_spin(main_duration, 8.0)
	if scatter_duration != null and is_instance_valid(scatter_duration):
		scatter_dur = SliderSpinLinkScr.eval_spin(scatter_duration, 8.0)
	if light_duration != null and is_instance_valid(light_duration):
		light_dur = SliderSpinLinkScr.eval_spin(light_duration, 8.0)
	if env_scale != null and is_instance_valid(env_scale):
		scale_val = SliderSpinLinkScr.eval_spin(env_scale, 1.0)
	if fly_speed != null and is_instance_valid(fly_speed):
		speed_val = SliderSpinLinkScr.eval_spin(fly_speed, 12.0)
	if path_style != null and is_instance_valid(path_style) and path_style.selected >= 0:
		path_style_val = _path_style_id_at(path_style.selected)
	scatter_layout_val = _scatter_layout_id()
	scatter_density_val = _scatter_density_value()
	scatter_global_scale_val = _scatter_global_scale_value()
	if asset_tabs != null and is_instance_valid(asset_tabs):
		tab_idx = asset_tabs.current_tab
	return {
		"name": str(ShowDirector.show_data.get("name", "HyperSpace")),
		"sidebar": {
			"env_entries": _duplicate_entries(_env_entries),
			"main_entries": _duplicate_entries(_main_entries),
			"scatter_entries": _duplicate_entries(_scatter_entries),
			"light_entries": _duplicate_entries(_light_entries),
			"sel_env": _sel_env,
			"sel_main": _sel_main,
			"sel_scatter": _sel_scatter,
			"sel_light": _sel_light,
			"env_duration": SliderSpinLinkScr.param_of_spin(env_duration) if env_duration else env_dur,
			"main_duration": SliderSpinLinkScr.param_of_spin(main_duration) if main_duration else main_dur,
			"scatter_duration": SliderSpinLinkScr.param_of_spin(scatter_duration) if scatter_duration else scatter_dur,
			"light_duration": SliderSpinLinkScr.param_of_spin(light_duration) if light_duration else light_dur,
			"env_scale": scale_val,
			"fly_speed": SliderSpinLinkScr.param_of_spin(fly_speed) if fly_speed else speed_val,
			"path_style": path_style_val,
			"scatter_layout": scatter_layout_val,
			"scatter_density": scatter_density_val,
			"scatter_global_scale": SliderSpinLinkScr.param_of_spin(scatter_global_scale) if scatter_global_scale else scatter_global_scale_val,
			"autoplay": [_autoplay[TAB_ENV], _autoplay[TAB_MAIN], _autoplay[TAB_SCATTER], _autoplay[TAB_LIGHT]],
			"current_tab": tab_idx,
		},
		"items": ShowDirector.items_to_dicts(),
		"current_index": ShowDirector.current_index,
		"cues": ShowDirector.cues.duplicate(true) if ShowDirector.cues is Array else [],
		"effects": ShowDirector.show_data.get("effects", ["ascii", "feedback", "glitch"]),
		"drivers": _serialize_drivers(),
		"fx": ShowDirector.export_fx_state() if ShowDirector else {},
	}


func _serialize_drivers() -> Dictionary:
	var n := get_node_or_null("/root/DriverHub")
	if n != null and n.has_method("serialize"):
		var d: Variant = n.call("serialize")
		if d is Dictionary:
			return d as Dictionary
	return {}


func _duplicate_entries(entries: Array[Dictionary]) -> Array:
	var out: Array = []
	for e in entries:
		out.append(e.duplicate(true))
	return out


func begin_session_restore() -> void:
	_restoring_session = true


func end_session_restore() -> void:
	_restoring_session = false


func _restore_sidebar_from_session() -> void:
	## Child _ready runs before Main — restore lists/timers here; stage apply happens in Main.
	var data := SessionStore.load_session()
	if data.is_empty():
		return
	var sidebar: Variant = data.get("sidebar", {})
	if not (sidebar is Dictionary) or (sidebar as Dictionary).is_empty():
		return
	_restoring_session = true
	var sb: Dictionary = sidebar
	# Honor explicit empty lists (user removed catalog rows).
	if sb.has("env_entries"):
		_env_entries = SessionStore.entries_from_variant(sb.get("env_entries", []))
		_clear_stamped_env_scale_drivers()
	if sb.has("main_entries"):
		_main_entries = SessionStore.entries_from_variant(sb.get("main_entries", []))
	if sb.has("scatter_entries"):
		_scatter_entries = SessionStore.entries_from_variant(sb.get("scatter_entries", []))
	if sb.has("light_entries"):
		_light_entries = SessionStore.entries_from_variant(sb.get("light_entries", []))
	_sel_env = int(sb.get("sel_env", _sel_env))
	_sel_main = int(sb.get("sel_main", _sel_main))
	_sel_scatter = int(sb.get("sel_scatter", _sel_scatter))
	_sel_light = int(sb.get("sel_light", _sel_light))
	_clamp_all_selections()
	if env_duration:
		SliderSpinLinkScr.set_spin_driven(env_duration, sb.get("env_duration", 8.0))
	if main_duration:
		SliderSpinLinkScr.set_spin_driven(main_duration, sb.get("main_duration", 8.0))
	if scatter_duration:
		SliderSpinLinkScr.set_spin_driven(scatter_duration, sb.get("scatter_duration", 8.0))
	if light_duration:
		SliderSpinLinkScr.set_spin_driven(light_duration, sb.get("light_duration", 8.0))
	if env_scale and sb.has("env_scale"):
		# Header Env scale starts undriven (plain number). Per-item Edit drivers stay
		# on catalog entries; do not stamp a session expression onto the header.
		var sl := SliderSpinLinkScr.slider_of_spin(env_scale)
		var num := _eval_driven_value(sb["env_scale"], 1.0)
		if sl:
			SliderSpinLinkScr.reset_to_number(sl, maxf(num, 0.01), false)
		else:
			SliderSpinLinkScr.set_spin_driven(env_scale, maxf(num, 0.01))
	if fly_speed and sb.has("fly_speed"):
		SliderSpinLinkScr.set_spin_driven(fly_speed, sb["fly_speed"])
	if path_style and (sb.has("path_style") or sb.has("camera_path")):
		_select_path_style_no_signal(str(sb.get("path_style", sb.get("camera_path", "auto"))))
	_scatter_settings_busy = true
	if scatter_layout and sb.has("scatter_layout"):
		_select_scatter_layout_no_signal(str(sb["scatter_layout"]))
	if scatter_density and sb.has("scatter_density"):
		SliderSpinLinkScr.set_spin_driven(scatter_density, sb["scatter_density"])
	if scatter_global_scale and sb.has("scatter_global_scale"):
		SliderSpinLinkScr.set_spin_driven(scatter_global_scale, sb["scatter_global_scale"])
	_scatter_settings_busy = false
	if asset_tabs and sb.has("current_tab"):
		asset_tabs.current_tab = clampi(int(sb["current_tab"]), 0, asset_tabs.get_tab_count() - 1)
	# Do not resume autoplay on boot — restore timers/lists only.
	_session_restored = true
	_restoring_session = false


func _clear_stamped_env_scale_drivers() -> void:
	## Older sessions copied the header Driver onto every env row. Strip those so
	## Env scale boots as a plain slider; user can still pick a Driver afterward.
	for i in _env_entries.size():
		var entry: Dictionary = _env_entries[i]
		entry.erase("user_scale_expr")
		var cfg: Dictionary = entry.get("config", {}) as Dictionary
		if not cfg.is_empty():
			cfg.erase("user_scale_expr")
			if cfg.has("user_scale") and _is_scale_expr(cfg["user_scale"]):
				cfg.erase("user_scale")
		if entry.has("user_scale") and _is_scale_expr(entry["user_scale"]):
			entry.erase("user_scale")
		_env_entries[i] = entry


func _clamp_all_selections() -> void:
	_sel_env = _clamp_sel(_sel_env, _env_entries.size())
	_sel_main = _clamp_sel(_sel_main, _main_entries.size())
	_sel_scatter = _clamp_sel(_sel_scatter, _scatter_entries.size())
	_sel_light = _clamp_sel(_sel_light, _light_entries.size())


func _clamp_sel(index: int, count: int) -> int:
	if count <= 0:
		return -1
	if index < 0:
		return -1
	return mini(index, count - 1)


func _setup_preset_shuffles() -> void:
	var header: VBoxContainer = $Margin/Column/Header
	var path_row: Node = $Margin/Column/Header/PathRow
	if header and path_style:
		_shuffle_slots["path"] = CycleRandomScr.attach_shuffle(header, path_row, "Shuffle path")
		var piv: HSlider = _shuffle_slots["path"].get("interval")
		if piv:
			SliderSpinLinkScr.attach_driven(piv, Callable(), 1.0)
	var scatter_tab: VBoxContainer = $Margin/Column/AssetTabs/Scattering
	var layout_row: Node = $Margin/Column/AssetTabs/Scattering/ScatterLayoutRow
	if scatter_tab and scatter_layout:
		_shuffle_slots["scatter"] = CycleRandomScr.attach_shuffle(scatter_tab, layout_row, "Shuffle layout")
		var siv: HSlider = _shuffle_slots["scatter"].get("interval")
		if siv:
			SliderSpinLinkScr.attach_driven(siv, Callable(), 1.0)


func _process(delta: float) -> void:
	_apply_live_playlist_drivers()
	if CycleRandomScr.tick_slot(_shuffle_slots.get("path", {}), delta):
		CycleRandomScr.advance_option(path_style)
	if CycleRandomScr.tick_slot(_shuffle_slots.get("scatter", {}), delta):
		CycleRandomScr.advance_option(scatter_layout)
	if _warming:
		_tick_warm(delta)
	for tab in [TAB_ENV, TAB_MAIN, TAB_SCATTER, TAB_LIGHT]:
		if not _autoplay[tab]:
			continue
		# Don't advance timers until cache is ready (pending Play waits on warm).
		if _warming and _pending_play_tab == tab:
			continue
		_elapsed[tab] += delta
		var step := _duration_for_tab(tab)
		if _elapsed[tab] < step:
			continue
		_elapsed[tab] = 0.0
		_step_tab(tab, 1)


func _maybe_autosave_spin(spin: SpinBox) -> void:
	var sl := SliderSpinLinkScr.slider_of_spin(spin)
	if sl and SliderSpinLinkScr.looks_driven_expr(sl):
		return
	_schedule_autosave()


func _apply_live_playlist_drivers() -> void:
	## Re-eval expressions every frame for live visuals; scatter count only on integer change.
	var fly_sl := SliderSpinLinkScr.slider_of_spin(fly_speed)
	if fly_sl and SliderSpinLinkScr.looks_driven_expr(fly_sl):
		_on_fly_speed_changed(SliderSpinLinkScr.eval_of(fly_sl))
	var scale_sl := SliderSpinLinkScr.slider_of_spin(env_scale)
	if scale_sl and SliderSpinLinkScr.looks_driven_expr(scale_sl):
		_on_env_scale_changed(SliderSpinLinkScr.eval_of(scale_sl))
	var dens_sl := SliderSpinLinkScr.slider_of_spin(scatter_density)
	if dens_sl and SliderSpinLinkScr.looks_driven_expr(dens_sl):
		_on_scatter_density_changed(SliderSpinLinkScr.eval_of(dens_sl))
	var gscale_sl := SliderSpinLinkScr.slider_of_spin(scatter_global_scale)
	if gscale_sl and SliderSpinLinkScr.looks_driven_expr(gscale_sl):
		_on_scatter_global_scale_changed(SliderSpinLinkScr.eval_of(gscale_sl))
	if _edit_scale_slider and _edit_dialog and _edit_dialog.visible \
			and SliderSpinLinkScr.looks_driven_expr(_edit_scale_slider):
		_commit_edit_scale()
	# Keep per-item scale drivers alive after the Edit popup closes.
	_tick_entry_scale_driver(TAB_ENV)
	_tick_entry_scale_driver(TAB_MAIN)
	_tick_entry_scale_driver(TAB_SCATTER)


func _tick_entry_scale_driver(tab: int) -> void:
	if _edit_dialog != null and _edit_dialog.visible and _edit_tab == tab:
		return
	var sel := _selection_for_tab(tab)
	var entries := _entries_for_tab(tab)
	if sel < 0 or sel >= entries.size():
		return
	var entry: Dictionary = entries[sel]
	var expr := _entry_scale_expr(entry)
	if expr.is_empty():
		return
	if tab == TAB_ENV and env_scale:
		var sl := SliderSpinLinkScr.slider_of_spin(env_scale)
		if sl != null and SliderSpinLinkScr.expr_of(sl) == expr:
			# Header Env scale already has this driver; that path ticks it.
			return
	var scale_val := maxf(_eval_driven_value(expr, _entry_scale_snapshot(entry)), 0.0)
	var cfg: Dictionary = entry.get("config", {}) as Dictionary
	if not cfg.is_empty():
		if not cfg.has("user_scale_expr"):
			cfg["user_scale_expr"] = expr
	_push_live_scale(tab, scale_val)


func _any_tab_autoplaying() -> bool:
	for on in _autoplay:
		if on:
			return true
	return false


func _setup_tab_icons() -> void:
	## Icon-only tabs so Env / Main / Scatter / Lighting all fit.
	var specs := [
		{"title": "", "tip": "Environments", "color": Color(0.35, 0.75, 0.45), "shape": "terrain"},
		{"title": "", "tip": "Main character", "color": Color(0.95, 0.7, 0.25), "shape": "diamond"},
		{"title": "", "tip": "Scattering", "color": Color(0.45, 0.7, 1.0), "shape": "dots"},
		{"title": "", "tip": "Lighting", "color": Color(1.0, 0.85, 0.35), "shape": "sun"},
	]
	for i in specs.size():
		var spec: Dictionary = specs[i]
		asset_tabs.set_tab_title(i, str(spec["title"]))
		asset_tabs.set_tab_icon(i, _make_tab_icon(spec["color"] as Color, str(spec["shape"])))
		asset_tabs.set_tab_tooltip(i, str(spec["tip"]))


func _make_tab_icon(color: Color, shape: String) -> Texture2D:
	var size := 18
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match shape:
		"terrain":
			for x in size:
				var h := int(4.0 + 6.0 * abs(sin(x * 0.55)) + (x % 3))
				for y in range(size - h, size):
					img.set_pixel(x, y, color)
		"diamond":
			var c := size / 2
			for y in size:
				for x in size:
					if abs(x - c) + abs(y - c) <= 7:
						img.set_pixel(x, y, color)
		"dots":
			for p: Vector2i in [Vector2i(4, 5), Vector2i(13, 4), Vector2i(8, 10), Vector2i(3, 13), Vector2i(14, 13)]:
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var px: int = p.x + ox
						var py: int = p.y + oy
						if px >= 0 and py >= 0 and px < size and py < size:
							img.set_pixel(px, py, color)
		"sun":
			var c2: float = size / 2.0
			for y in size:
				for x in size:
					var dx: float = float(x) - c2
					var dy: float = float(y) - c2
					var d: float = sqrt(dx * dx + dy * dy)
					if d <= 4.5 or (d >= 6.5 and d <= 8.0 and int(atan2(dy, dx) * 4.0 + 8.0) % 2 == 0):
						img.set_pixel(x, y, color)
		_:
			for y in range(3, size - 3):
				for x in range(3, size - 3):
					img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


func _load_catalog_entries() -> void:
	_env_entries.clear()
	for entry in FlythroughAssetCatalog.environment_chooser_entries():
		_env_entries.append((entry as Dictionary).duplicate(true))
	_main_entries.clear()
	_scatter_entries.clear()
	for entry in FlythroughAssetCatalog.prop_chooser_entries():
		var e: Dictionary = (entry as Dictionary).duplicate(true)
		var roles: Array = e.get("roles", []) as Array
		if "centerpiece" in roles:
			_main_entries.append(e.duplicate(true))
		if "scatter" in roles:
			_scatter_entries.append(e.duplicate(true))
	_light_entries.clear()
	for entry in FlythroughAssetCatalog.lighting_chooser_entries():
		_light_entries.append((entry as Dictionary).duplicate(true))


func _on_show_loaded(show_name: String) -> void:
	show_label.text = show_name
	# Stage params drive applied-layer highlight; keep session indices if unmatched.
	var prev_env := _sel_env
	var prev_main := _sel_main
	var prev_scatter := _sel_scatter
	var prev_light := _sel_light
	_sync_selection_from_stage()
	if _session_restored:
		if _sel_env < 0 and prev_env >= 0:
			_sel_env = _clamp_sel(prev_env, _env_entries.size())
		if _sel_main < 0 and prev_main >= 0:
			_sel_main = _clamp_sel(prev_main, _main_entries.size())
		if _sel_scatter < 0 and prev_scatter >= 0:
			_sel_scatter = _clamp_sel(prev_scatter, _scatter_entries.size())
		if _sel_light < 0 and prev_light >= 0:
			_sel_light = _clamp_sel(prev_light, _light_entries.size())
		_session_restored = false
	_rebuild_all_lists()
	_refresh_status()
	_sync_fly_speed_from_stage()
	_sync_path_style_from_stage()
	_sync_env_scale_from_stage()
	_sync_env_tiles_from_stage()
	_sync_scatter_settings_from_stage()
	_schedule_autosave()
	_start_warm_all(-1)


func _on_item_changed(_item_id: String, _index: int) -> void:
	## During layer apply / tab autoplay, trust intentional list indices — rematching
	## from stage configs can snap selection back and stall cycling on one asset.
	if _suppress_playlist_ui or _restoring_session:
		return
	if not _any_tab_autoplaying():
		_sync_selection_from_stage()
	_rebuild_all_lists()
	_refresh_status()
	_sync_fly_speed_from_stage()
	_sync_path_style_from_stage()
	_sync_env_scale_from_stage()
	_sync_env_tiles_from_stage()
	_sync_scatter_settings_from_stage()
	_schedule_autosave()


func _on_playlist_changed() -> void:
	if _suppress_playlist_ui or _restoring_session:
		return
	if not _any_tab_autoplaying():
		_sync_selection_from_stage()
	_rebuild_all_lists()
	_refresh_status()
	_sync_fly_speed_from_stage()
	_sync_path_style_from_stage()
	_sync_env_scale_from_stage()
	_sync_env_tiles_from_stage()
	_sync_scatter_settings_from_stage()
	_schedule_autosave()


func _on_fly_speed_changed(value: float) -> void:
	var idx := _ensure_stage()
	if idx < 0:
		return
	ShowDirector.set_active_cue_param("fly_speed", value)
	# Also keep the playlist alias used by configure_from_params.
	if idx < ShowDirector.items.size():
		ShowDirector.items[idx].params["speed"] = value
	_maybe_autosave_spin(fly_speed)


func _fill_path_style_options() -> void:
	if path_style == null:
		return
	path_style.clear()
	for i in FlythroughPathBuilder.STYLE_IDS.size():
		path_style.add_item(FlythroughPathBuilder.STYLE_LABELS[i])
		path_style.set_item_metadata(i, FlythroughPathBuilder.STYLE_IDS[i])
	path_style.select(0)


func _path_style_id_at(index: int) -> String:
	if path_style == null or index < 0 or index >= path_style.item_count:
		return FlythroughPathBuilder.STYLE_AUTO
	var meta: Variant = path_style.get_item_metadata(index)
	if meta == null:
		return FlythroughPathBuilder.normalize_style(path_style.get_item_text(index))
	return FlythroughPathBuilder.normalize_style(str(meta))


func _select_path_style_no_signal(style: String) -> void:
	if path_style == null:
		return
	var id := FlythroughPathBuilder.normalize_style(style)
	var idx := 0
	for i in path_style.item_count:
		if _path_style_id_at(i) == id:
			idx = i
			break
	path_style.select(idx)


func _on_path_style_selected(index: int) -> void:
	var idx := _ensure_stage()
	if idx < 0:
		return
	var style_id := _path_style_id_at(index)
	ShowDirector.set_active_cue_param("path_style", style_id)
	if idx < ShowDirector.items.size():
		ShowDirector.items[idx].params["camera_path"] = style_id
	_schedule_autosave()


func _on_env_scale_changed(value: float) -> void:
	var idx := _ensure_stage()
	if idx < 0:
		return
	var scale_val := maxf(value, 0.01)
	var raw: Variant = SliderSpinLinkScr.param_of_spin(env_scale) if env_scale else scale_val
	var driven := _is_scale_expr(raw)
	if idx < ShowDirector.items.size():
		var params: Dictionary = ShowDirector.items[idx].params
		var env_cfg: Dictionary = (params.get("environment", {}) as Dictionary).duplicate(true)
		if driven:
			env_cfg["user_scale_expr"] = str(raw).strip_edges()
			if not env_cfg.has("user_scale") or float(env_cfg.get("user_scale", 0.0)) <= 0.0:
				env_cfg["user_scale"] = 1.0
		else:
			env_cfg["user_scale"] = scale_val
			env_cfg.erase("user_scale_expr")
		params["environment"] = env_cfg
	# Keep selected list entry in sync with header Env scale (number or expression).
	if _sel_env >= 0 and _sel_env < _env_entries.size():
		_set_entry_user_scale(_env_entries[_sel_env], scale_val, raw)
	# Live scale only — avoid full env reload. Stored base stays if driven.
	ShowDirector.set_active_cue_param("env_scale", scale_val)
	_maybe_autosave_spin(env_scale)


func _sync_fly_speed_from_stage() -> void:
	if fly_speed == null:
		return
	var idx := _stage_index()
	var speed_val := 12.0
	if idx >= 0 and idx < ShowDirector.items.size():
		var params: Dictionary = ShowDirector.items[idx].params
		if params.has("fly_speed"):
			speed_val = float(params["fly_speed"])
		elif params.has("speed"):
			speed_val = float(params["speed"])
	SliderSpinLinkScr.set_spin_driven(fly_speed, speed_val)


func _sync_path_style_from_stage() -> void:
	if path_style == null:
		return
	var idx := _stage_index()
	var style_val := FlythroughPathBuilder.STYLE_AUTO
	if idx >= 0 and idx < ShowDirector.items.size():
		var params: Dictionary = ShowDirector.items[idx].params
		if params.has("path_style"):
			style_val = FlythroughPathBuilder.normalize_style(str(params["path_style"]))
		elif params.has("camera_path"):
			style_val = FlythroughPathBuilder.normalize_style(str(params["camera_path"]))
	_select_path_style_no_signal(style_val)


func _sync_env_scale_from_stage() -> void:
	if env_scale == null:
		return
	# Header stays a normal slider unless this row's Edit dialog assigned a driver.
	if _sel_env >= 0 and _sel_env < _env_entries.size():
		var expr := _entry_scale_expr(_env_entries[_sel_env])
		if not expr.is_empty():
			SliderSpinLinkScr.set_spin_driven(env_scale, expr)
			return
	var idx := _stage_index()
	var scale_val := 1.0
	if idx >= 0 and idx < ShowDirector.items.size():
		var params: Dictionary = ShowDirector.items[idx].params
		var env_cfg: Dictionary = params.get("environment", {}) as Dictionary
		if env_cfg.has("user_scale"):
			scale_val = float(env_cfg["user_scale"])
		elif env_cfg.has("scale"):
			scale_val = float(env_cfg["scale"])
		elif params.has("env_scale"):
			scale_val = float(params["env_scale"])
	var sl := SliderSpinLinkScr.slider_of_spin(env_scale)
	if sl:
		SliderSpinLinkScr.reset_to_number(sl, maxf(scale_val, 0.01), false)
	else:
		SliderSpinLinkScr.set_spin_driven(env_scale, scale_val)


func _sync_env_tile_spins(counts: Vector3i) -> void:
	_env_tile_busy = true
	if _env_tile_x:
		_env_tile_x.value = FlythroughAssetCatalog.env_tile_grid_size(counts.x)
	if _env_tile_y:
		_env_tile_y.value = FlythroughAssetCatalog.env_tile_grid_size(counts.y)
	if _env_tile_z:
		_env_tile_z.value = FlythroughAssetCatalog.env_tile_grid_size(counts.z)
	_env_tile_busy = false
	if _env_tile_hint:
		_env_tile_hint.text = _env_tile_hint_text(counts)


func _sync_env_tiles_from_stage() -> void:
	if _env_tile_x == null:
		return
	var counts := Vector3i.ZERO
	if _sel_env >= 0 and _sel_env < _env_entries.size() and _entry_has_tiles(_env_entries[_sel_env]):
		counts = _entry_tile_counts(_env_entries[_sel_env])
	else:
		var idx := _stage_index()
		if idx >= 0 and idx < ShowDirector.items.size():
			var params: Dictionary = ShowDirector.items[idx].params
			var env_cfg: Dictionary = params.get("environment", {}) as Dictionary
			counts = FlythroughAssetCatalog.env_tile_counts_from(env_cfg)
			if params.has("env_tiles") and not (env_cfg.has("tile_x") or env_cfg.has("tile_cells")):
				counts = FlythroughAssetCatalog.env_tile_counts_from_value(params["env_tiles"])
	_sync_env_tile_spins(counts)


func _on_env_tile_changed() -> void:
	if _env_tile_busy or _restoring_session:
		return
	var counts := _sidebar_tile_counts()
	if _env_tile_hint:
		_env_tile_hint.text = _env_tile_hint_text(counts)
	if _sel_env >= 0 and _sel_env < _env_entries.size():
		_set_entry_tile_counts(_env_entries[_sel_env], counts)
	_push_live_tiles(counts)


func _push_live_tiles(counts: Vector3i) -> void:
	var idx := _ensure_stage()
	if idx < 0:
		return
	if idx < ShowDirector.items.size():
		var params: Dictionary = ShowDirector.items[idx].params
		var env_cfg: Dictionary = (params.get("environment", {}) as Dictionary).duplicate(true)
		FlythroughAssetCatalog.stamp_env_tile_counts(env_cfg, counts)
		params["environment"] = env_cfg
	ShowDirector.set_active_cue_param("env_tiles", FlythroughAssetCatalog.env_tiles_cue_value(counts))
	_schedule_autosave()


func _fill_scatter_layout_options() -> void:
	if scatter_layout == null:
		return
	scatter_layout.clear()
	var ids := ["random", "grid", "circular"]
	var labels := ["Random", "Grid", "Circular"]
	for i in ids.size():
		scatter_layout.add_item(labels[i])
		scatter_layout.set_item_metadata(i, ids[i])
	scatter_layout.select(0)
	scatter_layout.tooltip_text = "Grid = 3D lattice filling a volume cube. Random = random points in that cube. Circular = stacked concentric rings."
	if scatter_density:
		scatter_density.tooltip_text = "How many scatter props to spawn (1–2000). GPU-instanced. GIF/video share one decoder."
	if scatter_global_scale:
		scatter_global_scale.tooltip_text = "Scale the whole scatter formation (spacing + volume cube). Per-item size stays in ✎ Edit."
	var hint: Label = get_node_or_null("Margin/Column/AssetTabs/Scattering/ScatterHint") as Label
	if hint:
		hint.text = "Fill a volume cube (up to 2000 instances). Layout picks the pattern; density is count. Global scale grows or shrinks the whole cluster. Per-item size is ✎ Edit."


func _scatter_layout_id() -> String:
	if scatter_layout == null or scatter_layout.selected < 0:
		return "random"
	var meta: Variant = scatter_layout.get_item_metadata(scatter_layout.selected)
	if meta == null:
		return FlythroughAssetCatalog.normalize_scatter_layout(scatter_layout.get_item_text(scatter_layout.selected))
	return FlythroughAssetCatalog.normalize_scatter_layout(str(meta))


func _scatter_density_value() -> int:
	if scatter_density == null:
		return 18
	return clampi(int(round(SliderSpinLinkScr.eval_spin(scatter_density, 18.0))), 1, 2000)


func _scatter_global_scale_value() -> float:
	if scatter_global_scale == null:
		return 1.0
	return clampf(SliderSpinLinkScr.eval_spin(scatter_global_scale, 1.0), 0.01, 100.0)


func _select_scatter_layout_no_signal(layout: String) -> void:
	if scatter_layout == null:
		return
	var id := FlythroughAssetCatalog.normalize_scatter_layout(layout)
	var idx := 0
	for i in scatter_layout.item_count:
		var meta: Variant = scatter_layout.get_item_metadata(i)
		var mid := FlythroughAssetCatalog.normalize_scatter_layout(str(meta) if meta != null else scatter_layout.get_item_text(i))
		if mid == id:
			idx = i
			break
	scatter_layout.select(idx)


func _sync_scatter_settings_from_stage() -> void:
	_scatter_settings_busy = true
	var layout_val := "random"
	var density_val := 18
	var global_scale_val := 1.0
	var idx := _stage_index()
	if idx >= 0 and idx < ShowDirector.items.size():
		var params: Dictionary = ShowDirector.items[idx].params
		var sc_cfg: Dictionary = params.get("scatter", {}) as Dictionary
		if sc_cfg.has("layout") or sc_cfg.has("mode"):
			layout_val = FlythroughAssetCatalog.normalize_scatter_layout(sc_cfg.get("layout", sc_cfg.get("mode", "random")))
		if sc_cfg.has("count"):
			density_val = clampi(int(sc_cfg["count"]), 1, 2000)
		if sc_cfg.has("global_scale"):
			global_scale_val = clampf(float(sc_cfg["global_scale"]), 0.01, 100.0)
		elif params.has("scatter_global_scale"):
			global_scale_val = clampf(float(params["scatter_global_scale"]), 0.01, 100.0)
	_select_scatter_layout_no_signal(layout_val)
	if scatter_density:
		SliderSpinLinkScr.set_spin_driven(scatter_density, float(density_val))
	if scatter_global_scale:
		SliderSpinLinkScr.set_spin_driven(scatter_global_scale, global_scale_val)
	_scatter_settings_busy = false


func _on_scatter_layout_selected(_index: int) -> void:
	if _scatter_settings_busy or _restoring_session:
		return
	_push_live_scatter_settings()


func _on_scatter_density_changed(_value: float) -> void:
	if _scatter_settings_busy or _restoring_session:
		return
	_push_live_scatter_settings()


func _on_scatter_global_scale_changed(_value: float) -> void:
	if _scatter_settings_busy or _restoring_session:
		return
	_push_live_scatter_global_scale()


func _push_live_scatter_settings() -> void:
	## Rebuild scatter when layout/density change and a scatter asset is applied.
	_maybe_autosave_spin(scatter_density)
	var idx := _ensure_stage()
	if idx < 0 or idx >= ShowDirector.items.size():
		return
	var params: Dictionary = ShowDirector.items[idx].params
	var sc_cfg: Dictionary = (params.get("scatter", {}) as Dictionary).duplicate(true)
	var density := _scatter_density_value()
	var layout := _scatter_layout_id()
	var gscale := _scatter_global_scale_value()
	if FlythroughAssetCatalog.is_empty_layer_config(sc_cfg):
		# Keep count at 0 so this stays empty; layout is stored for the next apply.
		sc_cfg["layout"] = layout
		sc_cfg["global_scale"] = gscale
		params["scatter"] = sc_cfg
		_schedule_autosave()
		return
	if int(sc_cfg.get("count", -1)) == density \
			and FlythroughAssetCatalog.normalize_scatter_layout(sc_cfg.get("layout", "random")) == layout:
		return
	sc_cfg["count"] = density
	sc_cfg["layout"] = layout
	sc_cfg["global_scale"] = gscale
	_suppress_playlist_ui = true
	ShowDirector.set_flythrough_layer("scatter", sc_cfg, idx)
	_suppress_playlist_ui = false


func _push_live_scatter_global_scale() -> void:
	## Scale the cluster live — no MultiMesh rebuild or asset re-import.
	_maybe_autosave_spin(scatter_global_scale)
	var idx := _ensure_stage()
	if idx < 0 or idx >= ShowDirector.items.size():
		return
	var gscale := _scatter_global_scale_value()
	var params: Dictionary = ShowDirector.items[idx].params
	var sc_cfg: Dictionary = (params.get("scatter", {}) as Dictionary).duplicate(true)
	sc_cfg["global_scale"] = gscale
	params["scatter"] = sc_cfg
	ShowDirector.set_active_cue_param("scatter_global_scale", gscale)


func _apply_environment(entry: Dictionary, force_sel: int = -1) -> void:
	var idx := _ensure_stage()
	if idx < 0:
		return
	var cfg: Dictionary = FlythroughAssetCatalog.layer_config_from_entry(entry, "environment")
	var scale_val := _entry_user_scale(entry)
	if env_scale and env_scale.is_visible_in_tree() and not entry.has("user_scale") and not (cfg.has("user_scale") or cfg.has("scale")) \
			and _entry_scale_expr(entry).is_empty():
		scale_val = SliderSpinLinkScr.eval_spin(env_scale, 1.0)
	scale_val = maxf(scale_val, 0.01)
	# Numeric size only — never stamp the header Driver expression onto the row.
	_set_entry_user_scale(entry, scale_val)
	_stamp_scale_on_cfg(cfg, entry, scale_val)
	_stamp_offset_on_cfg(cfg, entry)
	_stamp_tiles_on_cfg(cfg, entry)
	_stamp_mat_override_on_cfg(cfg, entry)
	_stamp_blend_on_cfg(cfg, entry)
	if env_scale:
		var expr := _entry_scale_expr(entry)
		if expr.is_empty():
			SliderSpinLinkScr.set_spin_driven(env_scale, scale_val)
		else:
			SliderSpinLinkScr.set_spin_driven(env_scale, expr)
	_suppress_playlist_ui = true
	ShowDirector.set_flythrough_layer("environment", cfg, idx)
	_suppress_playlist_ui = false
	_sync_env_tile_spins(FlythroughAssetCatalog.env_tile_counts_from(cfg))
	_sel_env = _resolve_selection_after_apply(_env_entries, force_sel, cfg, "environment")
	_refresh_lists_after_apply()
	_refresh_status()
	status_label.text = "Env: %s" % str(entry.get("label", "?"))
	_prefetch_neighbors(TAB_ENV)
	_schedule_autosave()


func _apply_main(entry: Dictionary, force_sel: int = -1) -> void:
	var idx := _ensure_stage()
	if idx < 0:
		return
	var cfg: Dictionary = FlythroughAssetCatalog.layer_config_from_entry(entry, "centerpiece")
	var scale_val := _entry_user_scale(entry)
	_stamp_scale_on_cfg(cfg, entry, scale_val)
	_stamp_offset_on_cfg(cfg, entry)
	_stamp_mat_override_on_cfg(cfg, entry)
	_stamp_blend_on_cfg(cfg, entry)
	_suppress_playlist_ui = true
	ShowDirector.set_flythrough_layer("centerpiece", cfg, idx)
	_suppress_playlist_ui = false
	_sel_main = _resolve_selection_after_apply(_main_entries, force_sel, cfg, "centerpiece")
	_refresh_lists_after_apply()
	_refresh_status()
	status_label.text = "Main: %s" % str(entry.get("label", "?"))
	_prefetch_neighbors(TAB_MAIN)
	_schedule_autosave()


func _apply_scatter(entry: Dictionary, force_sel: int = -1) -> void:
	var idx := _ensure_stage()
	if idx < 0:
		return
	var density := _scatter_density_value()
	var cfg: Dictionary = FlythroughAssetCatalog.layer_config_from_entry(entry, "scatter", density)
	cfg["count"] = density
	cfg["layout"] = _scatter_layout_id()
	cfg["global_scale"] = _scatter_global_scale_value()
	_stamp_scale_on_cfg(cfg, entry, _entry_user_scale(entry))
	_stamp_offset_on_cfg(cfg, entry)
	_stamp_mat_override_on_cfg(cfg, entry)
	_stamp_blend_on_cfg(cfg, entry)
	_suppress_playlist_ui = true
	ShowDirector.set_flythrough_layer("scatter", cfg, idx)
	_suppress_playlist_ui = false
	_sel_scatter = _resolve_selection_after_apply(_scatter_entries, force_sel, cfg, "scatter")
	_refresh_lists_after_apply()
	_refresh_status()
	status_label.text = "Scatter: %s" % str(entry.get("label", "?"))
	_prefetch_neighbors(TAB_SCATTER)
	_schedule_autosave()


func _apply_lighting(entry: Dictionary, force_sel: int = -1) -> void:
	var idx := _ensure_stage()
	if idx < 0:
		return
	# Same extraction path as other layers; stamp preset from entry id when missing
	# so rematch / status labels work for user-added HDRIs.
	var cfg: Dictionary = FlythroughAssetCatalog.layer_config_from_entry(entry, "lighting")
	var entry_id := str(entry.get("id", "")).strip_edges()
	if str(cfg.get("preset", "")).strip_edges().is_empty() and not entry_id.is_empty():
		cfg["preset"] = entry_id
	_suppress_playlist_ui = true
	ShowDirector.set_flythrough_layer("lighting", cfg, idx)
	_suppress_playlist_ui = false
	_sel_light = _resolve_lighting_selection_after_apply(force_sel, cfg)
	_refresh_lists_after_apply()
	_refresh_status()
	status_label.text = "Light: %s" % str(entry.get("label", "?"))
	_prefetch_neighbors(TAB_LIGHT)
	_schedule_autosave()


func _refresh_lists_after_apply() -> void:
	## During Play cycling, only update selection highlights — recreating every row
	## each step was a visible hitch on top of asset loads.
	if _any_tab_autoplaying():
		_sync_list_selection_highlights()
		_update_all_play_buttons()
		return
	_rebuild_all_lists()


func _sync_list_selection_highlights() -> void:
	_sync_list_highlight(env_list, _sel_env)
	_sync_list_highlight(main_list, _sel_main)
	_sync_list_highlight(scatter_list, _sel_scatter)
	_sync_list_highlight(light_list, _sel_light)


func _sync_list_highlight(container: VBoxContainer, selected: int) -> void:
	if container == null:
		return
	var i := 0
	for child in container.get_children():
		if child is HBoxContainer and child.get_child_count() > 0:
			var title := child.get_child(0)
			if title is Button:
				(title as Button).set_pressed_no_signal(i == selected)
		i += 1


func _prefetch_neighbors(tab: int) -> void:
	## During Play, keep the whole tab warm (not just next 1–2) so swaps stay instant.
	var entries := _entries_for_tab(tab)
	if entries.is_empty():
		return
	var paths: Array = []
	for entry in entries:
		if entry is Dictionary:
			_collect_prefetch_paths(entry as Dictionary, tab, paths)
	if not paths.is_empty():
		_AssetCache.prefetch_paths(paths)
	for p in paths:
		var s := str(p)
		if s.to_lower().ends_with(".gif") and not MediaImport.gif_cached(s):
			MediaImport.prefetch_gif(s)


func _collect_prefetch_paths(entry: Dictionary, tab: int, out: Array) -> void:
	var role := "environment"
	match tab:
		TAB_MAIN:
			role = "centerpiece"
		TAB_SCATTER:
			role = "scatter"
		TAB_LIGHT:
			role = "lighting"
	var cfg: Dictionary = FlythroughAssetCatalog.layer_config_from_entry(entry, role)
	var path := str(cfg.get("path", cfg.get("source", cfg.get("hdri_path", "")))).strip_edges()
	if not path.is_empty() and not path.begins_with("primitive:"):
		out.append(path)
	var hdri := str(cfg.get("hdri_path", "")).strip_edges()
	if not hdri.is_empty():
		out.append(hdri)


func _resolve_selection_after_apply(entries: Array[Dictionary], force_sel: int, cfg: Dictionary, role: String) -> int:
	## Prefer the list index we intentionally played. Config rematch is fallback only —
	## a failed match must not clear selection to -1 (that stalls autoplay on item 0).
	if force_sel >= 0 and force_sel < entries.size():
		return force_sel
	var matched := _index_of_config(entries, cfg, role)
	if matched >= 0:
		return matched
	# Last resort: keep a valid index so the next autoplay step can still advance.
	if entries.is_empty():
		return -1
	return 0


func _resolve_lighting_selection_after_apply(force_sel: int, cfg: Dictionary) -> int:
	## Lighting rematch is preset/hdri_path based — same force_sel trust as other tabs.
	if force_sel >= 0 and force_sel < _light_entries.size():
		return force_sel
	var matched := _index_of_lighting(_light_entries, cfg)
	if matched >= 0:
		return matched
	if _light_entries.is_empty():
		return -1
	if _sel_light >= 0:
		return clampi(_sel_light, 0, _light_entries.size() - 1)
	return 0


func _duration_for_tab(tab: int) -> float:
	var raw := 8.0
	match tab:
		TAB_ENV:
			if env_duration:
				raw = SliderSpinLinkScr.eval_spin(env_duration, 8.0)
		TAB_MAIN:
			if main_duration:
				raw = SliderSpinLinkScr.eval_spin(main_duration, 8.0)
		TAB_SCATTER:
			if scatter_duration:
				raw = SliderSpinLinkScr.eval_spin(scatter_duration, 8.0)
		TAB_LIGHT:
			if light_duration:
				raw = SliderSpinLinkScr.eval_spin(light_duration, 8.0)
	return clampf(raw, 1.0, 600.0)


func _toggle_tab_autoplay(tab: int) -> void:
	_ensure_stage()
	if _autoplay[tab]:
		_pending_play_tab = -1
		_set_tab_autoplay(tab, false)
		return
	var entries := _entries_for_tab(tab)
	if entries.is_empty():
		status_label.text = "Nothing to play in this tab"
		return
	if _warming:
		_pending_play_tab = tab
		status_label.text = "Caching… %d/%d" % [_warm_done, maxi(_warm_total, 1)]
		return
	if not _warm_ready:
		_pending_play_tab = tab
		_start_warm_all(tab)
		return
	_begin_tab_play(tab)


func _begin_tab_play(tab: int) -> void:
	# Advance immediately so Play is visibly cycling (avoids "stuck on current" for a full timer).
	_step_tab(tab, 1)
	_set_tab_autoplay(tab, true)


func _set_tab_autoplay(tab: int, playing: bool) -> void:
	_autoplay[tab] = playing
	_elapsed[tab] = 0.0
	# Category cycling is local — keep ShowDirector playlist autoplay off.
	if ShowDirector.autoplay:
		ShowDirector.set_autoplay(false)
	_update_play_button(tab)
	if playing:
		_prefetch_neighbors(tab)


func _collect_all_playlist_paths() -> Array:
	var paths: Array = []
	var seen: Dictionary = {}
	for tab in [TAB_ENV, TAB_MAIN, TAB_SCATTER, TAB_LIGHT]:
		for entry in _entries_for_tab(tab):
			if not (entry is Dictionary):
				continue
			var chunk: Array = []
			_collect_prefetch_paths(entry as Dictionary, tab, chunk)
			for p in chunk:
				var key := str(p).replace("\\", "/").strip_edges()
				if key.is_empty() or seen.has(key):
					continue
				seen[key] = true
				paths.append(key)
	return paths


func _start_warm_all(then_play_tab: int = -1) -> void:
	## Eager-load every Env/Main/Scatter/Lighting asset before Play timers start.
	## Boot splash owns the big first warm — skip visible Caching when that finished.
	if then_play_tab >= 0:
		_pending_play_tab = then_play_tab
	var paths := _collect_all_playlist_paths()
	_warm_paths = paths
	_warm_total = paths.size()
	_warm_done = 0
	_warm_elapsed = 0.0
	_warm_ready = false
	if paths.is_empty():
		_warming = false
		_warm_ready = true
		_finish_warm()
		return
	# Count what's already warm (BootLoader should have finished this set).
	var already := 0
	for p in paths:
		if _path_is_warmed(str(p)):
			already += 1
	_warm_done = already
	if already >= paths.size() and _AssetCache.inflight_count() <= 0:
		_warming = false
		_warm_ready = true
		_finish_warm()
		return
	# Boot claimed full warm but a few leftovers remain (new files / misses) — warm quietly
	# unless Play is waiting, or leftovers are more than trivial.
	var leftovers := paths.size() - already
	var quiet := _BootCache.full_warm_completed and leftovers <= 2 and then_play_tab < 0
	_warming = true
	_AssetCache.warm_paths(paths)
	if not quiet:
		status_label.text = "Caching… %d/%d" % [_warm_done, maxi(_warm_total, 1)]
	_update_all_play_buttons()


func _tick_warm(delta: float) -> void:
	_warm_elapsed += delta
	_AssetCache.poll()
	# Decode a few GIF/still media items per frame (main-thread but spread out).
	var media_left := MediaImport.warm_paths_sync_media(_warm_paths, WARM_GIF_PER_FRAME)
	var inflight := _AssetCache.inflight_count()
	var cached := 0
	for p in _warm_paths:
		if _path_is_warmed(str(p)):
			cached += 1
	_warm_done = cached
	# Avoid flashing the big Caching X/Y after boot already did that pass.
	var leftovers := _warm_total - _warm_done
	var show_progress := (not _BootCache.full_warm_completed) or leftovers > 2 or _pending_play_tab >= 0
	if show_progress and status_label:
		status_label.text = "Caching… %d/%d" % [_warm_done, maxi(_warm_total, 1)]
	var timed_out := _warm_elapsed >= WARM_TIMEOUT_SEC
	# Finish when threaded jobs + media queue are drained (failed loads won't block forever).
	if (media_left <= 0 and inflight <= 0) or timed_out:
		if not timed_out:
			MediaImport.warm_paths_sync_media(_warm_paths, 128)
		_warming = false
		_warm_ready = true
		_finish_warm()


func _path_is_warmed(path: String) -> bool:
	var s := path.strip_edges()
	if s.is_empty():
		return true
	var t := MediaImport.detect_type(s)
	match t:
		"gif":
			return MediaImport.gif_cached(s)
		"image":
			return MediaImport.texture_cached(s)
		"hdri":
			return _AssetCache.has_texture(s)
		"scene3d":
			return _AssetCache.has_scene(s)
		"video":
			return true
		_:
			return true


func _finish_warm() -> void:
	_update_all_play_buttons()
	if _pending_play_tab >= 0:
		var tab := _pending_play_tab
		_pending_play_tab = -1
		status_label.text = "Cache ready"
		_begin_tab_play(tab)
	elif status_label:
		if _BootCache.full_warm_completed:
			# Boot already showed the Caching pass — keep status calm.
			_refresh_status()
		else:
			status_label.text = "Cache ready (%d assets)" % _warm_total


func _update_all_play_buttons() -> void:
	for tab in [TAB_ENV, TAB_MAIN, TAB_SCATTER, TAB_LIGHT]:
		_update_play_button(tab)


func _update_play_button(tab: int) -> void:
	var btn := _play_btn_for_tab(tab)
	if btn == null:
		return
	if _warming and _pending_play_tab == tab:
		btn.text = "Caching…"
	elif _autoplay[tab]:
		btn.text = "■ Stop"
	else:
		btn.text = "▶ Play"


func _play_btn_for_tab(tab: int) -> Button:
	match tab:
		TAB_ENV:
			return env_play_btn
		TAB_MAIN:
			return main_play_btn
		TAB_SCATTER:
			return scatter_play_btn
		TAB_LIGHT:
			return light_play_btn
	return null


func _step_tab(tab: int, delta_i: int) -> void:
	var entries := _entries_for_tab(tab)
	if entries.is_empty():
		return
	# Single-item lists still re-apply so Lighting Play refreshes the sky/panorama
	# instead of looking "stuck" with a no-op skip.
	var sel := _selection_for_tab(tab)
	if entries.size() == 1:
		sel = 0
	elif sel < 0:
		sel = 0 if delta_i >= 0 else entries.size() - 1
	else:
		sel = (sel + delta_i) % entries.size()
		if sel < 0:
			sel += entries.size()
	_set_selection_for_tab(tab, sel)
	_play_entry_at(tab, sel)


func _play_entry_at(tab: int, index: int) -> void:
	var entries := _entries_for_tab(tab)
	if index < 0 or index >= entries.size():
		return
	var entry: Dictionary = entries[index]
	match tab:
		TAB_ENV:
			_apply_environment(entry, index)
		TAB_MAIN:
			_apply_main(entry, index)
		TAB_SCATTER:
			_apply_scatter(entry, index)
		TAB_LIGHT:
			_apply_lighting(entry, index)


func _ensure_stage() -> int:
	for i in ShowDirector.items.size():
		var item: PlaylistItem = ShowDirector.items[i]
		if item.type == "scene3d" and str(item.params.get("style", "")) != "demo":
			if ShowDirector.current_index != i:
				ShowDirector.play_index(i, Transition.Mode.CUT, 0.0)
			return i
	var params := FlythroughAssetCatalog.blank_stage_params()
	ShowDirector.add_item_from_dict({
		"id": "stage",
		"type": "scene3d",
		"path": "",
		"duration": ShowDirector.default_item_duration,
		"params": params,
	}, true)
	return ShowDirector.current_index


func _stage_index() -> int:
	if ShowDirector.current_index >= 0 and ShowDirector.current_index < ShowDirector.items.size():
		var cur: PlaylistItem = ShowDirector.items[ShowDirector.current_index]
		if cur.type == "scene3d" and str(cur.params.get("style", "")) != "demo":
			return ShowDirector.current_index
	for i in ShowDirector.items.size():
		var item: PlaylistItem = ShowDirector.items[i]
		if item.type == "scene3d" and str(item.params.get("style", "")) != "demo":
			return i
	return -1


func _sync_selection_from_stage() -> void:
	var idx := _stage_index()
	if idx < 0:
		_sel_env = -1
		_sel_main = -1
		_sel_scatter = -1
		_sel_light = -1
		return
	var item: PlaylistItem = ShowDirector.items[idx]
	_sel_env = _index_of_config(_env_entries, item.params.get("environment", {}), "environment")
	_sel_main = _index_of_config(_main_entries, item.params.get("centerpiece", {}), "centerpiece")
	_sel_scatter = _index_of_config(_scatter_entries, item.params.get("scatter", {}), "scatter")
	_sel_light = _index_of_lighting(_light_entries, item.params.get("lighting", {}))


func _index_of_lighting(entries: Array[Dictionary], config: Variant) -> int:
	if not (config is Dictionary):
		return -1
	var cfg: Dictionary = config
	var preset := str(cfg.get("preset", "")).strip_edges()
	var hdri := str(cfg.get("hdri_path", "")).strip_edges().replace("\\", "/")
	if preset.is_empty() and hdri.is_empty():
		return -1
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var ecfg: Dictionary = entry.get("config", {}) as Dictionary
		if not preset.is_empty():
			if str(entry.get("id", "")) == preset:
				return i
			if str(ecfg.get("preset", "")).strip_edges() == preset:
				return i
		if not hdri.is_empty():
			var ehdri := str(ecfg.get("hdri_path", "")).strip_edges().replace("\\", "/")
			if not ehdri.is_empty() and ehdri == hdri:
				return i
	return -1


func _index_of_config(entries: Array[Dictionary], config: Variant, role: String) -> int:
	if not (config is Dictionary):
		return -1
	var cfg: Dictionary = config
	if FlythroughAssetCatalog.is_empty_layer_config(cfg):
		return -1
	var cfg_label := FlythroughAssetCatalog.short_label_for_config(cfg)
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var use_role := role
		if role.is_empty():
			use_role = "environment"
			if "roles" in entry:
				var roles: Array = entry.get("roles", []) as Array
				if "centerpiece" in roles and "scatter" not in roles:
					use_role = "centerpiece"
				elif "scatter" in roles and "centerpiece" not in roles:
					use_role = "scatter"
				elif "centerpiece" in roles:
					use_role = "centerpiece"
		var entry_cfg: Dictionary = FlythroughAssetCatalog.layer_config_from_entry(entry, use_role)
		if FlythroughAssetCatalog.short_label_for_config(entry_cfg) == cfg_label:
			if _configs_match_asset(entry_cfg, cfg):
				return i
	return -1


func _configs_match_asset(a: Dictionary, b: Dictionary) -> bool:
	var ap := str(a.get("path", ""))
	var bp := str(b.get("path", ""))
	if ap != "" and ap == bp:
		return true
	var asrc := str(a.get("source", ""))
	var bsrc := str(b.get("source", ""))
	if asrc != "" and asrc == bsrc:
		return true
	return FlythroughAssetCatalog.short_label_for_config(a) == FlythroughAssetCatalog.short_label_for_config(b) \
		and FlythroughAssetCatalog.short_label_for_config(a) != "?"


func _rebuild_all_lists() -> void:
	_rebuilding = true
	_rebuild_list(env_list, _env_entries, TAB_ENV, _sel_env)
	_rebuild_list(main_list, _main_entries, TAB_MAIN, _sel_main)
	_rebuild_list(scatter_list, _scatter_entries, TAB_SCATTER, _sel_scatter)
	_rebuild_list(light_list, _light_entries, TAB_LIGHT, _sel_light)
	_rebuilding = false
	_update_all_play_buttons()


func _ellipsis_middle(text: String, max_chars: int = 28) -> String:
	## Keep start + end of long filenames so extension / id stay readable.
	if text.length() <= max_chars:
		return text
	var keep := maxi(max_chars - 1, 3)
	var left := keep / 2
	var right := keep - left
	return text.substr(0, left) + "…" + text.substr(text.length() - right)


func _rebuild_list(container: VBoxContainer, entries: Array[Dictionary], tab: int, selected: int) -> void:
	for child in container.get_children():
		child.queue_free()
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.clip_contents = true
		var full_label := str(entry.get("label", "Asset"))
		var title := Button.new()
		title.text = _ellipsis_middle(full_label, 28)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.size_flags_stretch_ratio = 1.0
		title.alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.toggle_mode = true
		title.button_pressed = (i == selected)
		title.tooltip_text = "%s\nApply this asset" % full_label
		var idx := i
		title.pressed.connect(func() -> void:
			if _rebuilding:
				return
			_set_selection_for_tab(tab, idx)
			_play_entry_at(tab, idx)
		)
		row.add_child(title)
		var edit_btn := Button.new()
		edit_btn.text = "⚙"
		edit_btn.custom_minimum_size = Vector2(36, 28)
		edit_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
		edit_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		edit_btn.tooltip_text = "Edit name, asset, scale, position, and environment tiling"
		edit_btn.pressed.connect(func() -> void: _open_edit_item(tab, idx))
		row.add_child(edit_btn)
		var del := Button.new()
		del.text = "✕"
		del.custom_minimum_size = Vector2(32, 28)
		del.size_flags_horizontal = Control.SIZE_SHRINK_END
		del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		del.tooltip_text = "Remove from this list"
		del.pressed.connect(func() -> void: _remove_entry(tab, idx))
		row.add_child(del)
		container.add_child(row)


func _remove_entry(tab: int, index: int) -> void:
	var entries := _entries_for_tab(tab)
	if index < 0 or index >= entries.size():
		return
	var was_selected := _selection_for_tab(tab) == index
	entries.remove_at(index)
	if was_selected:
		_set_selection_for_tab(tab, -1)
		_clear_stage_layer(tab)
	elif _selection_for_tab(tab) > index:
		_set_selection_for_tab(tab, _selection_for_tab(tab) - 1)
	_rebuild_all_lists()
	_refresh_status()
	_schedule_autosave()


func _clear_stage_layer(tab: int) -> void:
	var idx := _stage_index()
	if idx < 0:
		return
	_suppress_playlist_ui = true
	match tab:
		TAB_ENV:
			ShowDirector.set_flythrough_layer("environment", {"source": "primitive:box_corridor"}, idx)
		TAB_MAIN:
			ShowDirector.set_flythrough_layer("centerpiece", FlythroughAssetCatalog.empty_centerpiece_config(), idx)
		TAB_SCATTER:
			ShowDirector.set_flythrough_layer("scatter", FlythroughAssetCatalog.empty_scatter_config(), idx)
		TAB_LIGHT:
			ShowDirector.set_flythrough_layer("lighting", FlythroughAssetCatalog.default_lighting_config(), idx)
	_suppress_playlist_ui = false


func _entries_for_tab(tab: int) -> Array[Dictionary]:
	match tab:
		TAB_ENV:
			return _env_entries
		TAB_MAIN:
			return _main_entries
		TAB_SCATTER:
			return _scatter_entries
		TAB_LIGHT:
			return _light_entries
	return _env_entries


func _selection_for_tab(tab: int) -> int:
	match tab:
		TAB_ENV:
			return _sel_env
		TAB_MAIN:
			return _sel_main
		TAB_SCATTER:
			return _sel_scatter
		TAB_LIGHT:
			return _sel_light
	return -1


func _set_selection_for_tab(tab: int, index: int) -> void:
	match tab:
		TAB_ENV:
			_sel_env = index
		TAB_MAIN:
			_sel_main = index
		TAB_SCATTER:
			_sel_scatter = index
		TAB_LIGHT:
			_sel_light = index


func _refresh_status() -> void:
	var idx := _stage_index()
	if idx < 0:
		status_label.text = "No stage loaded"
		return
	var item: PlaylistItem = ShowDirector.items[idx]
	var env_s := FlythroughAssetCatalog.short_label_for_config(item.params.get("environment", {}))
	var main_s := FlythroughAssetCatalog.short_label_for_config(item.params.get("centerpiece", {}))
	var sc_s := FlythroughAssetCatalog.short_label_for_config(item.params.get("scatter", {}))
	var lt_s := FlythroughAssetCatalog.short_label_for_config(item.params.get("lighting", {}))
	if FlythroughAssetCatalog.is_empty_layer_config(item.params.get("centerpiece", {})):
		main_s = "—"
	if FlythroughAssetCatalog.is_empty_layer_config(item.params.get("scatter", {})):
		sc_s = "—"
	if lt_s == "?":
		lt_s = "—"
	status_label.text = "Env %s · Main %s · Scatter %s · Light %s" % [env_s, main_s, sc_s, lt_s]


func _set_layer_dialog_filters(for_hdri: bool) -> void:
	if for_hdri:
		layer_file_dialog.filters = PackedStringArray([
			"*.hdr,*.exr,*.png,*.jpg,*.jpeg ; HDR / panorama sky",
		])
	else:
		layer_file_dialog.filters = PackedStringArray([
			"*.glb,*.gltf,*.fbx,*.tscn,*.png,*.jpg,*.jpeg,*.webp,*.bmp,*.gif,*.mp4,*.webm,*.ogv,*.mov,*.avi ; Models, images, GIF & video",
			"*.glb,*.gltf,*.fbx,*.tscn ; 3D Models",
			"*.png,*.jpg,*.jpeg,*.webp,*.bmp,*.gif ; Images & GIF",
			"*.mp4,*.webm,*.ogv,*.mov,*.avi,*.gif ; Video & GIF",
		])


func _pick_layer_file(layer_id: String) -> void:
	_layer_pick = layer_id
	_replace_tab = -1
	_replace_index = -1
	var titles := {
		"environment": "Add environment (models, images, GIF, video)",
		"scatter": "Add scatter props (models, images, GIF, video)",
		"centerpiece": "Add main character (models, images, GIF, video)",
		"lighting": "Add HDRI / panorama sky",
	}
	_set_layer_dialog_filters(layer_id == "lighting")
	# Multi-select for add flows (Ctrl/Shift in native dialog).
	layer_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	layer_file_dialog.title = str(titles.get(layer_id, "Choose asset"))
	_file_pick_handled = false
	layer_file_dialog.popup_centered()


func _pick_replace(tab: int, index: int) -> void:
	_replace_tab = tab
	_replace_index = index
	_layer_pick = "replace"
	_set_layer_dialog_filters(tab == TAB_LIGHT)
	# Replace keeps multi-select practical: first file replaces, extras append.
	layer_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	layer_file_dialog.title = "Replace asset (multi-select appends extras)"
	_file_pick_handled = false
	layer_file_dialog.popup_centered()


func _on_layer_file_selected(path: String) -> void:
	## Single-file signal (some platforms); treat as one-item multi-add.
	_on_layer_files_selected(PackedStringArray([path]))


func _on_layer_files_selected(paths: PackedStringArray) -> void:
	if _file_pick_handled:
		return
	if _layer_pick.is_empty() or paths.is_empty():
		return
	_file_pick_handled = true
	var pick := _layer_pick
	var replace_tab := _replace_tab
	var replace_index := _replace_index
	_layer_pick = ""
	_replace_tab = -1
	_replace_index = -1

	if pick == "replace" and replace_tab >= 0 and replace_index >= 0:
		var first := MediaImport.to_project_or_absolute(paths[0])
		MediaImport.warm_path(first)
		_AssetCache.prefetch_paths([first])
		_replace_entry_with_file(replace_tab, replace_index, first, paths[0].get_file().get_basename())
		for i in range(1, paths.size()):
			if replace_tab == TAB_LIGHT:
				# Append extras as new HDRI rows (same as lighting add).
				var extra := MediaImport.to_project_or_absolute(paths[i])
				MediaImport.warm_path(extra)
				_AssetCache.prefetch_paths([extra])
				var elabel := paths[i].get_file().get_basename()
				_light_entries.append({
					"id": "user_hdri_%s" % elabel,
					"label": elabel,
					"user_added": true,
					"config": FlythroughAssetCatalog.hdri_lighting_config(
						"user_hdri_%s" % elabel,
						extra
					),
				})
			else:
				_append_user_file(replace_tab, paths[i], false)
		_rebuild_all_lists()
		_schedule_autosave()
		_warm_ready = false
		_start_warm_all(-1)
		_refresh_edit_dialog_after_replace(replace_tab, replace_index)
		return

	if pick == "lighting":
		var last_entry: Dictionary = {}
		for path in paths:
			var resolved := MediaImport.to_project_or_absolute(path)
			MediaImport.warm_path(resolved)
			_AssetCache.prefetch_paths([resolved])
			var label := path.get_file().get_basename()
			var light_entry := {
				"id": "user_hdri_%s" % label,
				"label": label,
				"user_added": true,
				"config": FlythroughAssetCatalog.hdri_lighting_config(
					"user_hdri_%s" % label,
					resolved
				),
			}
			_light_entries.append(light_entry)
			last_entry = light_entry
		if not last_entry.is_empty():
			_sel_light = _light_entries.size() - 1
			_rebuild_all_lists()
			_apply_lighting(last_entry, _sel_light)
		_warm_ready = false
		_start_warm_all(-1)
		return

	var tab := TAB_ENV
	match pick:
		"environment":
			tab = TAB_ENV
		"centerpiece":
			tab = TAB_MAIN
		"scatter":
			tab = TAB_SCATTER
		_:
			return
	var last_idx := -1
	for path in paths:
		var resolved_pre := MediaImport.to_project_or_absolute(path)
		MediaImport.warm_path(resolved_pre)
		_AssetCache.prefetch_paths([resolved_pre])
		last_idx = _append_user_file(tab, path, false)
	if last_idx >= 0:
		_rebuild_all_lists()
		_play_entry_at(tab, last_idx)
	_warm_ready = false
	_start_warm_all(-1)


func _append_user_file(tab: int, path: String, rebuild_and_play: bool = true) -> int:
	## Add one user file to Env / Main / Scatter. Returns new index or -1.
	var resolved := MediaImport.to_project_or_absolute(path)
	var media_type := MediaImport.detect_type(resolved)
	if media_type.is_empty():
		push_warning("PlaylistSidebar: unsupported file %s" % path)
		return -1
	if tab == TAB_LIGHT:
		return -1
	var label := path.get_file().get_basename()
	var entry := {
		"id": "user_%s" % label,
		"label": label,
		"user_added": true,
		"config": {"path": resolved},
	}
	match tab:
		TAB_ENV:
			entry["roles"] = ["environment"]
			_env_entries.append(entry)
			_sel_env = _env_entries.size() - 1
			if rebuild_and_play:
				_rebuild_all_lists()
				_apply_environment(entry, _sel_env)
			return _sel_env
		TAB_MAIN:
			entry["roles"] = ["centerpiece", "scatter"]
			_main_entries.append(entry)
			_sel_main = _main_entries.size() - 1
			if rebuild_and_play:
				_rebuild_all_lists()
				_apply_main(entry, _sel_main)
			return _sel_main
		TAB_SCATTER:
			entry["roles"] = ["scatter", "centerpiece"]
			_scatter_entries.append(entry)
			_sel_scatter = _scatter_entries.size() - 1
			if rebuild_and_play:
				_rebuild_all_lists()
				_apply_scatter(entry, _sel_scatter)
			return _sel_scatter
	return -1


func _replace_entry_with_file(tab: int, index: int, resolved: String, label: String) -> void:
	var entries := _entries_for_tab(tab)
	if index < 0 or index >= entries.size():
		return
	var entry: Dictionary = entries[index]
	var keep_scale := _entry_scale_snapshot(entry)
	var keep_expr := _entry_scale_expr(entry)
	var keep_offset := _entry_user_offset(entry)
	var keep_tiles := _entry_tile_counts(entry)
	var keep_mat := _entry_mat_override(entry)
	var keep_blend := _entry_blend_mode(entry)
	if tab == TAB_LIGHT:
		entry["label"] = label
		entry["user_added"] = true
		entry["id"] = "user_hdri_%s" % label
		entry["config"] = FlythroughAssetCatalog.hdri_lighting_config(entry["id"], resolved)
	else:
		if MediaImport.detect_type(resolved).is_empty():
			push_warning("PlaylistSidebar: unsupported replace file %s" % resolved)
			return
		entry["label"] = label
		var cfg: Dictionary = {"path": resolved, "user_scale": keep_scale, "user_offset": _offset_to_dict(keep_offset)}
		if not keep_mat.is_empty():
			cfg["mat_override"] = keep_mat
			entry["mat_override"] = keep_mat
		cfg["blend_mode"] = keep_blend
		entry["blend_mode"] = keep_blend
		if tab == TAB_ENV:
			FlythroughAssetCatalog.stamp_env_tile_counts(cfg, keep_tiles)
			FlythroughAssetCatalog.stamp_env_tile_counts(entry, keep_tiles)
		if keep_expr.is_empty():
			entry.erase("user_scale_expr")
		else:
			cfg["user_scale_expr"] = keep_expr
			entry["user_scale_expr"] = keep_expr
		entry["config"] = cfg
		entry["user_added"] = true
		entry["id"] = "user_%s" % label
		entry["user_scale"] = keep_scale
		entry["user_offset"] = _offset_to_dict(keep_offset)
	_set_selection_for_tab(tab, index)
	_rebuild_all_lists()
	_play_entry_at(tab, index)


func _refresh_edit_dialog_after_replace(tab: int, index: int) -> void:
	if not _edit_from_modal_replace:
		return
	_edit_from_modal_replace = false
	if _edit_dialog == null:
		return
	var entries := _entries_for_tab(tab)
	if index < 0 or index >= entries.size():
		return
	_edit_tab = tab
	_edit_index = index
	var entry: Dictionary = entries[index]
	_edit_name.text = str(entry.get("label", "Asset"))
	_edit_asset_label.text = _entry_asset_caption(entry)
	_edit_asset_label.tooltip_text = _edit_asset_label.text
	if _edit_scale_row != null and tab != TAB_LIGHT:
		_edit_scale_busy = true
		var raw: Variant = _entry_scale_raw(entry)
		if raw is String:
			SliderSpinLinkScr.set_expr(_edit_scale_slider, str(raw), false)
		else:
			SliderSpinLinkScr.set_expr(_edit_scale_slider, str(snappedf(float(raw), 0.001)), false)
		_edit_scale_busy = false
	if _edit_offset_box != null and tab != TAB_LIGHT:
		_edit_offset_busy = true
		var off := _entry_user_offset(entry)
		if _edit_offset_x:
			SliderSpinLinkScr.set_expr(_edit_offset_x, str(snappedf(off.x, 0.001)), false)
		if _edit_offset_y:
			SliderSpinLinkScr.set_expr(_edit_offset_y, str(snappedf(off.y, 0.001)), false)
		if _edit_offset_z:
			SliderSpinLinkScr.set_expr(_edit_offset_z, str(snappedf(off.z, 0.001)), false)
		_edit_offset_busy = false
	_sync_edit_mat_blend_rows(tab, entry)
	if not _edit_dialog.visible:
		_edit_dialog.popup_centered()


func step_prev() -> void:
	_ensure_stage()
	_step_tab(asset_tabs.current_tab, -1)


func step_next() -> void:
	_ensure_stage()
	_step_tab(asset_tabs.current_tab, 1)


func cycle_environment(delta_i: int) -> void:
	## Gamepad / hotkey: cycle Env list and apply (same as clicking a row).
	_ensure_stage()
	_step_tab(TAB_ENV, delta_i)


func cycle_main(delta_i: int) -> void:
	## Gamepad / hotkey: cycle Main character list and apply.
	_ensure_stage()
	_step_tab(TAB_MAIN, delta_i)


func cycle_scatter(delta_i: int) -> void:
	## Gamepad / hotkey: cycle Scatter list and apply.
	_ensure_stage()
	_step_tab(TAB_SCATTER, delta_i)


func cycle_lighting(delta_i: int) -> void:
	## Gamepad / hotkey: cycle Lighting / HDRI list and apply.
	_ensure_stage()
	_step_tab(TAB_LIGHT, delta_i)


func toggle_tab_play() -> void:
	_toggle_tab_autoplay(asset_tabs.current_tab)


func _on_clear() -> void:
	for i in _autoplay.size():
		_autoplay[i] = false
		_elapsed[i] = 0.0
	ShowDirector.set_autoplay(false)
	ShowDirector.clear_playlist()
	_sel_env = -1
	_sel_main = -1
	_sel_scatter = -1
	_sel_light = -1
	status_label.text = "No stage loaded"
	_rebuild_all_lists()
	_refresh_status()
	_save_session_now()


func _on_reset_to_defaults() -> void:
	_reset_sidebar_entry_customizations()
	if _edit_dialog != null and is_instance_valid(_edit_dialog) and _edit_dialog.visible:
		_edit_dialog.hide()
		_clear_edit_dialog_target()
	ShowDirector.reset_stage_to_defaults()
	_sync_fly_speed_from_stage()
	_sync_path_style_from_stage()
	_sync_env_scale_from_stage()
	_sync_scatter_settings_from_stage()
	_scatter_settings_busy = true
	_select_scatter_layout_no_signal("random")
	if scatter_density:
		SliderSpinLinkScr.set_spin_driven(scatter_density, 18.0)
	if scatter_global_scale:
		SliderSpinLinkScr.set_spin_driven(scatter_global_scale, 1.0)
	_scatter_settings_busy = false
	if env_scale:
		var sl := SliderSpinLinkScr.slider_of_spin(env_scale)
		if sl:
			SliderSpinLinkScr.reset_to_number(sl, 1.0, false)
		else:
			SliderSpinLinkScr.set_spin_driven(env_scale, 1.0)
	_save_session_now()
	if status_label:
		status_label.text = "Stage + effects reset to defaults"


func _reset_sidebar_entry_customizations() -> void:
	_reset_entries_customizations(_env_entries, "environment")
	_reset_entries_customizations(_main_entries, "centerpiece")
	_reset_entries_customizations(_scatter_entries, "scatter")


func _reset_entries_customizations(entries: Array[Dictionary], layer_id: String) -> void:
	for i in entries.size():
		var entry: Dictionary = entries[i]
		for k in ["user_scale", "user_scale_expr", "user_offset", "mat_override", "blend_mode", "tile_x", "tile_y", "tile_z", "tile_cells"]:
			entry.erase(k)
		var cfg: Dictionary = {}
		if entry.get("config", null) is Dictionary:
			cfg = (entry["config"] as Dictionary).duplicate(true)
		entry["config"] = FlythroughAssetCatalog.strip_layer_customizations(cfg, layer_id)
		entries[i] = entry
