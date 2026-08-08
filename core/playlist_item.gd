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
	params = data.get("params", {})
	layers = data.get("layers", [])
