class_name ShowLoader
extends RefCounted

## Loads and validates show.json manifests.


static func load_show(show_path: String) -> Dictionary:
	var file := FileAccess.open(show_path, FileAccess.READ)
	if file == null:
		push_error("ShowLoader: cannot open %s" % show_path)
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("ShowLoader: JSON parse error in %s: %s" % [show_path, json.get_error_message()])
		return {}
	var data: Dictionary = json.data
	return normalize_show(data, show_path.get_base_dir())


static func normalize_show(data: Dictionary, show_dir: String) -> Dictionary:
	var result := {
		"name": str(data.get("name", "Untitled Show")),
		"show_dir": show_dir,
		"items": [],
		"cues": [],
		"params": data.get("params", {}),
		"effects": data.get("effects", []),
	}
	for item_data in data.get("items", []):
		if item_data is Dictionary:
			var item := PlaylistItem.new(item_data)
			if not item.path.is_empty() and not item.path.begins_with("res://"):
				item.path = show_dir.path_join(item.path)
			result["items"].append(item)
	for cue_data in data.get("cues", []):
		if cue_data is Dictionary:
			result["cues"].append(cue_data)
	return result


static func find_item(items: Array, item_id: String) -> PlaylistItem:
	for item in items:
		if item is PlaylistItem and item.id == item_id:
			return item
	return null


static func validate_show(data: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	if not data.has("items"):
		errors.append("Missing 'items' array")
		return errors
	var ids: Dictionary = {}
	for item in data.get("items", []):
		if item is PlaylistItem:
			if item.id.is_empty():
				errors.append("Item missing id")
			elif ids.has(item.id):
				errors.append("Duplicate item id: %s" % item.id)
			else:
				ids[item.id] = true
			if item.type.is_empty():
				errors.append("Item '%s' missing type" % item.id)
	for cue in data.get("cues", []):
		if cue is Dictionary and not cue.has("id"):
			errors.append("Cue missing id")
	return errors
