extends Control
class_name DualRangeSlider

## Dual-thumb range slider (min/max on one track). Godot HSlider is single-thumb only.

signal range_changed(low_value: float, high_value: float)

const GRABBER_W := 8.0
const TRACK_H := 6.0

@export var min_value: float = 0.0:
	set(v):
		min_value = v
		_clamp_values()
		queue_redraw()

@export var max_value: float = 100.0:
	set(v):
		max_value = maxf(v, min_value + 0.001)
		_clamp_values()
		queue_redraw()

@export var step: float = 1.0
@export var low_value: float = 0.0:
	set(v):
		low_value = _snap(v)
		if low_value > high_value:
			low_value = high_value
		queue_redraw()

@export var high_value: float = 100.0:
	set(v):
		high_value = _snap(v)
		if high_value < low_value:
			high_value = low_value
		queue_redraw()

## If true, thumbs are independent (low=Active, high=Inactive) and may cross.
@export var independent: bool = false

var _grab: int = -1  # 0=low, 1=high, -1=none


func _ready() -> void:
	custom_minimum_size = Vector2(120, 24)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_clamp_values()
	queue_redraw()

func set_range_values(low: float, high: float, emit_change: bool = false) -> void:
	if independent:
		low_value = _snap(clampf(low, min_value, max_value))
		high_value = _snap(clampf(high, min_value, max_value))
	else:
		var a := _snap(clampf(low, min_value, max_value))
		var b := _snap(clampf(high, min_value, max_value))
		if a > b:
			var t := a
			a = b
			b = t
		low_value = a
		high_value = b
	queue_redraw()
	if emit_change:
		range_changed.emit(low_value, high_value)


func get_low() -> float:
	return low_value


func get_high() -> float:
	return high_value


func _snap(v: float) -> float:
	if step <= 0.0:
		return v
	return snappedf(v, step)


func _clamp_values() -> void:
	low_value = _snap(clampf(low_value, min_value, max_value))
	high_value = _snap(clampf(high_value, min_value, max_value))
	if not independent and low_value > high_value:
		low_value = high_value


func _ratio(v: float) -> float:
	var span := max_value - min_value
	if absf(span) < 0.0001:
		return 0.0
	return clampf((v - min_value) / span, 0.0, 1.0)


func _from_ratio(r: float) -> float:
	return _snap(min_value + clampf(r, 0.0, 1.0) * (max_value - min_value))


func _x_for(v: float) -> float:
	var inner := maxf(size.x - GRABBER_W, 1.0)
	return GRABBER_W * 0.5 + _ratio(v) * inner


func _value_at_x(px: float) -> float:
	var inner := maxf(size.x - GRABBER_W, 1.0)
	var r := (px - GRABBER_W * 0.5) / inner
	return _from_ratio(r)


func _closest_thumb(px: float) -> int:
	var dl := absf(px - _x_for(low_value))
	var dh := absf(px - _x_for(high_value))
	return 0 if dl <= dh else 1


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_grab = _closest_thumb(mb.position.x)
			_set_thumb(_grab, _value_at_x(mb.position.x))
			accept_event()
		else:
			_grab = -1
			accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm and _grab >= 0:
		_set_thumb(_grab, _value_at_x(mm.position.x))
		accept_event()


func _set_thumb(which: int, v: float) -> void:
	v = _snap(clampf(v, min_value, max_value))
	if independent:
		if which == 0:
			low_value = v
		else:
			high_value = v
	else:
		if which == 0:
			low_value = minf(v, high_value)
		else:
			high_value = maxf(v, low_value)
	queue_redraw()
	range_changed.emit(low_value, high_value)


func _draw() -> void:
	var cy := size.y * 0.5
	var track := Rect2(0.0, cy - TRACK_H * 0.5, size.x, TRACK_H)
	draw_rect(track, Color(0.12, 0.12, 0.14, 1.0), true)
	var x0 := _x_for(low_value)
	var x1 := _x_for(high_value)
	var left := minf(x0, x1)
	var right := maxf(x0, x1)
	draw_rect(Rect2(left, track.position.y, maxf(right - left, 1.0), track.size.y), Color(0.35, 0.55, 0.85, 1.0), true)
	_draw_grabber(x0, cy)
	_draw_grabber(x1, cy)


func _draw_grabber(x: float, cy: float) -> void:
	var r := Rect2(x - GRABBER_W * 0.5, cy - 9.0, GRABBER_W, 18.0)
	draw_rect(r, Color(0.88, 0.9, 0.95, 1.0), true)
	draw_rect(r, Color(0.2, 0.22, 0.28, 1.0), false, 1.0)
