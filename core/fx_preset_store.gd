class_name FxPresetStore
extends RefCounted

## Named effect-stack snapshots, played under Auto Mode → Presets (not Play All).
## Lives at user:// so it does not overwrite shows/ or the last session.

const PRESETS_PATH := "user://hyperspace_fx_presets.json"
const VERSION := 1


static func list_names() -> PackedStringArray:
	var names := PackedStringArray()
	var presets := _read_presets()
	var keys: Array = presets.keys()
	keys.sort()
	for k in keys:
		names.append(str(k))
	return names


static func get_preset(preset_name: String) -> Dictionary:
	var key := preset_name.strip_edges()
	if key.is_empty():
		return {}
	var presets := _read_presets()
	if not presets.has(key):
		return {}
	var raw: Variant = presets[key]
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {}


static func save_preset(preset_name: String, data: Dictionary) -> bool:
	var key := preset_name.strip_edges()
	if key.is_empty():
		return false
	var presets := _read_presets()
	var payload := data.duplicate(true)
	payload["name"] = key
	payload["saved_at"] = Time.get_datetime_string_from_system(true)
	presets[key] = payload
	return _write_presets(presets)


static func delete_preset(preset_name: String) -> bool:
	var key := preset_name.strip_edges()
	if key.is_empty():
		return false
	var presets := _read_presets()
	if not presets.has(key):
		return false
	presets.erase(key)
	return _write_presets(presets)


static func rename_preset(preset_name: String, new_name: String) -> bool:
	var old_key := preset_name.strip_edges()
	var new_key := new_name.strip_edges()
	if old_key.is_empty() or new_key.is_empty():
		return false
	if old_key == new_key:
		return true
	var presets := _read_presets()
	if not presets.has(old_key) or presets.has(new_key):
		return false
	var raw: Variant = presets[old_key]
	if not (raw is Dictionary):
		return false
	var payload: Dictionary = (raw as Dictionary).duplicate(true)
	payload["name"] = new_key
	presets.erase(old_key)
	presets[new_key] = payload
	return _write_presets(presets)


static func has_preset(preset_name: String) -> bool:
	return _read_presets().has(preset_name.strip_edges())


static func _read_file() -> Dictionary:
	if not FileAccess.file_exists(PRESETS_PATH):
		return {}
	var file := FileAccess.open(PRESETS_PATH, FileAccess.READ)
	if file == null:
		push_warning("FxPresetStore: cannot open %s" % PRESETS_PATH)
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("FxPresetStore: JSON parse error: %s" % json.get_error_message())
		return {}
	if not (json.data is Dictionary):
		return {}
	return json.data as Dictionary


static func _read_presets() -> Dictionary:
	var data := _read_file()
	var raw: Variant = data.get("presets", {})
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {}


static func _write_presets(presets: Dictionary) -> bool:
	var payload := {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"presets": presets.duplicate(true),
	}
	var text := JSON.stringify(payload, "\t")
	var file := FileAccess.open(PRESETS_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("FxPresetStore: cannot write %s" % PRESETS_PATH)
		return false
	file.store_string(text)
	file.close()
	return true
