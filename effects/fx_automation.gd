extends RefCounted
class_name FxAutomation

## Timed effect automation mirroring vuxanov/ASCII Live Visuals Engine:
## - Style switch: cycle ASCII presets on an interval (optional jitter)
## - Effect schedules: gate enabled effects open/closed over cycle/active windows

signal style_advanced(preset_name: String)
signal gate_changed(effect_id: String, open: bool)


var style_active: bool = false
var style_interval: float = 5.0
var style_jitter: bool = false
var style_timer: float = 0.0
var style_index: int = 0
var style_effective_interval: float = 5.0
var style_presets: PackedStringArray = PackedStringArray()

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
	if not style_jitter:
		style_effective_interval = style_interval


func set_style_jitter(on: bool) -> void:
	style_jitter = on
	style_effective_interval = _pick_interval(style_interval, style_jitter, 1.0, 30.0)


func ensure_gate(effect_id: String) -> Dictionary:
	if not _gates.has(effect_id):
		_gates[effect_id] = {
			"enabled": false,
			"cycle_sec": 20.0,
			"active_sec": 5.0,
			"jitter": false,
			"timer": 0.0,
			"effective_cycle": 20.0,
			"effective_active": 5.0,
			"open": true,
		}
	return _gates[effect_id]


func set_gate_enabled(effect_id: String, on: bool) -> void:
	var g := ensure_gate(effect_id)
	g["enabled"] = on
	g["timer"] = 0.0
	if on:
		_reroll_gate(g)
		g["open"] = true
	else:
		g["open"] = true
	gate_changed.emit(effect_id, true)


func set_gate_times(effect_id: String, cycle_sec: float, active_sec: float) -> void:
	var g := ensure_gate(effect_id)
	g["cycle_sec"] = clampf(cycle_sec, 0.5, 120.0)
	g["active_sec"] = clampf(active_sec, 0.05, g["cycle_sec"] * 0.95)
	if not g["jitter"]:
		g["effective_cycle"] = g["cycle_sec"]
		g["effective_active"] = g["active_sec"]


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


func tick(delta: float) -> void:
	if style_active and style_presets.size() > 0:
		style_timer += delta
		var eff := style_effective_interval if style_effective_interval > 0.0 else style_interval
		if style_timer >= eff:
			style_timer = 0.0
			style_effective_interval = _pick_interval(style_interval, style_jitter, 1.0, 30.0)
			style_index = (style_index + 1) % style_presets.size()
			style_advanced.emit(str(style_presets[style_index]))

	for effect_id in _gates.keys():
		var g: Dictionary = _gates[effect_id]
		if not bool(g.get("enabled", false)):
			if not bool(g.get("open", true)):
				g["open"] = true
				gate_changed.emit(str(effect_id), true)
			continue
		var c := maxf(0.5, float(g.get("effective_cycle", 20.0)))
		var a := minf(maxf(0.05, float(g.get("effective_active", 5.0))), c * 0.99)
		g["timer"] = float(g.get("timer", 0.0)) + delta
		while float(g["timer"]) >= c:
			g["timer"] = float(g["timer"]) - c
			if bool(g.get("jitter", false)):
				_reroll_gate(g)
				c = maxf(0.5, float(g.get("effective_cycle", 20.0)))
		c = maxf(0.5, float(g.get("effective_cycle", 20.0)))
		a = minf(maxf(0.05, float(g.get("effective_active", 5.0))), c * 0.99)
		var open_now := float(g["timer"]) < a
		if open_now != bool(g.get("open", true)):
			g["open"] = open_now
			gate_changed.emit(str(effect_id), open_now)


func enable_play_all(effect_ids: Array, cycle_sec: float = 20.0, active_sec: float = 5.0) -> void:
	## Master “Play All”: style switch + schedules for the given effects.
	set_style_active(true)
	for id in effect_ids:
		var eid := str(id)
		set_gate_times(eid, cycle_sec, active_sec)
		set_gate_enabled(eid, true)


func disable_play_all() -> void:
	set_style_active(false)
	for effect_id in _gates.keys():
		set_gate_enabled(str(effect_id), false)


func _reroll_gate(g: Dictionary) -> void:
	var base_c := float(g.get("cycle_sec", 20.0))
	var base_a := float(g.get("active_sec", 5.0))
	if bool(g.get("jitter", false)):
		g["effective_cycle"] = _pick_interval(base_c, true, 3.0, 120.0)
		var max_a: float = float(g["effective_cycle"]) * 0.95
		g["effective_active"] = clampf(base_a * randf_range(0.6, 1.4), 0.05, max_a)
	else:
		g["effective_cycle"] = base_c
		g["effective_active"] = clampf(base_a, 0.05, base_c * 0.95)


func _pick_interval(base: float, jitter: bool, lo: float, hi: float) -> float:
	if jitter:
		return clampf(base * randf_range(0.55, 1.55), lo, hi)
	return clampf(base, lo, hi)
