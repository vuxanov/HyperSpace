class_name CueAction
extends RefCounted

## One atomic cue operation (play, crossfade, set_effect, etc.).

var op: String = ""
var item_id: String = ""
var effect: String = ""
var duration: float = 0.0
var enabled: bool = true
var params: Dictionary = {}


static func from_dict(data: Dictionary) -> CueAction:
	var action := CueAction.new()
	action.op = str(data.get("op", ""))
	action.item_id = str(data.get("item", data.get("item_id", "")))
	action.effect = str(data.get("effect", ""))
	action.duration = float(data.get("duration", 0.0))
	action.enabled = bool(data.get("enabled", true))
	action.params = data.get("params", {})
	return action
