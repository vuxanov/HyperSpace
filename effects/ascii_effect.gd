extends EffectLayer
class_name AsciiEffect

## True ASCII post-process: luminance picks a character from a preset charset atlas.
## Character presets mirror vuxanov/ASCII Live Visuals Engine — ramps are reversed
## so dark→bright maps sparse→dense for HyperSpace's source-tint overlay shader.

const PRESETS := {
	# ASCII app: "@%#*+=-:. " (dense→sparse). HyperSpace: sparse→dense.
	"Standard": {
		"density": 80.0, "intensity": 0.92, "contrast": 1.25,
		"charset": " .:-=+*#%@", "tint": Color.WHITE, "cell_aspect": 0.55
	},
	# ASCII app: "█▓▒░ ". HyperSpace: " ░▒▓█".
	"Blocks": {
		"density": 56.0, "intensity": 1.0, "contrast": 1.5,
		"charset": " ░▒▓█", "tint": Color.WHITE, "cell_aspect": 1.0
	},
	# ASCII app: "●○•· ". HyperSpace: " ·•○●".
	"Minimal": {
		"density": 72.0, "intensity": 0.94, "contrast": 1.35,
		"charset": " ·•○●", "tint": Color.WHITE, "cell_aspect": 0.7
	},
	# ASCII app: "01" (dark=0, bright=1) — same order works here.
	"Binary": {
		"density": 100.0, "intensity": 0.95, "contrast": 1.4,
		"charset": "01", "tint": Color(0.45, 1.0, 0.55), "cell_aspect": 0.7
	},
	# ASCII app half-width katakana set (same order as the web generator).
	"Matrix": {
		"density": 100.0, "intensity": 0.94, "contrast": 1.35,
		"charset": "ｦｱｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄ",
		"tint": Color(0.35, 1.0, 0.45), "cell_aspect": 0.65
	},
	# Live Visuals Engine “dots” style.
	"Dots": {
		"density": 160.0, "intensity": 0.9, "contrast": 1.1,
		"charset": " ·•○●", "tint": Color(0.91, 0.84, 1.0), "cell_aspect": 0.7
	},
	# Live Visuals Engine glitch mosaic blocks.
	"Glitch": {
		"density": 90.0, "intensity": 0.96, "contrast": 1.6,
		"charset": " ▚▞▙▛▜▟█", "tint": Color(0.0, 1.0, 0.97), "cell_aspect": 1.0
	},
	# Live Visuals Engine pixel bar ramp.
	"Pixel": {
		"density": 120.0, "intensity": 0.95, "contrast": 1.9,
		"charset": " ▁▂▃▄▅▆▇█", "tint": Color(0.22, 0.74, 0.97), "cell_aspect": 0.55
	},
	# Live Visuals Engine braille density ramp (subset with bitmaps).
	"Braille": {
		"density": 110.0, "intensity": 0.93, "contrast": 1.7,
		"charset": " ⠁⠂⠃⠄⠅⠆⠇⠸⠿", "tint": Color(0.66, 0.55, 0.98), "cell_aspect": 0.7
	},
}

## Older HyperSpace / show names → current ASCII-app presets.
const PRESET_ALIASES := {
	"Classic": "Standard",
	"Dense": "Standard",
	"Sparse": "Minimal",
	"Amber": "Minimal",
	"Neon": "Binary",
}


var _rect: ColorRect
var _atlas_cache: Dictionary = {}  # charset -> ImageTexture
var _invert: bool = false
var _base_charset: String = " .:-=+*#%@"
var _density_min: float = 40.0
var _density_max: float = 80.0


func _ready() -> void:
	effect_id = "ascii"
	layer = 10
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://effects/ascii_effect.gdshader")
	_rect.material = mat
	add_child(_rect)
	visible = false
	apply_preset("Standard")


func apply_preset(preset_name: String) -> void:
	var resolved := _resolve_preset_name(preset_name)
	if not PRESETS.has(resolved):
		return
	var params: Dictionary = PRESETS[resolved].duplicate()
	params["invert"] = _invert
	apply_params(params)


func apply_params(params: Dictionary) -> void:
	super.apply_params(params)
	_apply_shader_params(params)
	_sync_visibility()


func set_active(is_on: bool) -> void:
	enabled = is_on
	_sync_visibility()


func apply_audio_state(state: AudioState) -> void:
	if not enabled:
		_sync_visibility()
		return
	_sync_visibility()
	var mat := _shader_mat()
	if mat:
		mat.set_shader_parameter("audio_highs", state.highs * _intensity)
		var dens := lerpf(_density_min, _density_max, clampf(state.energy, 0.0, 1.0))
		mat.set_shader_parameter("density", dens)


func apply_modulator(mod01: float) -> void:
	if not enabled:
		return
	var mat := _shader_mat()
	if mat:
		mat.set_shader_parameter("audio_highs", maxf(float(mat.get_shader_parameter("audio_highs")), mod01 * _intensity))
		var dens := lerpf(_density_min, _density_max, clampf(mod01, 0.0, 1.0))
		mat.set_shader_parameter("density", dens)


func _on_params_changed(params: Dictionary) -> void:
	_apply_shader_params(params)
	_sync_visibility()


func _resolve_preset_name(preset_name: String) -> String:
	if PRESETS.has(preset_name):
		return preset_name
	return str(PRESET_ALIASES.get(preset_name, preset_name))


func _apply_shader_params(params: Dictionary) -> void:
	var mat := _shader_mat()
	if mat == null:
		return
	if params.has("density_min") or params.has("density_max") or params.has("density"):
		var d_single := float(params.get("density", 80.0))
		_density_min = float(params.get("density_min", maxf(1.0, d_single * 0.65)))
		_density_max = float(params.get("density_max", d_single))
		if _density_min > _density_max:
			var tmp := _density_min
			_density_min = _density_max
			_density_max = tmp
		_density_min = clampf(_density_min, 1.0, 200.0)
		_density_max = clampf(_density_max, 1.0, 200.0)
		mat.set_shader_parameter("density", lerpf(_density_min, _density_max, 0.5))
	if params.has("intensity"):
		mat.set_shader_parameter("intensity", float(params["intensity"]))
	if params.has("contrast"):
		mat.set_shader_parameter("contrast", float(params["contrast"]))
	if params.has("cell_aspect"):
		mat.set_shader_parameter("cell_aspect", float(params["cell_aspect"]))
	if params.has("tint"):
		var tint: Variant = params["tint"]
		if tint is Color:
			mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	if params.has("invert"):
		_invert = bool(params["invert"])
	var charset := str(params.get("charset", _base_charset))
	_base_charset = charset
	charset = AsciiCharset.filter_charset(charset)
	if _invert:
		charset = _reverse_charset(charset)
	var atlas := _atlas_for(charset)
	mat.set_shader_parameter("ascii_atlas", atlas)
	mat.set_shader_parameter("charset_len", charset.length())


func _reverse_charset(charset: String) -> String:
	var out := ""
	for i in range(charset.length() - 1, -1, -1):
		out += charset.substr(i, 1)
	return out


func _atlas_for(charset: String) -> ImageTexture:
	if _atlas_cache.has(charset):
		return _atlas_cache[charset]
	var tex := AsciiCharset.build_atlas(charset)
	_atlas_cache[charset] = tex
	return tex


func _shader_mat() -> ShaderMaterial:
	if _rect and _rect.material is ShaderMaterial:
		return _rect.material as ShaderMaterial
	return null


func _sync_visibility() -> void:
	visible = enabled
	if _rect:
		_rect.visible = enabled
