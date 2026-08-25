extends Node

## Named signals + safe expression eval for effect parameters.
## Built-in identifiers (time/audio/path) plus user LFO / noise / random drivers.

const _Expr := preload("res://core/driver_expr.gd")

signal drivers_changed
signal values_updated

const WAVE_IDS: PackedStringArray = ["sine", "triangle", "saw", "square"]
const WAVE_LABELS: PackedStringArray = ["Sine", "Triangle", "Saw", "Square"]
const TYPE_LFO := "lfo"
const TYPE_NOISE := "noise"
const TYPE_RANDOM := "random"

## Shown in the Drivers tab Built-in section (name, one-line hint). Picker uses the same ids.
const BUILTIN_HINTS: Array = [
	["time", "Seconds since session start"],
	["volume", "Gated overall loudness (0 when silent)"],
	["energy", "Mean band presence after the noise gate"],
	["peak", "Loudest gated band"],
	["bass", "Bass loudness the mic can hear (~125–500 Hz)"],
	["mids", "Mid loudness (~315–3150 Hz)"],
	["highs", "Hats / cymbals / air (~3–20 kHz)"],
	["kick", "Kick gate: 1 on a 40–130 Hz hit, 0 otherwise"],
	["beat", "1 on a hit (kick, clap, snare, plosive), else 0"],
	["lfo1", "Default LFO — oscillates around 1 (tweak rate/depth/wave below)"],
	["lfo2", "Second default LFO — oscillates around 1"],
	["noise", "Smoothed noise around 1 (0–2)"],
	["rand", "Sample-and-hold random around 1 (default 0–2)"],
	["band0", "EQ bin 0; type band1 … band15 for the rest"],
]

var _time: float = 0.0
var _dt: float = 0.0
var _values: Dictionary = {}
var _defs: Dictionary = {}
var _phase: Dictionary = {}
var _noise_hold: Dictionary = {}
var _rand_hold: Dictionary = {}
var _rand_timer: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _reserved: Dictionary = {}
var _parser: Object = null
## Slow peak-follow so audio drivers sit near 1 when there is signal (not 0.000x FFT).
var _audio_peak_ema: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_parser = _Expr.new()
	_init_reserved()
	_ensure_defaults()
	set_process(true)
	var analyzer := get_node_or_null("/root/AudioAnalyzer")
	if analyzer != null and analyzer.has_signal("state_updated"):
		if not analyzer.is_connected("state_updated", Callable(self, "_on_analyzer_state")):
			analyzer.connect("state_updated", Callable(self, "_on_analyzer_state"))


func _process(delta: float) -> void:
	_dt = maxf(delta, 0.0)
	_time += _dt
	_sample_audio()
	_tick_generated(_dt)
	_write_aliases()
	values_updated.emit()


func _init_reserved() -> void:
	_reserved.clear()
	for row in BUILTIN_HINTS:
		_reserved[str(row[0])] = true
	for a in ["frac", "time_norm", "time01", "dt", "sin_time", "progress", "cam_speed", "level", "amp", "input_level", "mid", "treble", "random", "lfo"]:
		_reserved[a] = true
	for i in 16:
		_reserved["band%d" % i] = true


func _ensure_defaults() -> void:
	if not _defs.has("lfo1"):
		_defs["lfo1"] = _make_lfo("lfo1", 0.45, 1.0, "sine", true)
	if not _defs.has("lfo2"):
		_defs["lfo2"] = _make_lfo("lfo2", 0.85, 1.0, "triangle", true)
	if not _defs.has("noise"):
		_defs["noise"] = _make_noise("noise", 1.0, 0.65, true)
	if not _defs.has("rand"):
		_defs["rand"] = _make_random("rand", 2.0, 0.0, 2.0, true)
	for name in _defs.keys():
		if not _phase.has(name):
			_phase[name] = _rng.randf()


func _make_lfo(id: String, rate: float, depth: float, wave: String, builtin: bool) -> Dictionary:
	return {
		"id": id,
		"type": TYPE_LFO,
		"builtin": builtin,
		"rate": clampf(rate, 0.05, 16.0),
		"depth": clampf(depth, 0.0, 1.5),
		"wave": _norm_wave(wave),
	}


func _make_noise(id: String, speed: float, smoothness: float, builtin: bool) -> Dictionary:
	return {
		"id": id,
		"type": TYPE_NOISE,
		"builtin": builtin,
		"speed": clampf(speed, 0.05, 16.0),
		"smoothness": clampf(smoothness, 0.0, 1.0),
	}


func _make_random(id: String, rate: float, lo: float, hi: float, builtin: bool) -> Dictionary:
	return {
		"id": id,
		"type": TYPE_RANDOM,
		"builtin": builtin,
		"rate": clampf(rate, 0.05, 16.0),
		"min": lo,
		"max": hi,
	}


func _norm_wave(wave: String) -> String:
	var w := wave.strip_edges().to_lower()
	if w in ["sine", "triangle", "saw", "square"]:
		return w
	return "sine"


func _on_analyzer_state(_state: Variant = null) -> void:
	## Ignore the AudioState payload. Sample get_driver_audio (EQ bins + onset).
	_sample_audio()


func _sample_audio() -> void:
	var analyzer := get_node_or_null("/root/AudioAnalyzer")
	if analyzer == null:
		_zero_audio()
		return
	if analyzer.has_method("get_driver_audio"):
		var d: Variant = analyzer.call("get_driver_audio")
		if d is Dictionary:
			_apply_driver_audio(d as Dictionary)
			return
	var bands: Variant = analyzer.get("ui_bands")
	if bands is PackedFloat32Array:
		_apply_ui_bands(bands as PackedFloat32Array)
		return
	_zero_audio()


func _zero_audio() -> void:
	_values["bass"] = 0.0
	_values["mids"] = 0.0
	_values["highs"] = 0.0
	_values["kick"] = 0.0
	_values["energy"] = 0.0
	_values["peak"] = 0.0
	_values["volume"] = 0.0
	_values["beat"] = 0.0
	_audio_peak_ema = lerpf(_audio_peak_ema, 0.0, 0.2)
	for i in 16:
		_values["band%d" % i] = 0.0


func _apply_driver_audio(d: Dictionary) -> void:
	_values["bass"] = float(d.get("bass", 0.0))
	_values["mids"] = float(d.get("mids", 0.0))
	_values["highs"] = float(d.get("highs", 0.0))
	_values["kick"] = float(d.get("kick", 0.0))
	_values["energy"] = float(d.get("energy", 0.0))
	_values["peak"] = float(d.get("peak", 0.0))
	_values["volume"] = float(d.get("volume", 0.0))
	_values["beat"] = float(d.get("beat", 0.0))
	var bands: Variant = d.get("bands", PackedFloat32Array())
	_write_bands(bands)
	_renorm_audio_levels()


func _apply_ui_bands(bands: PackedFloat32Array) -> void:
	## Fallback if get_driver_audio is missing: same 16 EQ bins, same averages.
	var bass_ui := _mean_range(bands, 0, 3)
	var mids_ui := _mean_range(bands, 4, 9)
	var highs_ui := _mean_range(bands, 10, 15)
	var energy_ui := _mean_range(bands, 0, 15)
	var peak_ui := 0.0
	for i in bands.size():
		peak_ui = maxf(peak_ui, bands[i])
	_values["bass"] = bass_ui
	_values["mids"] = mids_ui
	_values["highs"] = highs_ui
	_values["energy"] = energy_ui
	_values["peak"] = peak_ui
	_values["volume"] = maxf(energy_ui, peak_ui)
	_values["kick"] = 0.0  # fallback path has no onset detector
	_values["beat"] = 0.0
	_write_bands(bands)
	_renorm_audio_levels()


func _write_bands(bands: Variant) -> void:
	for i in 16:
		var bv := 0.0
		if bands is PackedFloat32Array and i < (bands as PackedFloat32Array).size():
			bv = float((bands as PackedFloat32Array)[i])
		_values["band%d" % i] = bv


func _mean_range(bands: PackedFloat32Array, from_idx: int, to_idx: int) -> float:
	var total := 0.0
	var count := 0
	for i in range(from_idx, mini(to_idx + 1, bands.size())):
		total += bands[i]
		count += 1
	return total / maxf(float(count), 1.0)


func _renorm_audio_levels() -> void:
	## Analyzer already gates, differentiates, and applies intensity/sensitivity.
	## Peak-renormalizing here made every band look the same and killed the sliders.
	for k in ["volume", "energy", "peak", "bass", "mids", "highs", "kick", "beat"]:
		_values[k] = clampf(float(_values.get(k, 0.0)), 0.0, 2.0)
	for i in 16:
		var bk := "band%d" % i
		_values[bk] = clampf(float(_values.get(bk, 0.0)), 0.0, 2.0)
	_audio_peak_ema = 0.0


func _tick_generated(delta: float) -> void:
	for name_any in _defs.keys():
		var name := str(name_any)
		var def: Dictionary = _defs[name]
		var typ := str(def.get("type", TYPE_LFO))
		match typ:
			TYPE_LFO:
				var rate := maxf(float(def.get("rate", 0.45)), 0.05)
				var ph := float(_phase.get(name, 0.0))
				ph = fposmod(ph + delta * rate, 1.0)
				_phase[name] = ph
				var w := _wave01(ph, str(def.get("wave", "sine")))
				var d := clampf(float(def.get("depth", 1.0)), 0.0, 1.5)
				## Mean 1 at rest; depth 1 sweeps 0..2. Multiply-friendly (scale * lfo1 stays near scale).
				_values[name] = 1.0 + (w - 0.5) * 2.0 * d
			TYPE_NOISE:
				var speed := maxf(float(def.get("speed", 1.0)), 0.05)
				var smooth := clampf(float(def.get("smoothness", 0.6)), 0.0, 1.0)
				var hold := float(_noise_hold.get(name, 0.5))
				var target := _rng.randf()
				var follow := clampf(1.0 - smooth, 0.02, 1.0) * clampf(speed * delta * 4.0, 0.0, 1.0)
				hold = lerpf(hold, target, follow)
				_noise_hold[name] = hold
				_values[name] = clampf(hold, 0.0, 1.0) * 2.0
			TYPE_RANDOM:
				var rate_r := maxf(float(def.get("rate", 2.0)), 0.05)
				var timer := float(_rand_timer.get(name, 0.0)) + delta
				var interval := 1.0 / rate_r
				var lo := float(def.get("min", 0.0))
				var hi := float(def.get("max", 2.0))
				if hi < lo:
					var tmp := lo
					lo = hi
					hi = tmp
				if not _rand_hold.has(name):
					_rand_hold[name] = _rng.randf_range(lo, hi)
				while timer >= interval:
					timer -= interval
					_rand_hold[name] = _rng.randf_range(lo, hi)
				_rand_timer[name] = timer
				_values[name] = float(_rand_hold[name])
			_:
				_values[name] = 0.0


func _wave01(phase01: float, wave: String) -> float:
	var p := fposmod(phase01, 1.0)
	match wave:
		"triangle":
			return 1.0 - absf(2.0 * p - 1.0)
		"saw":
			return p
		"square":
			return 1.0 if p < 0.5 else 0.0
		_:
			return sin(p * TAU) * 0.5 + 0.5


func _write_aliases() -> void:
	_values["time"] = _time
	_values["level"] = float(_values.get("volume", 0.0))
	_values["amp"] = float(_values.get("volume", 0.0))
	_values["mid"] = float(_values.get("mids", 0.0))
	_values["treble"] = float(_values.get("highs", 0.0))
	_values["random"] = float(_values.get("rand", 0.0))
	_values["lfo"] = float(_values.get("lfo1", 0.0))


func get_value(name: String) -> float:
	return float(_values.get(name.strip_edges().to_lower(), 0.0))


func eval_expr(expr: String) -> float:
	if _parser == null:
		_parser = _Expr.new()
	return float(_parser.call("evaluate", expr, _values))


func eval_value(raw: Variant, fallback: float = 0.0) -> float:
	if raw == null:
		return fallback
	if raw is float or raw is int:
		return float(raw)
	if raw is String:
		var s := (raw as String).strip_edges()
		if s.is_empty():
			return fallback
		if _Expr.is_plain_number(s):
			return s.to_float()
		return eval_expr(s)
	return fallback


func eval_clamped(raw: Variant, lo: float, hi: float, fallback: float = 0.0) -> float:
	return clampf(eval_value(raw, fallback), lo, hi)


func list_defs() -> Array:
	var out: Array = []
	for name in ["lfo1", "lfo2", "noise", "rand"]:
		if _defs.has(name):
			out.append((_defs[name] as Dictionary).duplicate(true))
	var extras: Array = []
	for name_any in _defs.keys():
		var name := str(name_any)
		if name in ["lfo1", "lfo2", "noise", "rand"]:
			continue
		extras.append(name)
	extras.sort()
	for name2 in extras:
		out.append((_defs[name2] as Dictionary).duplicate(true))
	return out


func picker_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for row in [
		"time", "volume", "energy", "peak", "bass",
		"mids", "highs", "kick", "beat",
		"lfo1", "lfo2", "noise", "rand", "band0",
	]:
		names.append(row)
	var extras: Array = []
	for name_any in _defs.keys():
		var name := str(name_any)
		if name in ["lfo1", "lfo2", "noise", "rand"]:
			continue
		extras.append(name)
	extras.sort()
	for e in extras:
		names.append(str(e))
	return names


func get_def(name: String) -> Dictionary:
	var id := name.strip_edges().to_lower()
	if _defs.has(id):
		return (_defs[id] as Dictionary).duplicate(true)
	return {}


func is_reserved(name: String) -> bool:
	return _reserved.has(name.strip_edges().to_lower())


func sanitize_name(raw: String) -> String:
	var s := raw.strip_edges().to_lower()
	var out := ""
	for i in s.length():
		var ch := s.unicode_at(i)
		var ok := (ch >= 97 and ch <= 122) or (ch >= 48 and ch <= 57) or ch == 95
		if ok:
			out += String.chr(ch)
	if out.is_empty():
		out = "drv"
	if out.unicode_at(0) >= 48 and out.unicode_at(0) <= 57:
		out = "d_" + out
	return out


func unique_name(raw: String) -> String:
	var base := sanitize_name(raw)
	if not _defs.has(base) and not _reserved.has(base):
		return base
	var n := 2
	while _defs.has("%s_%d" % [base, n]) or _reserved.has("%s_%d" % [base, n]):
		n += 1
	return "%s_%d" % [base, n]


func add_driver(def: Dictionary) -> String:
	var typ := str(def.get("type", TYPE_LFO)).to_lower()
	if typ != TYPE_LFO and typ != TYPE_NOISE and typ != TYPE_RANDOM:
		typ = TYPE_LFO
	var id := unique_name(str(def.get("id", def.get("name", "drv"))))
	var made: Dictionary
	match typ:
		TYPE_NOISE:
			made = _make_noise(id, float(def.get("speed", 1.0)), float(def.get("smoothness", 0.6)), false)
		TYPE_RANDOM:
			made = _make_random(
				id,
				float(def.get("rate", 2.0)),
				float(def.get("min", 0.0)),
				float(def.get("max", 2.0)),
				false
			)
		_:
			made = _make_lfo(
				id,
				float(def.get("rate", 0.5)),
				float(def.get("depth", 1.0)),
				str(def.get("wave", "sine")),
				false
			)
	_defs[id] = made
	_phase[id] = _rng.randf()
	drivers_changed.emit()
	return id


func update_driver(name: String, patch: Dictionary) -> void:
	var id := name.strip_edges().to_lower()
	if not _defs.has(id):
		return
	var def: Dictionary = _defs[id]
	for k in patch.keys():
		var key := str(k)
		if key in ["id", "type", "builtin"]:
			continue
		def[key] = patch[k]
	if def.has("wave"):
		def["wave"] = _norm_wave(str(def["wave"]))
	if def.has("rate"):
		def["rate"] = clampf(float(def["rate"]), 0.05, 16.0)
	if def.has("depth"):
		def["depth"] = clampf(float(def["depth"]), 0.0, 1.5)
	if def.has("speed"):
		def["speed"] = clampf(float(def["speed"]), 0.05, 16.0)
	if def.has("smoothness"):
		def["smoothness"] = clampf(float(def["smoothness"]), 0.0, 1.0)
	_defs[id] = def


func remove_driver(name: String) -> bool:
	var id := name.strip_edges().to_lower()
	if not _defs.has(id):
		return false
	var def: Dictionary = _defs[id]
	if bool(def.get("builtin", false)):
		return false
	_defs.erase(id)
	_phase.erase(id)
	_noise_hold.erase(id)
	_rand_hold.erase(id)
	_rand_timer.erase(id)
	_values.erase(id)
	drivers_changed.emit()
	return true


func serialize() -> Dictionary:
	var tweaks: Dictionary = {}
	var custom: Array = []
	for name_any in _defs.keys():
		var name := str(name_any)
		var def: Dictionary = (_defs[name] as Dictionary).duplicate(true)
		if bool(def.get("builtin", false)):
			tweaks[name] = def
		else:
			custom.append(def)
	return {"tweaks": tweaks, "custom": custom}


func deserialize(data: Dictionary) -> void:
	_defs.clear()
	_phase.clear()
	_noise_hold.clear()
	_rand_hold.clear()
	_rand_timer.clear()
	_ensure_defaults()
	var tweaks: Variant = data.get("tweaks", {})
	if tweaks is Dictionary:
		for name_any in (tweaks as Dictionary).keys():
			var name := str(name_any)
			if not _defs.has(name):
				continue
			update_driver(name, tweaks[name] as Dictionary)
	var custom: Variant = data.get("custom", [])
	if custom is Array:
		for item in custom:
			if item is Dictionary:
				var d: Dictionary = item
				d["builtin"] = false
				var id := sanitize_name(str(d.get("id", d.get("name", "drv"))))
				if _reserved.has(id) or _defs.has(id):
					id = unique_name(id)
				d["id"] = id
				_defs[id] = d
				_phase[id] = _rng.randf()
	drivers_changed.emit()
