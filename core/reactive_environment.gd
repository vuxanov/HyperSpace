class_name ReactiveEnvironment
extends Node3D

## Base class for 3D environments with optional audio/Kinect reactivity hooks.


func apply_audio_state(_state: AudioState) -> void:
	pass


func apply_kinect_state(_state: KinectState) -> void:
	pass


func set_cue_param(_key: String, _value: Variant) -> void:
	pass


func on_item_started() -> void:
	pass


func on_item_stopped() -> void:
	pass
