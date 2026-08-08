extends Node

## Lightweight OSC receiver over UDP with KinectV2-OSC address parsing.

signal message_received(address: String, args: Array)
signal kinect_joint(body_id: int, joint_id: String, position: Vector3, tracking_state: String)
signal kinect_hand(body_id: int, hand_id: String, hand_state: String, confidence: String)

@export var listen_port: int = 12345
@export var enabled: bool = true

var _udp: PacketPeerUDP


func _ready() -> void:
	_start_listener()


func _start_listener() -> void:
	_udp = PacketPeerUDP.new()
	var ports: Array[int] = [listen_port, 12346, 12347, 9000]
	var bound := false
	for port in ports:
		var err := _udp.bind(port)
		if err == OK:
			listen_port = port
			bound = true
			print("OSCBus: listening on port %d" % listen_port)
			break
		_udp.close()
		_udp = PacketPeerUDP.new()
	if not bound:
		push_warning("OSCBus: could not bind an OSC port. Kinect OSC input disabled.")
		enabled = false



func _process(_delta: float) -> void:
	if not enabled or _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		_parse_packet(packet)


func _parse_packet(data: PackedByteArray) -> void:
	var offset := 0
	var address := _read_padded_string(data, offset)
	if address.is_empty():
		return
	offset = _align4(offset + address.length() + 1)
	if offset >= data.size():
		return
	var type_tag := _read_padded_string(data, offset)
	offset = _align4(offset + type_tag.length() + 1)
	var args: Array = []
	for i in type_tag.length():
		if offset >= data.size():
			break
		var tag: String = type_tag[i]
		match tag:
			"f":
				if offset + 4 <= data.size():
					args.append(data.decode_float(offset))
					offset += 4
			"i":
				if offset + 4 <= data.size():
					args.append(data.decode_s32(offset))
					offset += 4
			"s":
				var s := _read_padded_string(data, offset)
				args.append(s)
				offset = _align4(offset + s.length() + 1)
			"T":
				args.append(true)
			"F":
				args.append(false)
			_:
				break
	message_received.emit(address, args)
	_route_kinect(address, args)


func _route_kinect(address: String, args: Array) -> void:
	# KinectV2-OSC: /bodies/{bodyId}/joints/{jointId}
	if address.begins_with("/bodies/") and "/joints/" in address:
		var parts := address.split("/")
		if parts.size() >= 5:
			var body_id := int(parts[2])
			var joint_id := parts[4]
			if args.size() >= 4:
				var pos := Vector3(float(args[0]), float(args[1]), float(args[2]))
				var tracking := str(args[3])
				kinect_joint.emit(body_id, joint_id, pos, tracking)
	# KinectV2-OSC: /bodies/{bodyId}/hands/{handId}
	elif address.begins_with("/bodies/") and "/hands/" in address:
		var parts := address.split("/")
		if parts.size() >= 5:
			var body_id := int(parts[2])
			var hand_id := parts[4]
			var hand_state := str(args[0]) if args.size() > 0 else "Unknown"
			var confidence := str(args[1]) if args.size() > 1 else "Low"
			kinect_hand.emit(body_id, hand_id, hand_state, confidence)
	# OSCeleton-KinectSDK2: /osceleton2/joint
	elif address == "/osceleton2/joint" and args.size() >= 7:
		var joint_name := str(args[0])
		var user_id := int(args[2])
		var pos := Vector3(float(args[3]) / 100.0, -float(args[4]) / 100.0, float(args[5]) / 100.0)
		kinect_joint.emit(user_id, joint_name, pos, "Tracked")


func send_message(_address: String, _args: Array, _host: String = "127.0.0.1", _port: int = 9000) -> void:
	pass  # Outbound OSC reserved for future remote control


func _read_padded_string(data: PackedByteArray, from_offset: int) -> String:
	var end := from_offset
	while end < data.size() and data[end] != 0:
		end += 1
	if end <= from_offset:
		return ""
	return data.slice(from_offset, end).get_string_from_utf8()


func _align4(value: int) -> int:
	return (value + 3) & ~3
