extends VBoxContainer
class_name DualRangeSlider

## Dual-thumb range (min/max) plus a driver-capable field on each end.

const SliderSpinLinkScr := preload("res://ui/slider_spin_link.gd")

signal range_changed(low_value: float, high_value: float)

const GRABBER_W := 8.0
const TRACK_H := 6.0

@export var min_value: float = 0.0:
	set(v):
		min_value = v
		_clamp_values()
		if _low_slider:
			_low_slider.min_value = min_value
		if _high_slider:
			_high_slider.min_value = min_value
		if _track:
			_track.queue_redraw()

@export var max_value: float = 100.0:
	set(v):
		max_value = maxf(v, min_value + 0.001)
		_clamp_values()
		if _low_slider:
			_low_slider.max_value = max_value
		if _high_slider:
			_high_slider.max_value = max_value
		if _track:
			_track.queue_redraw()

@export var step: float = 1.0
@export var low_value: float = 0.0
@export var high_value: float = 100.0
@export var low_caption: String = ""
@export var high_caption: String = ""

## If true, thumbs are independent and may cross.
@export var independent: bool = false

var _grab: int = -1  # 0=low, 1=high, -1=none
var _track: Control
var _low_slider: HSlider
var _high_slider: HSlider
var _syncing: bool = false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	_build()
	_clamp_values()
	set_process(true)


func _process(_delta: float) -> void:
	if is_instance_valid(_low_slider):
		low_value = SliderSpinLinkScr.eval_of(_low_slider, low_value)
	if is_instance_valid(_high_slider):
		high_value = SliderSpinLinkScr.eval_of(_high_slider, high_value)
	if is_instance_valid(_track):
		_track.queue_redraw()


func _build() -> void:
	if _track != null:
		return
	if not low_caption.is_empty():
		var low_lbl := Label.new()
		low_lbl.text = low_caption
		add_child(low_lbl)
	_low_slider = _make_end_slider(low_value)
	add_child(_low_slider)
	SliderSpinLinkScr.attach_driven(_low_slider, _on_low_driven, 1.0)

	_track = Control.new()
	_track.custom_minimum_size = Vector2(120, 24)
	_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track.mouse_filter = Control.MOUSE_FILTER_STOP
	_track.draw.connect(_draw_track)
	_track.gui_input.connect(_on_track_gui_input)
	add_child(_track)

	if not high_caption.is_empty():
		var high_lbl := Label.new()
		high_lbl.text = high_caption
		add_child(high_lbl)
	_high_slider = _make_end_slider(high_value)
	add_child(_high_slider)
	SliderSpinLinkScr.attach_driven(_high_slider, _on_high_driven, 1.0)


func get_low_slider() -> HSlider:
	if _track == null:
		_build()
	return _low_slider


func get_high_slider() -> HSlider:
	if _track == null:
		_build()
	return _high_slider


func _make_end_slider(initial: float) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = min_value
	sl.max_value = max_value
	sl.step = step if step > 0.0 else 0.01
	sl.value = initial
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.tooltip_text = "Type a number or bass * 10. Pick Driver. Not clamped to the slider."
	return sl


func _on_low_driven(_v: float = 0.0) -> void:
	if _syncing:
		return
	low_value = SliderSpinLinkScr.eval_of(_low_slider, low_value)
	if _track:
		_track.queue_redraw()
	range_changed.emit(get_low(), get_high())


func _on_high_driven(_v: float = 0.0) -> void:
	if _syncing:
		return
	high_value = SliderSpinLinkScr.eval_of(_high_slider, high_value)
	if _track:
		_track.queue_redraw()
	range_changed.emit(get_low(), get_high())


func set_range_values(low: float, high: float, emit_change: bool = false) -> void:
	if _track == null:
		_build()
	_syncing = true
	if independent:
		low_value = low
		high_value = high
	else:
		var a := low
		var b := high
		if a > b:
			var t := a
			a = b
			b = t
		low_value = a
		high_value = b
	if _low_slider and not SliderSpinLinkScr.looks_driven_expr(_low_slider):
		SliderSpinLinkScr.set_expr(_low_slider, str(snappedf(low, 0.001)), false)
	if _high_slider and not SliderSpinLinkScr.looks_driven_expr(_high_slider):
		SliderSpinLinkScr.set_expr(_high_slider, str(snappedf(high, 0.001)), false)
	_syncing = false
	if _track:
		_track.queue_redraw()
	if emit_change:
		range_changed.emit(get_low(), get_high())


func reset_to_defaults(low: float, high: float) -> void:
	## Reset to default always overwrites driver expressions.
	if _track == null:
		_build()
	_syncing = true
	low_value = low
	high_value = high
	if _low_slider:
		SliderSpinLinkScr.reset_to_number(_low_slider, low, false)
	if _high_slider:
		SliderSpinLinkScr.reset_to_number(_high_slider, high, false)
	_syncing = false
	if _track:
		_track.queue_redraw()


func get_low() -> float:
	if _low_slider:
		return SliderSpinLinkScr.eval_of(_low_slider, low_value)
	return low_value


func get_high() -> float:
	if _high_slider:
		return SliderSpinLinkScr.eval_of(_high_slider, high_value)
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


func _sync_spins_from_values() -> void:
	pass


func _ratio(v: float) -> float:
	var span := max_value - min_value
	if absf(span) < 0.0001:
		return 0.0
	return clampf((v - min_value) / span, 0.0, 1.0)


func _from_ratio(r: float) -> float:
	return _snap(min_value + clampf(r, 0.0, 1.0) * (max_value - min_value))


func _x_for(v: float) -> float:
	var inner := maxf(_track.size.x - GRABBER_W, 1.0)
	return GRABBER_W * 0.5 + _ratio(v) * inner


func _value_at_x(px: float) -> float:
	var inner := maxf(_track.size.x - GRABBER_W, 1.0)
	var r := (px - GRABBER_W * 0.5) / inner
	return _from_ratio(r)


func _closest_thumb(px: float) -> int:
	var dl := absf(px - _x_for(low_value))
	var dh := absf(px - _x_for(high_value))
	return 0 if dl <= dh else 1


func _on_track_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_grab = _closest_thumb(mb.position.x)
			_set_thumb(_grab, _value_at_x(mb.position.x))
			_track.accept_event()
		else:
			_grab = -1
			_track.accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm and _grab >= 0:
		_set_thumb(_grab, _value_at_x(mm.position.x))
		_track.accept_event()


func _set_thumb(which: int, v: float) -> void:
	v = _snap(clampf(v, min_value, max_value))
	_syncing = true
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
	if which == 0 and _low_slider and not SliderSpinLinkScr.looks_driven_expr(_low_slider):
		SliderSpinLinkScr.set_expr(_low_slider, str(snappedf(low_value, 0.001)), false)
	if which == 1 and _high_slider and not SliderSpinLinkScr.looks_driven_expr(_high_slider):
		SliderSpinLinkScr.set_expr(_high_slider, str(snappedf(high_value, 0.001)), false)
	_syncing = false
	if _track:
		_track.queue_redraw()
	range_changed.emit(get_low(), get_high())


func _draw_track() -> void:
	if _track == null:
		return
	var cy := _track.size.y * 0.5
	var track := Rect2(0.0, cy - TRACK_H * 0.5, _track.size.x, TRACK_H)
	_track.draw_rect(track, Color(0.12, 0.12, 0.14, 1.0), true)
	var x0 := _x_for(low_value)
	var x1 := _x_for(high_value)
	var left := minf(x0, x1)
	var right := maxf(x0, x1)
	_track.draw_rect(Rect2(left, track.position.y, maxf(right - left, 1.0), track.size.y), Color(0.35, 0.55, 0.85, 1.0), true)
	_draw_grabber(x0, cy)
	_draw_grabber(x1, cy)


func _draw_grabber(x: float, cy: float) -> void:
	var r := Rect2(x - GRABBER_W * 0.5, cy - 9.0, GRABBER_W, 18.0)
	_track.draw_rect(r, Color(0.88, 0.9, 0.95, 1.0), true)
	_track.draw_rect(r, Color(0.2, 0.22, 0.28, 1.0), false, 1.0)
