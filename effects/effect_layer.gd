extends CanvasLayer
class_name EffectLayer

## Base class for stackable post-process / overlay effects.

@export var effect_id: String = ""
@export var enabled: bool = false
@export var audio_band: int = 0  # which band drives this effect (0=bass-heavy)

## Raw params may be floats or expression strings (DriverHub.eval).
var _raw_params: Dictionary = {}
var _intensity: float = 1.0
var _last_lfo: float = 0.0
var _last_audio_drive: float = 0.0
## Kept for session/legacy keys; user-facing Mode UI is gone (Drivers tab).
var drive_mode: String = "auto"
var audio_sensitivity: float = 1.0
var lfo_rate: float = 0.45
var lfo_depth: float = 1.0
var lfo_wave: String = "sine"
var _lfo_phase: float = 0.0


func _make_screen_color_rect(shader_path: String) -> ColorRect:
	## Reliable screen-read inside Output SubViewport:
	## BackBufferCopy (viewport) then ColorRect. Transparent rect so a failed
	## sample never paints opaque white over the scene.
	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(bbc)

	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Alpha 0: if the shader fails to bind, scene still shows through.
	rect.color = Color(1, 1, 1, 0)
	var mat := ShaderMaterial.new()
	var shader: Shader = load(shader_path) as Shader
	if shader:
		mat.shader = shader
	rect.material = mat
	add_child(rect)
	return rect


func normalize_drive_mode(mode: String) -> String:
	var m := mode.to_lower()
	if m == "manual":
		return "auto"
	return m


func apply_params(params: Dictionary) -> void:
	for k in params.keys():
		_raw_params[k] = params[k]
	if params.has("intensity"):
		_intensity = eval_num("intensity", 1.0, 0.0, 8.0)
	if params.has("enabled"):
		enabled = bool(params["enabled"])
	if params.has("drive_mode"):
		drive_mode = normalize_drive_mode(str(params["drive_mode"]))
	if params.has("audio_sensitivity"):
		audio_sensitivity = clampf(float(params["audio_sensitivity"]), 0.0, 2.0)
	read_lfo_params(params)
	_on_params_changed(params)


func has_raw_param(key: String) -> bool:
	## Public so subclasses do not touch _raw_params (inherited _members can fail to parse).
	return _raw_params.has(key)


const EXPR_CLAMP := 1.0e6


func eval_num(key: String, fallback: float, pmin: float = -1.0e12, pmax: float = 1.0e12) -> float:
	## Slider min/max are drag-only. Applied value is never clamped to the slider max.
	var raw: Variant = _raw_params.get(key, fallback)
	var v := _eval_raw(raw, fallback)
	return clampf(v, -EXPR_CLAMP, EXPR_CLAMP)


func _raw_is_expr(raw: Variant) -> bool:
	if not (raw is String):
		return false
	var s := (raw as String).strip_edges()
	if s.is_empty() or s.is_valid_float():
		return false
	return true


func _eval_raw(raw: Variant, fallback: float) -> float:
	var hub := _driver_hub()
	if hub != null and hub.has_method("eval_value"):
		return float(hub.call("eval_value", raw, fallback))
	if raw is float or raw is int:
		return float(raw)
	if raw is String:
		var s := (raw as String).strip_edges()
		if s.is_valid_float():
			return s.to_float()
	return fallback


func _driver_hub() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("DriverHub")


func read_lfo_params(params: Dictionary) -> void:
	if params.has("lfo_rate"):
		lfo_rate = clampf(float(params["lfo_rate"]), 0.05, 8.0)
	if params.has("lfo_depth"):
		lfo_depth = clampf(float(params["lfo_depth"]), 0.0, 1.5)
	if params.has("lfo_wave"):
		lfo_wave = str(params["lfo_wave"]).to_lower()


func tick_own_lfo(delta: float) -> float:
	_lfo_phase = fposmod(_lfo_phase + delta * maxf(lfo_rate, 0.05), 1.0)
	var w := wave01(_lfo_phase, lfo_wave)
	var d := clampf(lfo_depth, 0.0, 1.5)
	_last_lfo = clampf(0.5 + (w - 0.5) * d, 0.0, 1.0)
	return _last_lfo


static func wave01(phase01: float, wave: String) -> float:
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


func apply_modulator(mod01: float) -> void:
	_last_lfo = clampf(mod01, 0.0, 1.0)


func apply_audio_state(_state: AudioState) -> void:
	pass


func resolve_drive(audio_value: float) -> float:
	return clampf(eval_num("intensity", _intensity, 0.0, 3.0), 0.0, 3.0)


func band01(state: AudioState, band: String) -> float:
	if state == null:
		return 0.0
	var raw := 0.0
	match band:
		"bass":
			raw = state.bass
		"mids":
			raw = state.mids
		"highs":
			raw = state.highs
		"kick":
			raw = state.kick
		"energy":
			raw = state.energy
		"peak":
			raw = state.peak
		_:
			raw = state.energy
	return clampf(pow(clampf(raw, 0.0, 1.0), 0.55), 0.0, 1.0)


func audio_scale(base: float, drive01: float, floor_ratio: float = 0.0) -> float:
	var d := clampf(drive01, 0.0, 1.0)
	var flo := clampf(floor_ratio, 0.0, 1.0)
	return base * lerpf(flo, 1.0, d)


func _on_params_changed(_params: Dictionary) -> void:
	pass
