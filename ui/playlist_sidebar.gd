extends PanelContainer

## Left sidebar — icon tabs for Env / Main / Scatter / Lighting with independent timers.

signal present_requested

const TAB_ENV := 0
const TAB_MAIN := 1
const TAB_SCATTER := 2
const TAB_LIGHT := 3

@onready var show_label: Label = $Margin/Column/Header/ShowLabel
@onready var status_label: Label = $Margin/Column/Header/StatusLabel
@onready var fly_speed: SpinBox = $Margin/Column/Header/FlyRow/FlySpeed
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


func _ready() -> void:
	clear_button.pressed.connect(_on_clear)
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
	fly_speed.value_changed.connect(_on_fly_speed_changed)
	env_scale.value_changed.connect(_on_env_scale_changed)
	env_duration.value_changed.connect(func(_v: float) -> void: _schedule_autosave())
	main_duration.value_changed.connect(func(_v: float) -> void: _schedule_autosave())
	scatter_duration.value_changed.connect(func(_v: float) -> void: _schedule_autosave())
	light_duration.value_changed.connect(func(_v: float) -> void: _schedule_autosave())
	layer_file_dialog.file_selected.connect(_on_layer_file_selected)
	layer_file_dialog.files_selected.connect(_on_layer_files_selected)
	ShowDirector.show_loaded.connect(_on_show_loaded)
	ShowDirector.item_changed.connect(_on_item_changed)
	ShowDirector.playlist_changed.connect(_on_playlist_changed)
	_setup_autosave_timer()
	_setup_tab_icons()
	_load_catalog_entries()
	_restore_sidebar_from_session()
	_rebuild_all_lists()
	_refresh_status()
	_sync_fly_speed_from_stage()
	_sync_env_scale_from_stage()
	_update_all_play_buttons()
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
	var tab_idx := 0
	if env_duration != null and is_instance_valid(env_duration):
		env_dur = float(env_duration.value)
	if main_duration != null and is_instance_valid(main_duration):
		main_dur = float(main_duration.value)
	if scatter_duration != null and is_instance_valid(scatter_duration):
		scatter_dur = float(scatter_duration.value)
	if light_duration != null and is_instance_valid(light_duration):
		light_dur = float(light_duration.value)
	if env_scale != null and is_instance_valid(env_scale):
		scale_val = float(env_scale.value)
	if fly_speed != null and is_instance_valid(fly_speed):
		speed_val = float(fly_speed.value)
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
			"env_duration": env_dur,
			"main_duration": main_dur,
			"scatter_duration": scatter_dur,
			"light_duration": light_dur,
			"env_scale": scale_val,
			"fly_speed": speed_val,
			"autoplay": [_autoplay[TAB_ENV], _autoplay[TAB_MAIN], _autoplay[TAB_SCATTER], _autoplay[TAB_LIGHT]],
			"current_tab": tab_idx,
		},
		"items": ShowDirector.items_to_dicts(),
		"current_index": ShowDirector.current_index,
		"cues": ShowDirector.cues.duplicate(true) if ShowDirector.cues is Array else [],
		"effects": ShowDirector.show_data.get("effects", ["ascii", "particles", "feedback", "glitch"]),
	}


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
		env_duration.set_value_no_signal(clampf(float(sb.get("env_duration", env_duration.value)), 1.0, 600.0))
	if main_duration:
		main_duration.set_value_no_signal(clampf(float(sb.get("main_duration", main_duration.value)), 1.0, 600.0))
	if scatter_duration:
		scatter_duration.set_value_no_signal(clampf(float(sb.get("scatter_duration", scatter_duration.value)), 1.0, 600.0))
	if light_duration:
		light_duration.set_value_no_signal(clampf(float(sb.get("light_duration", light_duration.value)), 1.0, 600.0))
	if env_scale and sb.has("env_scale"):
		env_scale.set_value_no_signal(clampf(roundf(float(sb["env_scale"])), 1.0, 50.0))
	if fly_speed and sb.has("fly_speed"):
		fly_speed.set_value_no_signal(roundf(float(sb["fly_speed"])))
	if asset_tabs and sb.has("current_tab"):
		asset_tabs.current_tab = clampi(int(sb["current_tab"]), 0, asset_tabs.get_tab_count() - 1)
	# Do not resume autoplay on boot — restore timers/lists only.
	_session_restored = true
	_restoring_session = false


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


func _process(delta: float) -> void:
	for tab in [TAB_ENV, TAB_MAIN, TAB_SCATTER, TAB_LIGHT]:
		if not _autoplay[tab]:
			continue
		_elapsed[tab] += delta
		var step := _duration_for_tab(tab)
		if _elapsed[tab] < step:
			continue
		_elapsed[tab] = 0.0
		_step_tab(tab, 1)


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
	_sync_env_scale_from_stage()
	_schedule_autosave()


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
	_sync_env_scale_from_stage()
	_schedule_autosave()


func _on_playlist_changed() -> void:
	if _suppress_playlist_ui or _restoring_session:
		return
	if not _any_tab_autoplaying():
		_sync_selection_from_stage()
	_rebuild_all_lists()
	_refresh_status()
	_sync_fly_speed_from_stage()
	_sync_env_scale_from_stage()
	_schedule_autosave()


func _on_fly_speed_changed(value: float) -> void:
	var idx := _ensure_stage()
	if idx < 0:
		return
	ShowDirector.set_active_cue_param("fly_speed", value)
	# Also keep the playlist alias used by configure_from_params.
	if idx < ShowDirector.items.size():
		ShowDirector.items[idx].params["speed"] = value
	_schedule_autosave()


func _on_env_scale_changed(value: float) -> void:
	var idx := _ensure_stage()
	if idx < 0:
		return
	var scale_val := clampf(roundf(value), 1.0, 50.0)
	if idx < ShowDirector.items.size():
		var params: Dictionary = ShowDirector.items[idx].params
		var env_cfg: Dictionary = (params.get("environment", {}) as Dictionary).duplicate(true)
		env_cfg["user_scale"] = scale_val
		params["environment"] = env_cfg
	# Live scale only — avoid full env reload.
	ShowDirector.set_active_cue_param("env_scale", scale_val)
	_schedule_autosave()


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
	fly_speed.set_value_no_signal(roundf(speed_val))


func _sync_env_scale_from_stage() -> void:
	if env_scale == null:
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
	env_scale.set_value_no_signal(roundf(scale_val))


func _apply_environment(entry: Dictionary, force_sel: int = -1) -> void:
	var idx := _ensure_stage()
	if idx < 0:
		return
	var cfg: Dictionary = FlythroughAssetCatalog.layer_config_from_entry(entry, "environment")
	if env_scale:
		cfg["user_scale"] = float(env_scale.value)
	_suppress_playlist_ui = true
	ShowDirector.set_flythrough_layer("environment", cfg, idx)
	_suppress_playlist_ui = false
	_sel_env = _resolve_selection_after_apply(_env_entries, force_sel, cfg, "environment")
	_rebuild_all_lists()
	_refresh_status()
	status_label.text = "Env: %s" % str(entry.get("label", "?"))
	_schedule_autosave()


func _apply_main(entry: Dictionary, force_sel: int = -1) -> void:
	var idx := _ensure_stage()
	if idx < 0:
		return
	var cfg: Dictionary = FlythroughAssetCatalog.layer_config_from_entry(entry, "centerpiece")
	_suppress_playlist_ui = true
	ShowDirector.set_flythrough_layer("centerpiece", cfg, idx)
	_suppress_playlist_ui = false
	_sel_main = _resolve_selection_after_apply(_main_entries, force_sel, cfg, "centerpiece")
	_rebuild_all_lists()
	_refresh_status()
	status_label.text = "Main: %s" % str(entry.get("label", "?"))
	_schedule_autosave()


func _apply_scatter(entry: Dictionary, force_sel: int = -1) -> void:
	var idx := _ensure_stage()
	if idx < 0:
		return
	var cfg: Dictionary = FlythroughAssetCatalog.layer_config_from_entry(entry, "scatter", 18)
	_suppress_playlist_ui = true
	ShowDirector.set_flythrough_layer("scatter", cfg, idx)
	_suppress_playlist_ui = false
	_sel_scatter = _resolve_selection_after_apply(_scatter_entries, force_sel, cfg, "scatter")
	_rebuild_all_lists()
	_refresh_status()
	status_label.text = "Scatter: %s" % str(entry.get("label", "?"))
	_schedule_autosave()


func _apply_lighting(entry: Dictionary, force_sel: int = -1) -> void:
	var idx := _ensure_stage()
	if idx < 0:
		return
	var cfg: Dictionary = (entry.get("config", {}) as Dictionary).duplicate(true)
	_suppress_playlist_ui = true
	ShowDirector.set_flythrough_layer("lighting", cfg, idx)
	_suppress_playlist_ui = false
	if force_sel >= 0 and force_sel < _light_entries.size():
		_sel_light = force_sel
	else:
		var matched := _index_of_lighting(_light_entries, cfg)
		_sel_light = matched if matched >= 0 else _sel_light
	_rebuild_all_lists()
	_refresh_status()
	status_label.text = "Light: %s" % str(entry.get("label", "?"))
	_schedule_autosave()


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


func _duration_for_tab(tab: int) -> float:
	var raw := 8.0
	match tab:
		TAB_ENV:
			if env_duration:
				raw = float(env_duration.value)
		TAB_MAIN:
			if main_duration:
				raw = float(main_duration.value)
		TAB_SCATTER:
			if scatter_duration:
				raw = float(scatter_duration.value)
		TAB_LIGHT:
			if light_duration:
				raw = float(light_duration.value)
	return clampf(raw, 1.0, 600.0)


func _toggle_tab_autoplay(tab: int) -> void:
	_ensure_stage()
	if _autoplay[tab]:
		_set_tab_autoplay(tab, false)
		return
	var entries := _entries_for_tab(tab)
	if entries.is_empty():
		status_label.text = "Nothing to play in this tab"
		return
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


func _update_all_play_buttons() -> void:
	for tab in [TAB_ENV, TAB_MAIN, TAB_SCATTER, TAB_LIGHT]:
		_update_play_button(tab)


func _update_play_button(tab: int) -> void:
	var btn := _play_btn_for_tab(tab)
	if btn == null:
		return
	btn.text = "■ Stop" if _autoplay[tab] else "▶ Play"


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
	var sel := _selection_for_tab(tab)
	if sel < 0:
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
	var preset := str(cfg.get("preset", ""))
	if preset.is_empty():
		return -1
	for i in entries.size():
		var entry: Dictionary = entries[i]
		if str(entry.get("id", "")) == preset:
			return i
		var ecfg: Dictionary = entry.get("config", {}) as Dictionary
		if str(ecfg.get("preset", "")) == preset:
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


func _rebuild_list(container: VBoxContainer, entries: Array[Dictionary], tab: int, selected: int) -> void:
	for child in container.get_children():
		child.queue_free()
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := Button.new()
		title.text = str(entry.get("label", "Asset"))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.toggle_mode = true
		title.button_pressed = (i == selected)
		title.tooltip_text = "Apply this asset"
		var idx := i
		title.pressed.connect(func() -> void:
			if _rebuilding:
				return
			_set_selection_for_tab(tab, idx)
			_play_entry_at(tab, idx)
		)
		row.add_child(title)
		var replace := Button.new()
		replace.text = "↻"
		replace.custom_minimum_size = Vector2(36, 0)
		replace.tooltip_text = "Replace this item with another file"
		replace.disabled = (tab == TAB_LIGHT)
		replace.pressed.connect(func() -> void: _pick_replace(tab, idx))
		row.add_child(replace)
		var del := Button.new()
		del.text = "✕"
		del.custom_minimum_size = Vector2(32, 0)
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
	if tab == TAB_LIGHT:
		return
	_replace_tab = tab
	_replace_index = index
	_layer_pick = "replace"
	_set_layer_dialog_filters(false)
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
		_replace_entry_with_file(replace_tab, replace_index, first, paths[0].get_file().get_basename())
		for i in range(1, paths.size()):
			_append_user_file(replace_tab, paths[i], false)
		_rebuild_all_lists()
		_schedule_autosave()
		return

	if pick == "lighting":
		var last_entry: Dictionary = {}
		for path in paths:
			var resolved := MediaImport.to_project_or_absolute(path)
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
		last_idx = _append_user_file(tab, path, false)
	if last_idx >= 0:
		_rebuild_all_lists()
		_play_entry_at(tab, last_idx)


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
	if MediaImport.detect_type(resolved).is_empty() and tab != TAB_LIGHT:
		push_warning("PlaylistSidebar: unsupported replace file %s" % resolved)
		return
	var entry: Dictionary = entries[index]
	entry["label"] = label
	entry["config"] = {"path": resolved}
	entry["user_added"] = true
	entry["id"] = "user_%s" % label
	_set_selection_for_tab(tab, index)
	_rebuild_all_lists()
	_play_entry_at(tab, index)


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
