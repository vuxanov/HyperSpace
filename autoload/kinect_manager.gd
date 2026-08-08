extends Node

## Aggregates raw OSC Kinect messages into a per-frame KinectState resource.

signal state_updated(state: KinectState)

var current_state: KinectState = KinectState.new()
var enabled: bool = true
var smoothing: float = 0.35

var _body_cache: Dictionary = {}  # body_id -> KinectBody
var _joint_map: Dictionary = {
	"HandLeft": "HandLeft", "HandRight": "HandRight",
	"Head": "Head", "SpineShoulder": "SpineShoulder",
	"SpineMid": "SpineMid", "SpineBase": "SpineBase",
	"ElbowLeft": "ElbowLeft", "ElbowRight": "ElbowRight",
	"ShoulderLeft": "ShoulderLeft", "ShoulderRight": "ShoulderRight",
}


func _ready() -> void:
	OSCBus.kinect_joint.connect(_on_kinect_joint)
	OSCBus.kinect_hand.connect(_on_kinect_hand)


func _process(_delta: float) -> void:
	_finalize_frame()


func _on_kinect_joint(body_id: int, joint_id: String, position: Vector3, tracking_state: String) -> void:
	if not enabled:
		return
	var body: KinectBody = _get_or_create_body(body_id)
	var mapped: String = str(_joint_map.get(joint_id, joint_id))
	if body.joints.has(mapped):
		var previous: Vector3 = body.joints[mapped] as Vector3
		body.joints[mapped] = previous.lerp(position, smoothing)
	else:
		body.joints[mapped] = position
	body.is_tracked = tracking_state != "NotTracked"


func _on_kinect_hand(body_id: int, hand_id: String, hand_state: String, _confidence: String) -> void:
	if not enabled:
		return
	var body: KinectBody = _get_or_create_body(body_id)
	body.hand_states[hand_id] = hand_state


func _get_or_create_body(body_id: int) -> KinectBody:
	if not _body_cache.has(body_id):
		var body := KinectBody.new()
		body.body_id = body_id
		_body_cache[body_id] = body
	return _body_cache[body_id] as KinectBody


func _finalize_frame() -> void:
	var bodies: Array[KinectBody] = []
	for body_id in _body_cache:
		var body: KinectBody = _body_cache[body_id] as KinectBody
		body.centroid = _compute_centroid(body)
		if body.is_tracked:
			bodies.append(body)
	current_state.bodies = bodies
	current_state.body_count = bodies.size()
	current_state.primary_body = bodies[0] if bodies.size() > 0 else null
	state_updated.emit(current_state)
	_body_cache.clear()


func _compute_centroid(body: KinectBody) -> Vector3:
	var keys: Array[String] = ["SpineMid", "SpineShoulder", "SpineBase", "Head"]
	var total := Vector3.ZERO
	var count := 0
	for key in keys:
		if body.joints.has(key):
			total += body.joints[key] as Vector3
			count += 1
	if count == 0:
		return Vector3.ZERO
	return total / float(count)


func get_state() -> KinectState:
	return current_state.duplicate_state()
