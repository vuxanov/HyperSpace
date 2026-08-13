extends VBoxContainer
class_name ScheduleSecondsPair

## Active / Inactive seconds — each end is a driver-capable row
## (slider + LineEdit + Driver dropdown). Expressions re-eval every frame.

const SliderSpinLinkScr := preload("res://ui/slider_spin_link.gd")

signal range_changed(active_sec: float, inactive_sec: float)

@export var min_value: float = 1.0
@export var max_value: float = 60.0
@export var step: float = 1.0

var _active_label: Label
var _active_slider: HSlider
var _inactive_label: Label
var _inactive_slider: HSlider
var _syncing: bool = false
var _driven_ready: bool = false


func _init() -> void:
	_build()


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	if _active_slider == null:
		_build()
	_attach_driven()
	set_process(true)
	_refresh_labels()


func _process(_delta: float) -> void:
	_refresh_labels()


func _build() -> void:
	if _active_slider != null:
		return
	_active_label = Label.new()
	add_child(_active_label)
	_active_slider = _make_slider(4.0)
	add_child(_active_slider)
	_inactive_label = Label.new()
	add_child(_inactive_label)
	_inactive_slider = _make_slider(4.0)
	add_child(_inactive_slider)
	_refresh_labels()


func _make_slider(initial: float) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = min_value
	sl.max_value = max_value
	sl.step = step
	sl.value = initial
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.tooltip_text = "Seconds. Type bass * 10 or pick Driver — not clamped to the slider."
	return sl


func _attach_driven() -> void:
	if _driven_ready:
		return
	if _active_slider == null or _active_slider.get_parent() == null:
		return
	SliderSpinLinkScr.attach_driven(_active_slider, _on_active_driven, 1.0)
	SliderSpinLinkScr.attach_driven(_inactive_slider, _on_inactive_driven, 1.0)
	_driven_ready = true


func eval_active() -> float:
	_attach_driven()
	return maxf(0.01, SliderSpinLinkScr.eval_of(_active_slider, 4.0))


func eval_inactive() -> float:
	_attach_driven()
	return maxf(0.01, SliderSpinLinkScr.eval_of(_inactive_slider, 4.0))


func get_active() -> float:
	return eval_active()


func get_inactive() -> float:
	return eval_inactive()


func get_active_param() -> Variant:
	_attach_driven()
	return SliderSpinLinkScr.param_of(_active_slider)


func get_inactive_param() -> Variant:
	_attach_driven()
	return SliderSpinLinkScr.param_of(_inactive_slider)


func active_is_expr() -> bool:
	return SliderSpinLinkScr.looks_driven_expr(_active_slider)


func inactive_is_expr() -> bool:
	return SliderSpinLinkScr.looks_driven_expr(_inactive_slider)


## Compat with DualRangeSlider callers (low=active, high=inactive).
func get_low() -> float:
	return get_active()


func get_high() -> float:
	return get_inactive()


func set_range_values(active_sec: float, inactive_sec: float, emit_change: bool = false) -> void:
	## Numbers only — do not wipe a typed expression (bass * 10).
	if _active_slider == null:
		_build()
	_attach_driven()
	_syncing = true
	if not SliderSpinLinkScr.looks_driven_expr(_active_slider):
		SliderSpinLinkScr.set_expr(_active_slider, str(snappedf(active_sec, 0.001)), false)
	if not SliderSpinLinkScr.looks_driven_expr(_inactive_slider):
		SliderSpinLinkScr.set_expr(_inactive_slider, str(snappedf(inactive_sec, 0.001)), false)
	_syncing = false
	_refresh_labels()
	if emit_change:
		range_changed.emit(eval_active(), eval_inactive())


func reset_to_defaults(active_sec: float = 4.0, inactive_sec: float = 4.0) -> void:
	## Reset to default always overwrites driver expressions.
	if _active_slider == null:
		_build()
	_attach_driven()
	_syncing = true
	SliderSpinLinkScr.reset_to_number(_active_slider, active_sec, false)
	SliderSpinLinkScr.reset_to_number(_inactive_slider, inactive_sec, false)
	_syncing = false
	_refresh_labels()


func _on_active_driven(_v: float = 0.0) -> void:
	if _syncing:
		return
	_refresh_labels()
	range_changed.emit(eval_active(), eval_inactive())


func _on_inactive_driven(_v: float = 0.0) -> void:
	if _syncing:
		return
	_refresh_labels()
	range_changed.emit(eval_active(), eval_inactive())


func _refresh_labels() -> void:
	var a := 4.0
	if is_instance_valid(_active_slider):
		a = eval_active() if _driven_ready else float(_active_slider.value)
	var i := 4.0
	if is_instance_valid(_inactive_slider):
		i = eval_inactive() if _driven_ready else float(_inactive_slider.value)
	if is_instance_valid(_active_label):
		_active_label.text = "Active: %s sec" % str(snappedf(a, 0.001))
	if is_instance_valid(_inactive_label):
		_inactive_label.text = "Inactive: %s sec" % str(snappedf(i, 0.001))
