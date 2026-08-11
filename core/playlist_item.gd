class_name PlaylistItem
extends RefCounted

## Runtime representation of one playlist entry from show.json.

var id: String = ""
var type: String = ""
var path: String = ""
var loop: bool = false
var duration: float = -1.0
var params: Dictionary = {}
var layers: Array = []  # for composite items


func _init(data: Dictionary = {}) -> void:
	if data.is_empty():
		return
	id = str(data.get("id", ""))
	type = str(data.get("type", ""))
	path = str(data.get("path", ""))
	loop = bool(data.get("loop", false))
	duration = float(data.get("duration", -1.0))
	var raw_params: Variant = data.get("params", {})
	if raw_params is Dictionary:
		params = (raw_params as Dictionary).duplicate(true)
	else:
		params = {}
	var raw_layers: Variant = data.get("layers", [])
	if raw_layers is Array:
		layers = (raw_layers as Array).duplicate(true)
	else:
		layers = []


func to_dict() -> Dictionary:
	## Round-trip for session / show.json serialization.
	var data := {
		"id": id,
		"type": type,
		"path": path,
		"loop": loop,
		"duration": duration,
		"params": params.duplicate(true),
	}
	if not layers.is_empty():
		data["layers"] = layers.duplicate(true)
	return data
