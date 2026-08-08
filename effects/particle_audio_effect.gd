extends EffectLayer
class_name ParticleAudioEffect

## Marker effect — actual breakup happens on 3D objects (DemoEnvironment).
## This layer stays lightweight so the toggle still works through ShowDirector.

func _ready() -> void:
	effect_id = "particles"
	layer = 5
	visible = false


func set_active(is_on: bool) -> void:
	enabled = is_on
	visible = false  # mesh→particles is handled inside the 3D environment


func apply_audio_state(_state: AudioState) -> void:
	pass


func _on_params_changed(_params: Dictionary) -> void:
	visible = false
