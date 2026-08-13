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
	"Emoji": {
		"density": 72.0, "intensity": 1.0, "contrast": 1.45,
		"charset": " ▫▪□■⬜🔲🔳⬛", "tint": Color(1.0, 0.92, 0.55), "cell_aspect": 1.0
	},
	"Faces": {
		"density": 64.0, "intensity": 0.96, "contrast": 1.35,
		"charset": " ·✧⭐❤💫🔥", "tint": Color(1.0, 0.72, 0.42), "cell_aspect": 1.0
	},
	"Runes": {
		"density": 88.0, "intensity": 0.94, "contrast": 1.4,
		"charset": " ᛁᚾᚲᚢᚠᚦᚱᚺᛏᛉᛊᛒᛗ", "tint": Color(0.72, 0.88, 1.0), "cell_aspect": 0.7
	},
	"Cyrillic": {
		"density": 90.0, "intensity": 0.93, "contrast": 1.3,
		"charset": " іосеанкджшщЖШМ", "tint": Color(0.95, 0.82, 1.0), "cell_aspect": 0.65
	},
	"Crosses": {
		"density": 84.0, "intensity": 0.95, "contrast": 1.55,
		"charset": " +×✕†‡✚✙┼╋✖", "tint": Color(1.0, 0.55, 0.62), "cell_aspect": 0.7
	},
	"Stars": {
		"density": 96.0, "intensity": 0.92, "contrast": 1.35,
		"charset": " ·✧✦☆★✪", "tint": Color(1.0, 0.88, 0.45), "cell_aspect": 0.75
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
var _base_intensity: float = 0.92
var _base_contrast: float = 1.25
var _style_index: int = -1


func _ready() -> void:
	effect_id = "ascii"
	layer = 10
	# Same BackBufferCopy → ColorRect path as other screen LFX.
	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(bbc)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color(1, 1, 1, 0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://effects/ascii_effect.gdshader")
	_rect.material = mat
	add_child(_rect)
	visible = false
	set_process(false)
	apply_preset("Standard")


func _process(_delta: float) -> void:
	if not enabled:
		set_process(false)


func apply_preset(preset_name: String) -> void:
	var resolved := _resolve_preset_name(preset_name)
	if not PRESETS.has(resolved):
		return
	var params: Dictionary = PRESETS[resolved].duplicate()
	params["charset"] = PRESETS[resolved].get("charset", _base_charset)
	apply_params(params)


func apply_params(params: Dictionary) -> void:
	super.apply_params(params)
	_apply_shader_params(params)
	_apply_resolved()
	_sync_visibility()
	set_process(false)


func set_active(is_on: bool) -> void:
	enabled = is_on
	_sync_visibility()
	set_process(false)


func apply_audio_state(_state: AudioState) -> void:
	if not enabled:
		_sync_visibility()
		return
	_sync_visibility()
	_apply_resolved()


func apply_modulator(_mod01: float) -> void:
	pass


func _apply_resolved() -> void:
	var mat := _shader_mat()
	if mat == null:
		return
	_apply_driven_style()
	_density_min = eval_num("density_min", _density_min, 1.0, 200.0)
	_density_max = eval_num("density_max", _density_max, 1.0, 200.0)
	if _density_min > _density_max:
		var tmp := _density_min
		_density_min = _density_max
		_density_max = tmp
	_base_intensity = eval_num("intensity", _base_intensity, 0.0, 4.0)
	_base_contrast = eval_num("contrast", _base_contrast, 0.1, 4.0)
	var dens := lerpf(_density_min, _density_max, 0.5)
	if has_raw_param("density"):
		dens = eval_num("density", dens, 1.0, 200.0)
	mat.set_shader_parameter("audio_highs", 0.0)
	mat.set_shader_parameter("density", dens)
	mat.set_shader_parameter("intensity", _base_intensity)
	mat.set_shader_parameter("contrast", _base_contrast)


func _on_params_changed(params: Dictionary) -> void:
	_apply_shader_params(params)
	_sync_visibility()


func _resolve_preset_name(preset_name: String) -> String:
	if PRESETS.has(preset_name):
		return preset_name
	return str(PRESET_ALIASES.get(preset_name, preset_name))


static func wrap_style_index(v: float) -> int:
	var n := PRESETS.size()
	if n <= 0:
		return 0
	return posmod(int(floor(v)), n)


func _apply_driven_style() -> void:
	## Driver/expression on style_index selects a preset charset (wraps). Density is separate.
	if not has_raw_param("style_index"):
		return
	var names: Array = PRESETS.keys()
	var n := names.size()
	if n <= 0:
		return
	var idx := wrap_style_index(eval_num("style_index", 0.0))
	if idx == _style_index:
		return
	_style_index = idx
	var pname := str(names[idx])
	var p: Dictionary = PRESETS.get(pname, {})
	if p.is_empty():
		return
	var mat := _shader_mat()
	if mat == null:
		return
	if p.has("cell_aspect"):
		mat.set_shader_parameter("cell_aspect", float(p["cell_aspect"]))
	if p.has("tint"):
		var tint: Variant = p["tint"]
		if tint is Color:
			mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	var charset := str(p.get("charset", _base_charset))
	_base_charset = charset
	charset = AsciiCharset.filter_charset(charset)
	var atlas := _atlas_for(charset)
	mat.set_shader_parameter("ascii_atlas", atlas)
	mat.set_shader_parameter("charset_len", charset.length())


func _apply_shader_params(params: Dictionary) -> void:
	var mat := _shader_mat()
	if mat == null:
		return
	if params.has("density_min") or params.has("density_max"):
		_density_min = eval_num("density_min", _density_min, 1.0, 200.0)
		_density_max = eval_num("density_max", _density_max, 1.0, 200.0)
		if _density_min > _density_max:
			var tmp := _density_min
			_density_min = _density_max
			_density_max = tmp
	elif params.has("density"):
		var d_single := eval_num("density", 80.0, 1.0, 200.0)
		_density_min = maxf(1.0, d_single * 0.65)
		_density_max = d_single
	if params.has("intensity"):
		_base_intensity = eval_num("intensity", _base_intensity, 0.0, 4.0)
	if params.has("contrast"):
		_base_contrast = eval_num("contrast", _base_contrast, 0.1, 4.0)
	if params.has("cell_aspect"):
		mat.set_shader_parameter("cell_aspect", float(params["cell_aspect"]))
	if params.has("tint"):
		var tint: Variant = params["tint"]
		if tint is Color:
			mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	_invert = false
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
