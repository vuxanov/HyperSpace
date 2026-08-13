extends Control

## First scene: fully warm playlist assets + load main UI, then hand off.
## Splash owns the big "Caching X/Y" pass — main must not re-run it.

const _AssetCache := preload("res://core/asset_cache.gd")
const _BootCache := preload("res://core/boot_cache.gd")

const MAIN_SCENE_PATH := "res://ui/main.tscn"
const MEDIA_PER_FRAME := 1
## Safety only — prefer waiting for full warm over early first paint.
const BOOT_TIMEOUT_SEC := 300.0
const MIN_SPLASH_SEC := 0.4
const READY_HOLD_SEC := 0.15
## Same-frame completion bursts still tick 1, 2, 3… on the label.
const REVEAL_STEP_SEC := 0.04
const NAME_CYCLE_SEC := 0.12

@onready var brand_label: Label = $Center/Column/Brand
@onready var status_label: Label = $Center/Column/Status
@onready var progress_bar: ProgressBar = $Center/Column/Progress
@onready var spinner: Control = $Center/Column/SpinnerRow/Spinner
@onready var detail_label: Label = $Center/Column/Detail

var _asset_paths: Array = []
var _shader_paths: Array = []
var _shaders_done: int = 0
var _main_ready: bool = false
var _main_frac: float = 0.0
var _main_packed: PackedScene = null
var _assets_kicked: bool = false
var _finished: bool = false
var _elapsed: float = 0.0
var _spin_angle: float = 0.0
var _status_phase: String = "Starting…"
## Paths that have finished (warmed, failed, or skipped). Only grows.
var _finished_keys: Dictionary = {}
## Finished paths not yet shown on the K / N label (FIFO).
var _reveal_queue: Array = []
var _reveal_accum: float = 0.0
var _asset_done_shown: int = 0
var _last_revealed_name: String = ""
var _name_cycle_idx: int = 0
var _name_cycle_accum: float = 0.0
var _bar_floor: float = 0.0
var _asset_total: int = 0


func _ready() -> void:
	get_tree().root.gui_embed_subwindows = false
	var win := get_window()
	win.size = Vector2i(1700, 950)
	win.min_size = Vector2i(1200, 700)
	_BootCache.full_warm_completed = false
	_shader_paths = _BootCache.collect_shader_paths()
	_asset_paths = _BootCache.collect_critical_paths()
	_asset_total = _asset_paths.size()
	# Threaded load of the heavy main control surface (parallel with asset warm).
	var err := ResourceLoader.load_threaded_request(MAIN_SCENE_PATH, "PackedScene", true)
	if err != OK:
		push_warning("BootLoader: threaded main request failed (%s)" % err)
	_kick_asset_warm()
	_refresh_finished_assets(false)
	_process_reveal(0.0)
	_update_ui(0.0, "Loading assets %d / %d" % [_asset_done_shown, _asset_total], _detail_name())
	set_process(true)


func _kick_asset_warm() -> void:
	if _assets_kicked:
		return
	_assets_kicked = true
	if _asset_paths.is_empty():
		return
	_AssetCache.warm_paths(_asset_paths)
	# Kick media/GIF warm for paths that need main-thread decode (budgeted in _process).
	for p in _asset_paths:
		var t := MediaImport.detect_type(str(p))
		if t == "video":
			MediaImport.warm_path(str(p))


func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta
	_spin_angle = fmod(_spin_angle + delta * 4.2, TAU)
	if spinner:
		spinner.rotation = _spin_angle

	_AssetCache.poll()
	_poll_main_scene()
	_warm_shaders_step()
	var inflight := _AssetCache.inflight_count()
	var media_left := MediaImport.warm_paths_sync_media(_asset_paths, MEDIA_PER_FRAME)
	var assets_idle := inflight <= 0 and media_left <= 0
	_refresh_finished_assets(assets_idle)
	_process_reveal(delta)
	_tick_name_cycle(delta)

	var asset_units := _asset_visual_units()
	var shader_total := float(_shader_paths.size())
	var asset_total_f := float(_asset_total)
	var den := asset_total_f + shader_total + 1.0
	if den < 1.0:
		den = 1.0
	var overall := clampf((asset_units + float(_shaders_done) + _main_frac) / den, 0.0, 0.999)
	overall = maxf(overall, _bar_floor)
	_bar_floor = overall

	var detail := _detail_name()
	_status_phase = _status_for(assets_idle)
	_update_ui(overall, _status_phase, detail)

	var shaders_idle := _shaders_done >= _shader_paths.size()
	var reveal_idle := _reveal_queue.is_empty() and _asset_done_shown >= _asset_total
	var timed_out := _elapsed >= BOOT_TIMEOUT_SEC
	var min_time_ok := _elapsed >= MIN_SPLASH_SEC
	# Do not leave the big Caching pass for main — wait for assets unless safety timeout.
	if timed_out or (assets_idle and reveal_idle and shaders_idle and _main_ready and min_time_ok):
		if timed_out and media_left > 0:
			MediaImport.warm_paths_sync_media(_asset_paths, 8)
			_refresh_finished_assets(true)
		if timed_out:
			_flush_reveal_queue()
		if (assets_idle and reveal_idle) or timed_out:
			_try_finish(assets_idle or timed_out)


func _refresh_finished_assets(mark_idle_rest: bool) -> void:
	for p in _asset_paths:
		var s := str(p)
		if _finished_keys.has(s):
			continue
		var now_done := _BootCache.path_is_warmed(s) or _AssetCache.has_failed(s) \
				or MediaImport.warm_gave_up(s)
		if now_done or mark_idle_rest:
			_finished_keys[s] = true
			_reveal_queue.append(s)


func _process_reveal(delta: float) -> void:
	## At most one K increment per interval so a poll burst still reads 1, 2, 3…
	if _reveal_queue.is_empty():
		_reveal_accum = minf(_reveal_accum + delta, REVEAL_STEP_SEC)
		return
	_reveal_accum += delta
	if _asset_done_shown > 0 and _reveal_accum < REVEAL_STEP_SEC:
		return
	var s := str(_reveal_queue.pop_front())
	_asset_done_shown += 1
	_last_revealed_name = _file_label(s)
	_reveal_accum = 0.0


func _flush_reveal_queue() -> void:
	while not _reveal_queue.is_empty():
		var s := str(_reveal_queue.pop_front())
		_asset_done_shown += 1
		_last_revealed_name = _file_label(s)
	_asset_done_shown = maxi(_asset_done_shown, _asset_total)


func _tick_name_cycle(delta: float) -> void:
	_name_cycle_accum += delta
	if _name_cycle_accum < NAME_CYCLE_SEC:
		return
	_name_cycle_accum = 0.0
	_name_cycle_idx += 1


func _asset_visual_units() -> float:
	## Shown K plus in-flight fraction of paths not yet finished. Floor keeps the bar monotonic.
	var units := float(_asset_done_shown)
	for p in _asset_paths:
		var s := str(p)
		if _finished_keys.has(s):
			continue
		units += _AssetCache.threaded_progress(s)
	return units


func _detail_name() -> String:
	## Prefer the file we just counted; otherwise cycle remaining / in-flight names.
	if not _reveal_queue.is_empty() and not _last_revealed_name.is_empty():
		return _last_revealed_name
	var pending: Array = []
	for p in _asset_paths:
		var s := str(p)
		if not _finished_keys.has(s):
			pending.append(_file_label(s))
	if not pending.is_empty():
		return str(pending[_name_cycle_idx % pending.size()])
	if not _last_revealed_name.is_empty():
		return _last_revealed_name
	if _shaders_done < _shader_paths.size():
		return _file_label(str(_shader_paths[_shaders_done]))
	return ""


func _file_label(path: String) -> String:
	var n := path.replace("\\", "/").get_file()
	if n.is_empty():
		return path
	return n


func _status_for(assets_idle: bool) -> String:
	if not assets_idle or _asset_done_shown < _asset_total:
		return "Loading assets %d / %d" % [_asset_done_shown, _asset_total]
	if _shaders_done < _shader_paths.size():
		return "Compiling effects %d / %d" % [_shaders_done, _shader_paths.size()]
	if not _main_ready:
		return "Loading interface…"
	return "Starting HyperSpace…"


func _warm_shaders_step() -> void:
	## Load one shader per frame so progress ticks and compile cost is spread out.
	if _shaders_done >= _shader_paths.size():
		return
	var path := str(_shader_paths[_shaders_done])
	if ResourceLoader.exists(path):
		var _res: Resource = ResourceLoader.load(path)
	_shaders_done += 1


func _poll_main_scene() -> void:
	if _main_ready:
		_main_frac = 1.0
		return
	var progress: Array = []
	var st := ResourceLoader.load_threaded_get_status(MAIN_SCENE_PATH, progress)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if not progress.is_empty():
			_main_frac = clampf(float(progress[0]), 0.0, 0.99)
		return
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		var res: Resource = ResourceLoader.load_threaded_get(MAIN_SCENE_PATH)
		if res is PackedScene:
			_main_packed = res as PackedScene
			_main_ready = true
			_main_frac = 1.0
			return
	# Failed or never requested — sync fallback.
	if ResourceLoader.exists(MAIN_SCENE_PATH):
		var res2: Resource = ResourceLoader.load(MAIN_SCENE_PATH)
		if res2 is PackedScene:
			_main_packed = res2 as PackedScene
	_main_ready = _main_packed != null
	_main_frac = 1.0 if _main_ready else 0.0


func _update_ui(frac: float, status: String, detail: String = "") -> void:
	if progress_bar:
		progress_bar.value = maxf(progress_bar.value, frac * 100.0)
	if status_label:
		status_label.text = status
	if detail_label:
		detail_label.text = detail


func _try_finish(assets_fully_warm: bool) -> void:
	if _finished:
		return
	if _elapsed < READY_HOLD_SEC:
		return
	if not _main_ready:
		_poll_main_scene()
		if not _main_ready:
			return
	_finished = true
	if assets_fully_warm:
		_BootCache.mark_full_warm_completed()
	_update_ui(1.0, "Ready", "Opening…")
	set_process(false)
	if _main_packed != null:
		get_tree().change_scene_to_packed(_main_packed)
	else:
		get_tree().change_scene_to_file(MAIN_SCENE_PATH)
