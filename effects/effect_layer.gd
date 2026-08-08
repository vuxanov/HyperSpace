extends CanvasLayer
class_name EffectLayer

## Base class for stackable post-process / overlay effects.

@export var effect_id: String = ""
@export var enabled: bool = false
@export var audio_band: int = 0  # which band drives this effect (0=bass-heavy)

var _intensity: float = 1.0


func apply_params(params: Dictionary) -> void:
	if params.has("intensity"):
		_intensity = float(params["intensity"])
	if params.has("enabled"):
		enabled = bool(params["enabled"])
	_on_params_changed(params)


func apply_audio_state(_state: AudioState) -> void:
	pass


func _on_params_changed(_params: Dictionary) -> void:
	pass
