extends RefCounted
class_name FxAutomation

## Timed effect automation mirroring vuxanov/ASCII Live Visuals Engine:
## - Style switch: cycle ASCII presets on a fixed interval
## - Effect schedules: gate enabled effects open/closed over active/inactive windows
##
## Schedule mapping (must match UI labels in ScheduleSecondsPair):
##   active_sec   = how long the effect/drive is ON
##   inactive_sec = how long it is OFF
## Cycle = active_sec + inactive_sec; then repeats.
## Phase model: open iff phase < active (exact UI seconds, no 0.99 caps).
##
## Play All modes:
## - cycle / audio: independent per-effect Active/Inactive (staggered), schedule
##   slider is a base hint for those rolls.
## - random: master `play_all` Active/Inactive mutes ALL play-all FX during
##   Inactive; during Active, periodically reshuffles which FX are on + params.
## - evolution: same master mute as random, but the mix starts at two FX and
##   slowly gains one more until the Play All cap. Already-on FX stay on.

signal style_advanced(preset_name: String)
signal gate_changed(effect_id: String, open: bool)
signal density_randomize_tick
signal play_all_randomize_tick

const LFO_RATE_DEFAULT := 0.45
const LFO_DEPTH_DEFAULT := 1.0
const LFO_WAVE_DEFAULT := "sine"
const AUDIO_SENS_DEFAULT := 1.0
const PLAY_ALL_MODES := ["cycle", "random", "audio", "evolution"]
const EVOLUTION_START_COUNT := 2
## Grow interval = Active seconds, clamped so Evolution never dumps the full stack.
const EVOLUTION_INTERVAL_MIN := 4.0
const EVOLUTION_INTERVAL_MAX := 16.0
const EVOLUTION_INTERVAL_ACTIVE_SCALE := 1.0


static func copy_driven_params(prev: Dictionary, dest: Dictionary) -> void:
	## Keep per-parameter expressions (strings) across randomize / style cycles.
	for k in prev.keys():
		if prev[k] is String:
			dest[k] = prev[k]


static func copy_lfo_params(prev: Dictionary, dest: Dictionary) -> void:
	## Legacy alias — expressions replaced per-effect LFO knobs.
	copy_driven_params(prev, dest)


var style_active: bool = false
var style_interval: float = 5.0
var style_timer: float = 0.0
var style_index: int = 0
var style_presets: PackedStringArray = PackedStringArray()

## ASCII density randomizer (independent of style charset)
var density_random: bool = false
var density_random_timer: float = 0.0
var density_random_interval: float = 4.0

## effect_id -> gate dict
var _gates: Dictionary = {}

## Play All master controls (own schedule + mode/speed/audio).
var play_all_running: bool = false
var play_all_mode: String = "cycle"  # cycle | random | audio | evolution
var play_all_speed: float = 1.0
var play_all_audio_reactive: bool = false
var play_all_audio_energy: float = 0.0
var _play_all_ids: Array = []
var _play_all_random_timer: float = 0.0
var _play_all_evolve_timer: float = 0.0
var _play_all_evolve_count: int = 0
var _evolution_pending_randomize: Array = []
## Random/Evolution subset mask: effect_id -> want open while master window is active.
var _play_all_subset: Dictionary = {}
var _play_all_was_open: bool = true


func configure_style_presets(names: PackedStringArray) -> void:
	style_presets = names
	if style_index >= style_presets.size():
		style_index = 0


func set_style_active(on: bool) -> void:
	style_active = on
	if on:
		style_timer = 0.0


func set_style_interval(seconds: float) -> void:
	style_interval = clampf(seconds, 0.01, 1.0e6)
	density_random_interval = style_interval


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
	var a := clampf(active_sec, 0.01, 1.0e6)
	var i := clampf(inactive_sec, 0.01, 1.0e6)
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


func is_play_all_window_open() -> bool:
	## Master Play All Active/Inactive window (phase model).
	var g: Dictionary = _gates.get("play_all", {})
	if g.is_empty() or not bool(g.get("enabled", false)):
		return true
	return bool(g.get("open", true))


func is_gate_open(effect_id: String) -> bool:
	if effect_id == "play_all":
		return is_play_all_window_open()
	# Random / Evolution: master mute + subset mask (ignore per-effect phase).
	if play_all_running and _uses_play_all_subset() and _is_play_all_effect(effect_id):
		if not is_play_all_window_open():
			return false
		return bool(_play_all_subset.get(effect_id, false))
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


func get_play_all_ids() -> Array:
	return _play_all_ids.duplicate()


func tick(delta: float) -> void:
	## Use real process delta only (never accumulate while paused — ShowDirector
	## simply stops calling tick when the tree is paused).
	var speed := play_all_speed if play_all_running else 1.0
	if play_all_running and play_all_audio_reactive:
		# Audio reactive: quiet = slower cycles, loud = faster.
		speed *= lerpf(0.45, 1.75, clampf(play_all_audio_energy, 0.0, 1.0))
	var dt := maxf(delta, 0.0) * maxf(speed, 0.05)
	if style_active and style_presets.size() > 0:
		style_timer += dt
		var eff := maxf(0.01, style_interval)
		if style_timer >= eff:
			style_timer = fmod(style_timer, eff)
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
		var eid_str := str(effect_id)
		# Random / Evolution: only the master play_all gate advances; per-FX open state
		# comes from the subset mask + master mute (see is_gate_open).
		if play_all_running and _uses_play_all_subset() \
				and eid_str != "play_all" and _is_play_all_effect(eid_str):
			continue
		var g2: Dictionary = _gates[effect_id]
		if not bool(g2.get("enabled", false)):
			if not bool(g2.get("open", true)):
				g2["open"] = true
				gate_changed.emit(eid_str, true)
			continue
		var active := maxf(0.05, float(g2.get("effective_active", g2.get("active_sec", 4.0))))
		var inactive := maxf(0.05, float(g2.get("effective_inactive", g2.get("inactive_sec", 4.0))))
		if play_all_running and play_all_audio_reactive and not eid_str.begins_with("react_") \
				and eid_str != "play_all":
			# Stretch active window with energy so loud passages keep FX open longer.
			active *= lerpf(0.65, 1.45, clampf(play_all_audio_energy, 0.0, 1.0))
		var cycle := active + inactive
		var phase := float(g2.get("phase", 0.0)) + dt
		# Wrap exactly on cycle boundaries; reroll jitter windows on each wrap.
		while phase >= cycle:
			phase -= cycle
			# Play All cycle/audio: jitter-reroll so cadences keep drifting apart.
			if bool(g2.get("jitter", false)) or (play_all_running and not _uses_play_all_subset()):
				_reroll_gate(g2)
				active = maxf(0.05, float(g2.get("effective_active", 4.0)))
				inactive = maxf(0.05, float(g2.get("effective_inactive", 4.0)))
				cycle = active + inactive
		g2["phase"] = phase
		_apply_open_state(eid_str, g2, true)

	# Random: reshape mix while Active; master Inactive mutes via is_gate_open.
	if play_all_running and play_all_mode == "random":
		var master_open := is_play_all_window_open()
		if master_open and not _play_all_was_open:
			# Fresh Active window → immediate reshuffle.
			_play_all_random_timer = 0.0
			force_random_reshuffle()
		elif master_open:
			_play_all_random_timer += dt
			var g_master := ensure_gate("play_all")
			var active_win := maxf(0.05, float(g_master.get("effective_active", g_master.get("active_sec", 4.0))))
			# Reshuffle several times per Active window (not once-and-freeze).
			var interval := clampf(active_win * 0.2, 0.75, 2.5)
			if _play_all_random_timer >= interval:
				_play_all_random_timer = 0.0
				force_random_reshuffle()
		else:
			_play_all_random_timer = 0.0
		_play_all_was_open = master_open
	elif play_all_running and play_all_mode == "evolution":
		var evo_open := is_play_all_window_open()
		if evo_open and not _play_all_was_open:
			# Resume growing after mute — keep the current set.
			_play_all_evolve_timer = 0.0
		elif evo_open:
			_play_all_evolve_timer += dt
			var g_evo := ensure_gate("play_all")
			var evo_active := maxf(0.05, float(g_evo.get("effective_active", g_evo.get("active_sec", 4.0))))
			var evo_interval := clampf(evo_active * EVOLUTION_INTERVAL_ACTIVE_SCALE, EVOLUTION_INTERVAL_MIN, EVOLUTION_INTERVAL_MAX)
			if _play_all_evolve_timer >= evo_interval:
				_play_all_evolve_timer = 0.0
				_grow_evolution_subset()
		else:
			_play_all_evolve_timer = 0.0
		_play_all_was_open = evo_open


func configure_play_all(mode: String, speed: float, audio_reactive: bool, active_sec: float, inactive_sec: float) -> void:
	var prev_mode := play_all_mode
	play_all_mode = mode if mode in PLAY_ALL_MODES else "cycle"
	play_all_speed = clampf(speed, 0.01, 1.0e6)
	play_all_audio_reactive = audio_reactive or play_all_mode == "audio"
	set_gate_active_inactive("play_all", active_sec, inactive_sec)
	# Enable without resetting phase if already running (schedule tweaks keep phase).
	var g := ensure_gate("play_all")
	g["jitter"] = false
	if not bool(g.get("enabled", false)):
		set_gate_enabled("play_all", true)
	else:
		g["enabled"] = true
		g["effective_active"] = float(g.get("active_sec", active_sec))
		g["effective_inactive"] = float(g.get("inactive_sec", inactive_sec))
		_apply_open_state("play_all", g, true)
	# Random / Evolution: no per-effect jitter cadence — master schedule owns Active/Inactive.
	if _uses_play_all_subset():
		for eid in _play_all_ids:
			var eg := ensure_gate(str(eid))
			eg["jitter"] = false
			eg["enabled"] = true
		if play_all_running and (prev_mode != play_all_mode or _play_all_subset.is_empty()):
			_play_all_random_timer = 0.0
			_play_all_evolve_timer = 0.0
			# Start Active so the first window is immediately usable.
			g["phase"] = 0.0
			_apply_open_state("play_all", g, true)
			_play_all_was_open = true
			if play_all_mode == "random":
				force_random_reshuffle()
			else:
				_start_evolution_subset()
	else:
		_play_all_subset.clear()
		_play_all_evolve_count = 0
		_evolution_pending_randomize.clear()
		for eid in _play_all_ids:
			var eg2 := ensure_gate(str(eid))
			eg2["jitter"] = true
			_reroll_gate(eg2)


func set_play_all_speed(speed: float) -> void:
	play_all_speed = clampf(speed, 0.01, 1.0e6)


func set_play_all_audio_reactive(on: bool) -> void:
	play_all_audio_reactive = on


func set_play_all_audio_energy(energy: float) -> void:
	play_all_audio_energy = clampf(energy, 0.0, 1.0)


func pick_independent_schedule(base_active: float, base_inactive: float) -> Vector2:
	## Independent Active/Inactive around the Play All base (never zero / lockstep).
	var ba := maxf(2.0, base_active)
	var bi := maxf(2.0, base_inactive)
	var a := clampf(ba * randf_range(0.45, 1.85), 2.0, 28.0)
	var i := clampf(bi * randf_range(0.55, 2.15), 2.0, 36.0)
	# Snap toward whole seconds so UI sliders stay readable.
	a = snappedf(a, 1.0)
	i = snappedf(i, 1.0)
	return Vector2(maxf(2.0, a), maxf(2.0, i))


func apply_independent_gate_schedule(effect_id: String, base_active: float, base_inactive: float, stagger: bool = true) -> Vector2:
	## Assign a unique schedule + optional phase stagger. Returns (active, inactive).
	var pair := pick_independent_schedule(base_active, base_inactive)
	set_gate_active_inactive(effect_id, pair.x, pair.y)
	var g := ensure_gate(effect_id)
	g["jitter"] = true
	_reroll_gate(g)
	if stagger:
		stagger_gate_phase(effect_id)
	return Vector2(float(g.get("active_sec", pair.x)), float(g.get("inactive_sec", pair.y)))


func stagger_gate_phase(effect_id: String) -> void:
	var g := ensure_gate(effect_id)
	var active := maxf(0.05, float(g.get("effective_active", g.get("active_sec", 4.0))))
	var inactive := maxf(0.05, float(g.get("effective_inactive", g.get("inactive_sec", 4.0))))
	var cycle := maxf(0.1, active + inactive)
	g["phase"] = randf() * cycle
	_apply_open_state(effect_id, g, true)


func randomize_play_all_schedules(base_active: float, base_inactive: float) -> Dictionary:
	## Re-roll every Play All effect schedule independently. Returns eid -> Vector2(a,i).
	## No-op for Random / Evolution (master schedule owns timing).
	var out: Dictionary = {}
	var a := clampf(base_active, 0.01, 1.0e6)
	var i := clampf(base_inactive, 0.01, 1.0e6)
	set_gate_active_inactive("play_all", a, i)
	if _uses_play_all_subset():
		return out
	for eid_any in _play_all_ids:
		var eid := str(eid_any)
		out[eid] = apply_independent_gate_schedule(eid, a, i, true)
	return out


func force_random_reshuffle() -> void:
	## Reroll which effects are on + notify listeners to randomize params/styles.
	_reroll_random_play_all_subset()
	play_all_randomize_tick.emit()


func _reroll_random_play_all_subset() -> void:
	## Randomly pick a subset of Play All FX for the current Active window.
	if _play_all_ids.is_empty():
		return
	var any_open := false
	for eid_any in _play_all_ids:
		var eid := str(eid_any)
		var want_open := randf() < 0.55
		_play_all_subset[eid] = want_open
		if want_open:
			any_open = true
	# Always keep at least one effect while Active (Inactive mutes via master).
	if not any_open and is_play_all_window_open():
		var pick := str(_play_all_ids[randi() % _play_all_ids.size()])
		_play_all_subset[pick] = true
	for eid_any2 in _play_all_ids:
		var eid2 := str(eid_any2)
		gate_changed.emit(eid2, is_gate_open(eid2))


func enable_play_all(effect_ids: Array, cycle_sec: float = 20.0, active_sec: float = 5.0) -> void:
	## Master “Play All”: style switch + mode-specific scheduling.
	play_all_running = true
	_play_all_ids = []
	for id in effect_ids:
		_play_all_ids.append(str(id))
	set_style_active(true)
	var a := clampf(active_sec, 0.01, 1.0e6)
	var inactive := maxf(0.01, cycle_sec - a)
	set_gate_active_inactive("play_all", a, inactive)
	var g_master := ensure_gate("play_all")
	g_master["jitter"] = false
	g_master["effective_active"] = a
	g_master["effective_inactive"] = inactive
	set_gate_enabled("play_all", true)
	_play_all_was_open = true
	_play_all_random_timer = 0.0
	_play_all_evolve_timer = 0.0
	if _uses_play_all_subset():
		_play_all_subset.clear()
		for id2 in effect_ids:
			var eid := str(id2)
			var g := ensure_gate(eid)
			g["jitter"] = false
			g["enabled"] = true
			g["open"] = true
			g["phase"] = 0.0
		if play_all_mode == "random":
			force_random_reshuffle()
		else:
			_start_evolution_subset()
	else:
		_play_all_subset.clear()
		for id3 in effect_ids:
			var eid3 := str(id3)
			var pair := pick_independent_schedule(a, inactive)
			set_gate_active_inactive(eid3, pair.x, pair.y)
			var g3 := ensure_gate(eid3)
			g3["jitter"] = true
			set_gate_enabled(eid3, true)
			# set_gate_enabled resets phase to 0 — stagger after so FX do not open together.
			stagger_gate_phase(eid3)


func disable_play_all() -> void:
	play_all_running = false
	_play_all_ids.clear()
	_play_all_subset.clear()
	_play_all_random_timer = 0.0
	_play_all_evolve_timer = 0.0
	_play_all_evolve_count = 0
	_evolution_pending_randomize.clear()
	_play_all_was_open = true
	set_style_active(false)
	set_gate_enabled("play_all", false)
	for effect_id in _gates.keys():
		var eid := str(effect_id)
		# Leave reactivity Active/Inactive gates alone (react_*).
		if eid.begins_with("react_") or eid == "play_all":
			continue
		set_gate_enabled(eid, false)


func clear_all_automation() -> void:
	## Full stop used by Reset to default: Play All, style/density, every schedule gate.
	disable_play_all()
	set_density_random(false)
	# Reset Play All knobs without re-enabling the master gate (configure_play_all does).
	play_all_mode = "cycle"
	play_all_speed = 1.0
	play_all_audio_reactive = false
	play_all_audio_energy = 0.0
	set_gate_active_inactive("play_all", 4.0, 4.0)
	for effect_id in _gates.keys():
		set_gate_enabled(str(effect_id), false)


func _is_play_all_effect(effect_id: String) -> bool:
	for eid in _play_all_ids:
		if str(eid) == effect_id:
			return true
	return false


func _uses_play_all_subset() -> bool:
	return play_all_mode == "random" or play_all_mode == "evolution"


func take_evolution_randomize_ids() -> Array:
	var out: Array = _evolution_pending_randomize.duplicate()
	_evolution_pending_randomize.clear()
	return out


func _start_evolution_subset() -> void:
	## Begin at two random FX; grow later via _grow_evolution_subset.
	_play_all_subset.clear()
	_evolution_pending_randomize.clear()
	_play_all_evolve_count = 0
	_play_all_evolve_timer = 0.0
	if _play_all_ids.is_empty():
		return
	var shuffled: Array = _play_all_ids.duplicate()
	shuffled.shuffle()
	var n := mini(EVOLUTION_START_COUNT, shuffled.size())
	for eid_any in shuffled:
		_play_all_subset[str(eid_any)] = false
	for i in n:
		var eid := str(shuffled[i])
		_play_all_subset[eid] = true
		_evolution_pending_randomize.append(eid)
	_play_all_evolve_count = n
	for eid_any2 in _play_all_ids:
		var eid2 := str(eid_any2)
		gate_changed.emit(eid2, is_gate_open(eid2))
	play_all_randomize_tick.emit()


func _grow_evolution_subset() -> void:
	## Add one unused effect; stay at cap. Randomize only the newly added FX.
	if _play_all_ids.is_empty():
		return
	var cap := _play_all_ids.size()
	if _play_all_evolve_count >= cap:
		return
	var candidates: Array = []
	for eid_any in _play_all_ids:
		var eid := str(eid_any)
		if not bool(_play_all_subset.get(eid, false)):
			candidates.append(eid)
	if candidates.is_empty():
		_play_all_evolve_count = cap
		return
	var pick := str(candidates[randi() % candidates.size()])
	_play_all_subset[pick] = true
	_play_all_evolve_count += 1
	_evolution_pending_randomize = [pick]
	gate_changed.emit(pick, is_gate_open(pick))
	play_all_randomize_tick.emit()


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
		g["effective_active"] = clampf(base_a * randf_range(0.6, 1.4), 0.01, 1.0e6)
		g["effective_inactive"] = clampf(base_i * randf_range(0.6, 1.4), 0.01, 1.0e6)
	else:
		g["effective_active"] = base_a
		g["effective_inactive"] = base_i

