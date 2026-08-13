extends RefCounted
class_name CycleRandom

## Shared UI for preset shuffle and influence-toggle randomization.
## Matches ASCII Style Switch: enable + fixed interval seconds (no RND interval).

const SHUFFLE_DEFAULT := 5.0
const RANDOM_DEFAULT := 1.0


static func attach_shuffle(parent: Control, after: Node, title: String = "Shuffle presets") -> Dictionary:
	var toggle := CheckButton.new()
	toggle.text = title
	toggle.tooltip_text = "Cycle this dropdown through its options on a fixed interval."
	parent.add_child(toggle)
	if after != null and is_instance_valid(after) and after.get_parent() == parent:
		parent.move_child(toggle, after.get_index() + 1)
	var body := VBoxContainer.new()
	body.visible = false
	body.add_theme_constant_override("separation", 4)
	parent.add_child(body)
	parent.move_child(body, toggle.get_index() + 1)
	var lbl := Label.new()
	lbl.text = "Interval (sec)"
	body.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0.5
	slider.max_value = 30.0
	slider.step = 0.5
	slider.value = SHUFFLE_DEFAULT
	slider.tooltip_text = "How often the dropdown advances. Type a number or pick Driver."
	body.add_child(slider)
	toggle.toggled.connect(func(on: bool) -> void: body.visible = on)
	return {"toggle": toggle, "body": body, "interval": slider, "timer": 0.0}


static func attach_random(parent: Control, after: Node, share_interval: HSlider = null) -> Dictionary:
	var toggle := CheckButton.new()
	toggle.text = "Random"
	toggle.tooltip_text = "Randomly check and uncheck these influence targets over time."
	parent.add_child(toggle)
	if after != null and is_instance_valid(after) and after.get_parent() == parent:
		parent.move_child(toggle, after.get_index() + 1)
	var slider: HSlider = share_interval
	var body: VBoxContainer = null
	if share_interval == null:
		body = VBoxContainer.new()
		body.visible = false
		body.add_theme_constant_override("separation", 4)
		parent.add_child(body)
		parent.move_child(body, toggle.get_index() + 1)
		var lbl := Label.new()
		lbl.text = "Interval (sec)"
		body.add_child(lbl)
		slider = HSlider.new()
		slider.min_value = 0.5
		slider.max_value = 5.0
		slider.step = 0.1
		slider.value = RANDOM_DEFAULT
		slider.tooltip_text = "How often influence targets reshuffle. Type a number or pick Driver."
		body.add_child(slider)
		toggle.toggled.connect(func(on: bool) -> void: body.visible = on)
	return {"toggle": toggle, "body": body, "interval": slider, "timer": 0.0}


static func interval_of(slot: Dictionary, fallback: float = 1.0) -> float:
	var slider: Variant = slot.get("interval")
	if slider is HSlider and is_instance_valid(slider):
		return maxf(0.5, float((slider as HSlider).value))
	return maxf(0.5, fallback)


static func tick_slot(slot: Dictionary, delta: float) -> bool:
	if slot.is_empty():
		return false
	var toggle: Variant = slot.get("toggle")
	if not (toggle is CheckButton) or not (toggle as CheckButton).button_pressed:
		slot["timer"] = 0.0
		return false
	var t := float(slot.get("timer", 0.0)) + maxf(delta, 0.0)
	var interval := interval_of(slot, 1.0)
	if t >= interval:
		slot["timer"] = fmod(t, interval)
		return true
	slot["timer"] = t
	return false


static func advance_option(opt: OptionButton, skip_indices: PackedInt32Array = PackedInt32Array()) -> int:
	if opt == null or not is_instance_valid(opt) or opt.item_count <= 1:
		return -1
	var start := opt.selected
	if start < 0:
		start = 0
	var next := (start + 1) % opt.item_count
	var guard := 0
	while skip_indices.has(next) and guard < opt.item_count:
		next = (next + 1) % opt.item_count
		guard += 1
	if next == start:
		return -1
	opt.select(next)
	opt.item_selected.emit(next)
	return next


static func randomize_checks(buttons: Array, keep_one: bool = true) -> void:
	var live: Array[CheckButton] = []
	for b in buttons:
		if b is CheckButton and is_instance_valid(b) and (b as CheckButton).visible:
			live.append(b as CheckButton)
	if live.is_empty():
		return
	var on_count := 0
	for btn in live:
		var on := randf() >= 0.5
		if btn.button_pressed != on:
			btn.button_pressed = on
		if btn.button_pressed:
			on_count += 1
	if keep_one and on_count == 0:
		live[randi() % live.size()].button_pressed = true


static func reset_slot(slot: Dictionary) -> void:
	if slot.is_empty():
		return
	var toggle: Variant = slot.get("toggle")
	if toggle is CheckButton:
		(toggle as CheckButton).set_pressed_no_signal(false)
	var body: Variant = slot.get("body")
	if body is CanvasItem:
		(body as CanvasItem).visible = false
	var slider: Variant = slot.get("interval")
	if slider is HSlider:
		(slider as HSlider).value = SHUFFLE_DEFAULT if float((slider as HSlider).max_value) > 10.0 else RANDOM_DEFAULT
	slot["timer"] = 0.0
