extends HBoxContainer
class_name PlaylistRow

## One playlist row: drag to reorder, click name to replace, play / duration / delete.

signal play_pressed(index: int)
signal replace_pressed(index: int)
signal delete_pressed(index: int)
signal duration_changed(index: int, value: float)
signal reorder_drop(from_index: int, to_index: int)
signal files_dropped_on_row(index: int, paths: PackedStringArray)

var index: int = -1
var _item_btn: Button
var _play_btn: Button
var _dur: SpinBox
var _del_btn: Button
var _handle: Label


func setup(row_index: int, title: String, duration: float, selected: bool) -> void:
	index = row_index
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_handle = Label.new()
	_handle.text = "⋮⋮"
	_handle.tooltip_text = "Drag to reorder"
	_handle.mouse_filter = Control.MOUSE_FILTER_PASS
	_handle.custom_minimum_size = Vector2(22, 0)
	add_child(_handle)

	_item_btn = Button.new()
	_item_btn.text = title
	_item_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_item_btn.toggle_mode = true
	_item_btn.button_pressed = selected
	_item_btn.tooltip_text = "Click to replace this item"
	_item_btn.pressed.connect(func() -> void: replace_pressed.emit(index))
	add_child(_item_btn)

	_play_btn = Button.new()
	_play_btn.text = "▶"
	_play_btn.custom_minimum_size = Vector2(36, 0)
	_play_btn.tooltip_text = "Play this item"
	_play_btn.pressed.connect(func() -> void: play_pressed.emit(index))
	add_child(_play_btn)

	_dur = SpinBox.new()
	_dur.min_value = 1.0
	_dur.max_value = 600.0
	_dur.step = 1.0
	_dur.custom_minimum_size = Vector2(72, 0)
	_dur.suffix = "s"
	_dur.value = roundf(duration)
	_dur.value_changed.connect(func(v: float) -> void: duration_changed.emit(index, v))
	add_child(_dur)

	_del_btn = Button.new()
	_del_btn.text = "✕"
	_del_btn.custom_minimum_size = Vector2(36, 0)
	_del_btn.tooltip_text = "Remove from playlist"
	_del_btn.pressed.connect(func() -> void: delete_pressed.emit(index))
	add_child(_del_btn)


func _get_drag_data(_at_position: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = _item_btn.text if _item_btn else "Item"
	set_drag_preview(preview)
	return {"type": "playlist_reorder", "index": index}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if data is Dictionary:
		var d: Dictionary = data
		if str(d.get("type", "")) == "playlist_reorder":
			return int(d.get("index", -1)) != index
	if data is PackedStringArray:
		return true
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Dictionary:
		var d: Dictionary = data
		if str(d.get("type", "")) == "playlist_reorder":
			reorder_drop.emit(int(d.get("index", -1)), index)
			return
	if data is PackedStringArray:
		files_dropped_on_row.emit(index, data as PackedStringArray)
