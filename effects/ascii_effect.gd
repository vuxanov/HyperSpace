extends EffectLayer
class_name AsciiEffect

## True ASCII post-process: luminance picks a character from a preset charset atlas.

const PRESETS := {
	"Classic": {
		"density": 90.0, "intensity": 0.92, "contrast": 1.25,
		"charset": " .:-=+*#%@", "tint": Color.WHITE, "cell_aspect": 0.55
	},
	"Dense": {
		"density": 130.0, "intensity": 0.9, "contrast": 1.15,
		"charset": " .'`^\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$",
		"tint": Color.WHITE, "cell_aspect": 0.6
	},
	"Sparse": {
		"density": 48.0, "intensity": 0.95, "contrast": 1.45,
		"charset": " .-+*%@", "tint": Color.WHITE, "cell_aspect": 0.5
	},
	"Matrix": {
		"density": 100.0, "intensity": 0.94, "contrast": 1.35,
		"charset": " 01ZIHX#@", "tint": Color(0.45, 1.0, 0.5), "cell_aspect": 0.7
	},
	"Amber": {
		"density": 80.0, "intensity": 0.9, "contrast": 1.2,
		"charset": " ·•○●#%█", "tint": Color(1.0, 0.82, 0.35), "cell_aspect": 0.55
	},
	"Neon": {
		"density": 110.0, "intensity": 0.88, "contrast": 1.4,
		"charset": " .·:+*xX#@", "tint": Color(0.75, 0.55, 1.0), "cell_aspect": 0.55
	},
	"Blocks": {
		"density": 56.0, "intensity": 1.0, "contrast": 1.5,
		"charset": " ░▒▓█", "tint": Color.WHITE, "cell_aspect": 1.0
	},
}

var _rect: ColorRect
var _atlas_cache: Dictionary = {}  # charset -> ImageTexture


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
	apply_preset("Classic")


func apply_preset(preset_name: String) -> void:
	if not PRESETS.has(preset_name):
		return
	apply_params(PRESETS[preset_name])


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


func _on_params_changed(params: Dictionary) -> void:
	_apply_shader_params(params)
	_sync_visibility()


func _apply_shader_params(params: Dictionary) -> void:
	var mat := _shader_mat()
	if mat == null:
		return
	if params.has("density"):
		mat.set_shader_parameter("density", float(params["density"]))
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
	var charset := str(params.get("charset", " .:-=+*#%@"))
	charset = AsciiCharset.filter_charset(charset)
	var atlas := _atlas_for(charset)
	mat.set_shader_parameter("ascii_atlas", atlas)
	mat.set_shader_parameter("charset_len", charset.length())


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
