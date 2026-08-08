extends EffectLayer
class_name ParticleAudioEffect

## Toggle + target routing. Breakup is applied inside items/environments.

func _ready() -> void:
	effect_id = "particles"
	layer = 5
	visible = false


func set_active(is_on: bool) -> void:
	enabled = is_on
	visible = false


func apply_params(params: Dictionary) -> void:
	super.apply_params(params)
	if params.has("target"):
		var hub = load("res://core/reactivity_hub.gd")
		hub.set_field("particles_target", str(params["target"]))


func apply_audio_state(_state: AudioState) -> void:
	pass


func _on_params_changed(params: Dictionary) -> void:
	if params.has("target"):
		var hub = load("res://core/reactivity_hub.gd")
		hub.set_field("particles_target", str(params["target"]))
	visible = false
