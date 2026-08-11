class_name SessionStore
extends RefCounted

## Last-session cache for playlist sidebar + fly-through stage.
## Lives at user:// so it does not overwrite shows/demo/show.json.

const SESSION_PATH := "user://hyperspace_session.json"
const VERSION := 1


static func has_session() -> bool:
	return FileAccess.file_exists(SESSION_PATH)


static func load_session() -> Dictionary:
	if not has_session():
		return {}
	var file := FileAccess.open(SESSION_PATH, FileAccess.READ)
	if file == null:
		push_warning("SessionStore: cannot open %s" % SESSION_PATH)
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("SessionStore: JSON parse error: %s" % json.get_error_message())
		return {}
	if not (json.data is Dictionary):
		return {}
	var data: Dictionary = json.data
	if int(data.get("version", 0)) > VERSION:
		push_warning("SessionStore: unsupported version %s" % str(data.get("version")))
	return data


static func save_session(data: Dictionary) -> bool:
	var payload := data.duplicate(true)
	payload["version"] = VERSION
	payload["saved_at"] = Time.get_datetime_string_from_system(true)
	var text := JSON.stringify(payload, "\t")
	var file := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SessionStore: cannot write %s" % SESSION_PATH)
		return false
	file.store_string(text)
	file.close()
	return true


static func clear_session() -> void:
	if not has_session():
		return
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("hyperspace_session.json")


static func entries_from_variant(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (raw is Array):
		return out
	for item in raw:
		if item is Dictionary:
			out.append((item as Dictionary).duplicate(true))
	return out
