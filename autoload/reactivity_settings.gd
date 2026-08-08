extends Node

## Global audio-reactivity routing — what reacts, on which axes, and how hard.

signal settings_changed

var enabled: bool = true
var affect_scale: bool = true
var scale_x: bool = true
var scale_y: bool = true
var scale_z: bool = true
var affect_light: bool = true
var affect_emission: bool = true
var affect_rotation: bool = true
var scale_amount: float = 5.0  # numeric multiplier — higher = much stronger scale reaction
var target: String = "centerpiece"  # centerpiece | scatter | environment | all | foreground (alias)


func set_enabled(value: bool) -> void:
	enabled = value
	settings_changed.emit()


func set_scale_amount(value: float) -> void:
	scale_amount = maxf(value, 0.0)
	settings_changed.emit()


func notify_changed() -> void:
	settings_changed.emit()


func scale_vector(base: float) -> Vector3:
	# `base` already includes scale_amount amplification from the caller.
	var amount := base - 1.0
	return Vector3(
		1.0 + amount if scale_x else 1.0,
		1.0 + amount if scale_y else 1.0,
		1.0 + amount if scale_z else 1.0
	)
