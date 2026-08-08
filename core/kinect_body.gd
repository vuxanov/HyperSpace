class_name KinectBody
extends Resource

## Normalized skeleton data for one tracked body.

@export var body_id: int = -1
@export var joints: Dictionary = {}  # joint_name -> Vector3
@export var hand_states: Dictionary = {}  # "Left"/"Right" -> String
@export var centroid: Vector3 = Vector3.ZERO
@export var is_tracked: bool = false


func get_joint(joint_name: String) -> Vector3:
	return joints.get(joint_name, Vector3.ZERO)


func both_hands_raised(threshold: float = 1.2) -> bool:
	var left := get_joint("HandLeft")
	var right := get_joint("HandRight")
	var spine := get_joint("SpineShoulder")
	if spine == Vector3.ZERO:
		spine = get_joint("SpineMid")
	return left.y > spine.y + threshold and right.y > spine.y + threshold
