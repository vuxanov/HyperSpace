extends VBoxContainer
class_name ScheduleSecondsPair

## Two separate Active / Inactive second sliders with live readouts.
## Replaces DualRange for schedule gates (clearer than dual thumbs).

signal range_changed(active_sec: float, inactive_sec: float)

@export var min_value: float = 1.0
@export var max_value: float = 60.0
@export var step: float = 1.0

var _active_label: Label
var _active_slider: HSlider
var _inactive_label: Label
var _inactive_slider: HSlider
var _syncing: bool = false


func _init() -> void:
	# Build immediately so set_range_values works before add_child/_ready.
	_build()


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	if _active_slider == null:
		_build()
	_refresh_labels()


func _build() -> void:
	if _active_slider != null:
		return
	_active_label = Label.new()
	add_child(_active_label)
	_active_slider = HSlider.new()
	_active_slider.min_value = min_value
	_active_slider.max_value = max_value
	_active_slider.step = step
	_active_slider.value = 4.0
	_active_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_slider.value_changed.connect(_on_active_changed)
	add_child(_active_slider)

	_inactive_label = Label.new()
	add_child(_inactive_label)
	_inactive_slider = HSlider.new()
	_inactive_slider.min_value = min_value
	_inactive_slider.max_value = max_value
	_inactive_slider.step = step
	_inactive_slider.value = 4.0
	_inactive_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inactive_slider.value_changed.connect(_on_inactive_changed)
	add_child(_inactive_slider)

	_refresh_labels()


func get_active() -> float:
	if _active_slider == null:
		return 4.0
	return float(_active_slider.value)


func get_inactive() -> float:
	if _inactive_slider == null:
		return 4.0
	return float(_inactive_slider.value)


## Compat with DualRangeSlider callers (low=active, high=inactive).
func get_low() -> float:
	return get_active()


func get_high() -> float:
	return get_inactive()


func set_range_values(active_sec: float, inactive_sec: float, emit_change: bool = false) -> void:
	if _active_slider == null:
		_build()
	_syncing = true
	_active_slider.value = clampf(snappedf(active_sec, step), min_value, max_value)
	_inactive_slider.value = clampf(snappedf(inactive_sec, step), min_value, max_value)
	_syncing = false
	_refresh_labels()
	if emit_change:
		range_changed.emit(get_active(), get_inactive())


func _on_active_changed(_v: float) -> void:
	if _syncing:
		return
	_refresh_labels()
	range_changed.emit(get_active(), get_inactive())


func _on_inactive_changed(_v: float) -> void:
	if _syncing:
		return
	_refresh_labels()
	range_changed.emit(get_active(), get_inactive())


func _refresh_labels() -> void:
	var a := int(round(get_active()))
	var i := int(round(get_inactive()))
	if _active_label:
		_active_label.text = "Active: %d sec" % a
	if _inactive_label:
		_inactive_label.text = "Inactive: %d sec" % i
