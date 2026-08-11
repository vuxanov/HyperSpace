extends RefCounted
class_name FxAutomation

## Timed effect automation mirroring vuxanov/ASCII Live Visuals Engine:
## - Style switch: cycle ASCII presets on an interval (optional jitter)
## - Effect schedules: gate enabled effects open/closed over active/inactive windows
##
## Schedule mapping (must match UI labels in ScheduleSecondsPair):
##   active_sec   = how long the effect/drive is ON
##   inactive_sec = how long it is OFF
## Cycle = active_sec + inactive_sec; then repeats.
## Phase model: open iff phase < active (exact UI seconds, no 0.99 caps).

signal style_advanced(preset_name: String)
signal gate_changed(effect_id: String, open: bool)
signal density_randomize_tick


var style_active: bool = false
var style_interval: float = 5.0
var style_jitter: bool = false
var style_timer: float = 0.0
var style_index: int = 0
var style_effective_interval: float = 5.0
var style_presets: PackedStringArray = PackedStringArray()

## ASCII density randomizer (independent of style charset)
var density_random: bool = false
var density_random_timer: float = 0.0
var density_random_interval: float = 4.0

## effect_id -> gate dict
var _gates: Dictionary = {}


func configure_style_presets(names: PackedStringArray) -> void:
	style_presets = names
	if style_index >= style_presets.size():
		style_index = 0


func set_style_active(on: bool) -> void:
	style_active = on
	if on:
		style_timer = 0.0
		style_effective_interval = _pick_interval(style_interval, style_jitter, 1.0, 30.0)


func set_style_interval(seconds: float) -> void:
	style_interval = clampf(seconds, 0.5, 60.0)
	density_random_interval = style_interval
	if not style_jitter:
		style_effective_interval = style_interval


func set_style_jitter(on: bool) -> void:
	style_jitter = on
	style_effective_interval = _pick_interval(style_interval, style_jitter, 1.0, 30.0)


func set_density_random(on: bool) -> void:
	density_random = on
	density_random_timer = 0.0
	if on:
		density_randomize_tick.emit()


func ensure_gate(effect_id: String) -> Dictionary:
	if not _gates.has(effect_id):
		_gates[effect_id] = {
			"enabled": false,
			"active_sec": 4.0,
			"inactive_sec": 4.0,
			"jitter": false,
			"phase": 0.0,
			"effective_active": 4.0,
			"effective_inactive": 4.0,
			"open": true,
		}
	return _gates[effect_id]


func set_gate_enabled(effect_id: String, on: bool) -> void:
	var g := ensure_gate(effect_id)
	g["enabled"] = on
	if on:
		_reroll_gate(g)
		# Fresh Active window whenever the schedule is (re)enabled.
		g["phase"] = 0.0
		g["open"] = true
	else:
		g["phase"] = 0.0
		g["open"] = true
	gate_changed.emit(effect_id, true)


func set_gate_times(effect_id: String, cycle_sec: float, active_sec: float) -> void:
	## Legacy: cycle = active + inactive, active = on-window.
	var c := clampf(cycle_sec, 0.1, 240.0)
	var a := clampf(active_sec, 0.05, c)
	set_gate_active_inactive(effect_id, a, maxf(0.05, c - a))


func set_gate_active_inactive(effect_id: String, active_sec: float, inactive_sec: float) -> void:
	## UI mapping: first slider / Active label → active_sec; Inactive → inactive_sec.
	var g := ensure_gate(effect_id)
	var a := clampf(active_sec, 0.05, 120.0)
	var i := clampf(inactive_sec, 0.05, 120.0)
	var prev_a := float(g.get("active_sec", a))
	var prev_i := float(g.get("inactive_sec", i))
	g["active_sec"] = a
	g["inactive_sec"] = i
	if not bool(g.get("jitter", false)):
		g["effective_active"] = a
		g["effective_inactive"] = i
	# Changing durations mid-run: keep relative progress in the old cycle, then
	# clamp into the new cycle so the next edge lands on exact Active/Inactive.
	if not is_equal_approx(prev_a, a) or not is_equal_approx(prev_i, i):
		var old_cycle := maxf(0.05, prev_a + prev_i)
		var new_cycle := maxf(0.05, a + i)
		var phase := float(g.get("phase", 0.0))
		var ratio := clampf(phase / old_cycle, 0.0, 0.999999)
		g["phase"] = ratio * new_cycle
		_apply_open_state(effect_id, g, true)


func set_gate_jitter(effect_id: String, on: bool) -> void:
	var g := ensure_gate(effect_id)
	g["jitter"] = on
	_reroll_gate(g)


func is_gate_open(effect_id: String) -> bool:
	var g: Dictionary = _gates.get(effect_id, {})
	if g.is_empty() or not bool(g.get("enabled", false)):
		return true
	return bool(g.get("open", true))


func is_gate_enabled(effect_id: String) -> bool:
	var g: Dictionary = _gates.get(effect_id, {})
	return bool(g.get("enabled", false))


func get_gate_active(effect_id: String) -> float:
	return float(ensure_gate(effect_id).get("active_sec", 4.0))


func get_gate_inactive(effect_id: String) -> float:
	return float(ensure_gate(effect_id).get("inactive_sec", 4.0))


func tick(delta: float) -> void:
	## Use real process delta only (never accumulate while paused — ShowDirector
	## simply stops calling tick when the tree is paused).
	var dt := maxf(delta, 0.0)
	if style_active and style_presets.size() > 0:
		style_timer += dt
		var eff := style_effective_interval if style_effective_interval > 0.0 else style_interval
		if style_timer >= eff:
			style_timer = fmod(style_timer, eff)
			style_effective_interval = _pick_interval(style_interval, style_jitter, 1.0, 30.0)
			style_index = (style_index + 1) % style_presets.size()
			style_advanced.emit(str(style_presets[style_index]))
			if density_random:
				density_randomize_tick.emit()

	if density_random and not style_active:
		density_random_timer += dt
		var di := maxf(1.0, density_random_interval)
		if density_random_timer >= di:
			density_random_timer = fmod(density_random_timer, di)
			density_randomize_tick.emit()

	for effect_id in _gates.keys():
		var g: Dictionary = _gates[effect_id]
		if not bool(g.get("enabled", false)):
			if not bool(g.get("open", true)):
				g["open"] = true
				gate_changed.emit(str(effect_id), true)
			continue
		var active := maxf(0.05, float(g.get("effective_active", g.get("active_sec", 4.0))))
		var inactive := maxf(0.05, float(g.get("effective_inactive", g.get("inactive_sec", 4.0))))
		var cycle := active + inactive
		var phase := float(g.get("phase", 0.0)) + dt
		# Wrap exactly on cycle boundaries; reroll jitter windows on each wrap.
		while phase >= cycle:
			phase -= cycle
			if bool(g.get("jitter", false)):
				_reroll_gate(g)
				active = maxf(0.05, float(g.get("effective_active", 4.0)))
				inactive = maxf(0.05, float(g.get("effective_inactive", 4.0)))
				cycle = active + inactive
		g["phase"] = phase
		_apply_open_state(str(effect_id), g, true)


func enable_play_all(effect_ids: Array, cycle_sec: float = 20.0, active_sec: float = 5.0) -> void:
	## Master “Play All”: style switch + schedules for the given effects.
	set_style_active(true)
	var a := clampf(active_sec, 0.05, 120.0)
	var inactive := maxf(0.05, cycle_sec - a)
	for id in effect_ids:
		var eid := str(id)
		set_gate_active_inactive(eid, a, inactive)
		set_gate_enabled(eid, true)


func disable_play_all() -> void:
	set_style_active(false)
	for effect_id in _gates.keys():
		var eid := str(effect_id)
		# Leave reactivity Active/Inactive gates alone (react_*).
		if eid.begins_with("react_"):
			continue
		set_gate_enabled(eid, false)


func _apply_open_state(effect_id: String, g: Dictionary, emit_on_change: bool) -> void:
	var active := maxf(0.05, float(g.get("effective_active", g.get("active_sec", 4.0))))
	var open_now := float(g.get("phase", 0.0)) < active
	var was_open := bool(g.get("open", true))
	g["open"] = open_now
	if emit_on_change and open_now != was_open:
		gate_changed.emit(effect_id, open_now)


func _reroll_gate(g: Dictionary) -> void:
	var base_a := float(g.get("active_sec", 4.0))
	var base_i := float(g.get("inactive_sec", 4.0))
	if bool(g.get("jitter", false)):
		g["effective_active"] = clampf(base_a * randf_range(0.6, 1.4), 0.05, 120.0)
		g["effective_inactive"] = clampf(base_i * randf_range(0.6, 1.4), 0.05, 120.0)
	else:
		g["effective_active"] = base_a
		g["effective_inactive"] = base_i


func _pick_interval(base: float, jitter: bool, lo: float, hi: float) -> float:
	if jitter:
		return clampf(base * randf_range(0.55, 1.55), lo, hi)
	return clampf(base, lo, hi)
