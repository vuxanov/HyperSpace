extends EffectLayer
class_name AsciiEffect

## ASCII / pixelate post-process with named presets.

const PRESETS := {
	"Classic": {"density": 80.0, "intensity": 0.85, "contrast": 1.0, "preset_mode": 0, "tint": Color.WHITE},
	"Dense": {"density": 140.0, "intensity": 0.9, "contrast": 1.2, "preset_mode": 0, "tint": Color.WHITE},
	"Sparse": {"density": 36.0, "intensity": 0.95, "contrast": 1.4, "preset_mode": 0, "tint": Color.WHITE},
	"Matrix": {"density": 90.0, "intensity": 0.92, "contrast": 1.3, "preset_mode": 1, "tint": Color(0.6, 1.0, 0.6)},
	"Amber": {"density": 70.0, "intensity": 0.88, "contrast": 1.1, "preset_mode": 2, "tint": Color(1.0, 0.85, 0.4)},
	"Neon": {"density": 100.0, "intensity": 0.8, "contrast": 1.5, "preset_mode": 3, "tint": Color(0.8, 0.6, 1.0)},
	"Blocks": {"density": 48.0, "intensity": 1.0, "contrast": 1.6, "preset_mode": 4, "tint": Color.WHITE},
}

var _rect: ColorRect


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
	if params.has("preset_mode"):
		mat.set_shader_parameter("preset_mode", int(params["preset_mode"]))
	if params.has("tint"):
		var tint: Variant = params["tint"]
		if tint is Color:
			mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))


func _shader_mat() -> ShaderMaterial:
	if _rect and _rect.material is ShaderMaterial:
		return _rect.material as ShaderMaterial
	return null


func _sync_visibility() -> void:
	visible = enabled
	if _rect:
		_rect.visible = enabled
