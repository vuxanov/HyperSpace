class_name KinectState
extends Resource

## Aggregated Kinect tracking state for the current frame.

@export var bodies: Array[KinectBody] = []
@export var body_count: int = 0
@export var primary_body: KinectBody = null


func duplicate_state() -> KinectState:
	var copy := KinectState.new()
	copy.body_count = body_count
	copy.bodies = bodies.duplicate()
	copy.primary_body = primary_body
	return copy
