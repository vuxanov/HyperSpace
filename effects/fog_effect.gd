extends EffectLayer
class_name FogEffect

## Distance fog / mist on the live WorldEnvironment (Godot Environment fog).
## Density / Start / End / Tint only — Fog Noise overlay is retired.
## Lighting catalog fog is the fallback when off.

## Gray-white mist before any Tint. Tint 0 stays this; Tint > 0 is a real hue, not a gray veil.
const BASE_COLOR := Color(0.76, 0.80, 0.84)
const DEFAULT_COLOR := BASE_COLOR
## Chroma only — mix a saturated HSV into BASE_COLOR. Does not change density/opacity.
const TINT_MIX := 0.95
const TINT_SAT := 0.98
const TINT_VAL := 0.86

var _density: float = 0.32
var _begin: float = 5.0
var _end: float = 32.0
## Hue degrees. 0 = no extra hue (plain BASE_COLOR). 1–360 = spectrum.
var _tint: float = 0.0


func _ready() -> void:
	effect_id = "fog"
	layer = 1
	visible = false
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var director: Node = tree.root.get_node_or_null("ShowDirector")
		if director != null and director.has_signal("item_changed"):
			if not director.is_connected("item_changed", Callable(self, "_on_item_changed")):
				director.connect("item_changed", Callable(self, "_on_item_changed"))


func _on_item_changed(_item_id: String = "", _index: int = -1) -> void:
	_push_to_scene(enabled)


func set_active(is_on: bool) -> void:
	enabled = is_on
	visible = false
	_push_to_scene(is_on)


func apply_params(params: Dictionary) -> void:
	super.apply_params(params)
	_resolve()
	if enabled:
		_push_to_scene(true)


func apply_audio_state(_state: AudioState) -> void:
	if not enabled:
		_push_to_scene(false)
		return
	_resolve()
	_push_to_scene(true)


func apply_modulator(_mod01: float) -> void:
	pass


func _on_params_changed(_params: Dictionary) -> void:
	_resolve()


func _resolve() -> void:
	_density = eval_num("density", _density, 0.0, 2.0)
	_begin = eval_num("begin", eval_num("fog_begin", _begin, 0.0, 800.0), 0.0, 800.0)
	_end = eval_num("end", eval_num("fog_end", _end, 0.5, 2000.0), 0.5, 2000.0)
	var pack := {
		"density": _density, "begin": _begin, "end": _end,
		"color": raw_param("color", raw_param("fog_color", {})),
	}
	if has_raw_param("tint"):
		_tint = eval_num("tint", _tint, 0.0, 360.0)
		pack["tint"] = _tint
	var cleaned := sanitize_params(pack)
	_density = float(cleaned["density"])
	_begin = float(cleaned["begin"])
	_end = float(cleaned["end"])
	_tint = float(cleaned["tint"])


static func tinted_fog_color(tint_hue: float) -> Color:
	## 0 = plain gray-white mist. Otherwise a saturated hue at the same brightness (not thicker).
	var t := clampf(tint_hue, 0.0, 360.0)
	if t <= 0.5:
		return BASE_COLOR
	var hue01 := fposmod(t, 360.0) / 360.0
	var spectral := Color.from_hsv(hue01, TINT_SAT, TINT_VAL)
	return BASE_COLOR.lerp(spectral, TINT_MIX)


static func tint_from_params(params: Dictionary) -> float:
	if params.has("tint"):
		return clampf(float(params["tint"]), 0.0, 360.0)
	if params.has("color") or params.has("fog_color"):
		return _hue_from_legacy_color(params.get("color", params.get("fog_color", {})))
	return 0.0


static func _hue_from_legacy_color(raw: Variant) -> float:
	## Old Color picker stored RGB. Near-base gray → 0 (no tint). Else hue 1–360.
	var c := color_from_param(raw, BASE_COLOR)
	var delta := absf(c.r - BASE_COLOR.r) + absf(c.g - BASE_COLOR.g) + absf(c.b - BASE_COLOR.b)
	if delta <= 0.08 or c.s <= 0.06:
		return 0.0
	var deg := c.h * 360.0
	if deg < 0.5:
		return 360.0
	return clampf(deg, 1.0, 360.0)


static func color_from_param(raw: Variant, fallback: Color = BASE_COLOR) -> Color:
	if raw is Color:
		return raw as Color
	if raw is Dictionary:
		var d: Dictionary = raw
		return Color(
			float(d.get("r", fallback.r)),
			float(d.get("g", fallback.g)),
			float(d.get("b", fallback.b)),
			1.0
		)
	if raw is String:
		var s := str(raw).strip_edges()
		if not s.is_empty():
			return Color.from_string(s, fallback)
	return fallback


static func sanitize_params(params: Dictionary) -> Dictionary:
	## Old 0.12 / 40 m / 140 m sat behind typical flythrough geometry (hero ~3 m, env tens of meters).
	var out := params.duplicate(true)
	var density := float(out.get("density", 0.32))
	var fog_begin := float(out.get("begin", out.get("fog_begin", 5.0)))
	var fog_end := float(out.get("end", out.get("fog_end", 32.0)))
	if absf(density - 0.12) <= 0.02 and absf(fog_begin - 40.0) <= 1.5:
		density = 0.32
		fog_begin = 5.0
		if absf(fog_end - 140.0) <= 2.0 or fog_end >= 100.0:
			fog_end = 32.0
	out["density"] = density
	out["begin"] = fog_begin
	out["end"] = fog_end
	out.erase("noise")
	out.erase("noise_scale")
	out["tint"] = tint_from_params(out)
	return out


func _pack() -> Dictionary:
	return {
		"density": _density,
		"begin": _begin,
		"end": _end,
		"tint": _tint,
	}


func _push_to_scene(on: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var director: Node = tree.root.get_node_or_null("ShowDirector")
	if director == null:
		return
	var node: Variant = director.get("current_item_node")
	if node != null and node is Node and (node as Node).has_method("set_fog"):
		(node as Node).call("set_fog", on, _pack() if on else {})
