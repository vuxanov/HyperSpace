extends RefCounted
class_name SliderSpinLink

const _Expr := preload("res://core/driver_expr.gd")

## Pair an HSlider with a numeric SpinBox beside it.
## - Slider keeps a practical drag range.
## - SpinBox accepts free typed decimals (fine step); arrow buttons step whole numbers.
## - allow_greater / allow_lesser so typed values are not hard-clamped to the slider.

const SPIN_WIDTH := 92.0
const DRIVEN_EDIT_WIDTH := 80.0
const DRIVER_OPTION_WIDTH := 100.0
const FALLBACK_PICKER := [
	"time", "volume", "energy", "peak", "bass",
	"mids", "highs", "kick", "beat",
	"lfo1", "lfo2", "noise", "rand", "band0",
]
const EDIT_STEP := 0.001
const ARROW_STEP := 1.0
const FREE_MIN := -1000000.0
const FREE_MAX := 1000000.0

static var _busy: Dictionary = {}  # instance_id -> bool
static var _driven: Dictionary = {}  # instance_id -> HSlider
static var _driven_choices: Dictionary = {}  # instance_id -> OptionButton
static var add_new_handler: Callable


static func configure_spin(spin: SpinBox, edit_step: float = EDIT_STEP, widen: bool = true) -> void:
	## Configure a standalone SpinBox (no slider) with whole-number arrows + free decimals.
	spin.step = _nice_edit_step(edit_step)
	spin.custom_arrow_step = ARROW_STEP
	spin.allow_greater = true
	spin.allow_lesser = true
	if widen:
		spin.max_value = FREE_MAX
		# Preserve intentional non-negative floors (e.g. fly speed / scale ≥ 0).
		if spin.min_value > 0.0:
			spin.min_value = 0.0
		elif spin.min_value < 0.0:
			spin.min_value = FREE_MIN


static func attach(slider: HSlider, spin_width: float = SPIN_WIDTH) -> SpinBox:
	## Reparent slider into an HBox with a sibling SpinBox. Returns the SpinBox.
	if slider == null or not is_instance_valid(slider):
		return null
	if slider.has_meta("slider_spin_link"):
		return _as_spin(slider.get_meta("slider_spin_link"))

	var parent := slider.get_parent()
	if parent == null:
		return null
	var idx := slider.get_index()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	parent.move_child(row, idx)
	slider.reparent(row)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var spin := SpinBox.new()
	spin.custom_minimum_size = Vector2(spin_width, 0)
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	spin.min_value = FREE_MIN
	spin.max_value = FREE_MAX
	spin.step = _nice_edit_step(slider.step)
	spin.custom_arrow_step = ARROW_STEP
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.value = slider.value
	spin.tooltip_text = "Type a value (decimals ok). Arrows change by 1."
	row.add_child(spin)

	slider.set_meta("slider_spin_link", spin)
	slider.set_meta("linked_value", slider.value)
	_busy[slider.get_instance_id()] = false

	slider.value_changed.connect(func(v: float) -> void:
		if _is_busy(slider):
			return
		_set_busy(slider, true)
		spin.set_value_no_signal(v)
		slider.set_meta("linked_value", v)
		_set_busy(slider, false)
	)
	spin.value_changed.connect(func(v: float) -> void:
		if _is_busy(slider):
			return
		_set_busy(slider, true)
		slider.set_meta("linked_value", v)
		slider.set_value_no_signal(clampf(v, slider.min_value, slider.max_value))
		# Deliver the free typed value (may be outside the slider's visual range).
		slider.value_changed.emit(v)
		_set_busy(slider, false)
	)
	return spin


static func attach_many(sliders: Array) -> void:
	for s in sliders:
		var sl := _as_slider(s)
		if sl:
			attach(sl)


static func value_of(slider: HSlider) -> float:
	if not _live(slider):
		return 0.0
	if slider.has_meta("linked_value"):
		return float(slider.get_meta("linked_value"))
	return float(slider.value)


static func set_row_visible(slider: HSlider, vis: bool) -> void:
	## Hide/show the wrap (slider + LineEdit + Driver), not just the thumb.
	if not _live(slider):
		return
	var wrap: Variant = _meta_live(slider, "driven_wrap")
	if wrap is CanvasItem:
		(wrap as CanvasItem).visible = vis
		return
	if slider.has_meta("slider_spin_link") or slider.has_meta("driven_edit"):
		var row := slider.get_parent()
		if _live(row) and (row is HBoxContainer or row is VBoxContainer):
			(row as CanvasItem).visible = vis
			return
	slider.visible = vis


static func set_value(slider: HSlider, value: float, emit_change: bool = false) -> void:
	if not _live(slider):
		return
	_set_busy(slider, true)
	slider.set_meta("linked_value", value)
	if emit_change:
		slider.value = clampf(value, slider.min_value, slider.max_value)
		if not is_equal_approx(slider.value, value):
			slider.value_changed.emit(value)
	else:
		slider.set_value_no_signal(clampf(value, slider.min_value, slider.max_value))
	var spin := _as_spin(_meta_live(slider, "slider_spin_link"))
	if spin:
		spin.set_value_no_signal(value)
	_set_busy(slider, false)


static func _nice_edit_step(slider_step: float) -> float:
	if slider_step <= 0.0:
		return EDIT_STEP
	# Fine enough to type decimals; never coarser than the slider step when step < 1.
	if slider_step >= 1.0:
		return EDIT_STEP
	return minf(slider_step, EDIT_STEP) if slider_step < EDIT_STEP else slider_step


static func _is_busy(node: Object) -> bool:
	if not _live(node):
		return true
	return bool(_busy.get(node.get_instance_id(), false))


static func _set_busy(node: Object, busy: bool) -> void:
	if not _live(node):
		return
	_busy[node.get_instance_id()] = busy


static func _live(raw: Variant) -> bool:
	## True only for a still-alive Object. Do not `as Type` before this.
	return raw != null and is_instance_valid(raw)


static func _as_slider(raw: Variant) -> HSlider:
	if not _live(raw):
		return null
	return raw as HSlider


static func _as_edit(raw: Variant) -> LineEdit:
	if not _live(raw):
		return null
	return raw as LineEdit


static func _as_opt(raw: Variant) -> OptionButton:
	if not _live(raw):
		return null
	return raw as OptionButton


static func _as_spin(raw: Variant) -> SpinBox:
	if not _live(raw):
		return null
	return raw as SpinBox


static func _meta_live(node: Object, key: String) -> Variant:
	if not _live(node) or not node.has_meta(key):
		return null
	var raw: Variant = node.get_meta(key)
	if not _live(raw):
		return null
	return raw


static func unregister_driven(id: int) -> void:
	_driven.erase(id)
	_driven_choices.erase(id)
	_busy.erase(id)


static func _on_driven_exiting(id: int) -> void:
	unregister_driven(id)


static func attach_driven(slider: HSlider, on_change: Callable = Callable(), divisor: float = 1.0) -> LineEdit:
	## Two-row wrap: slider on top, LineEdit + visible Driver dropdown below.
	## LineEdit accepts type/paste (bass, -bass, bass * 10). Picking Driver writes the name.
	if slider == null or not is_instance_valid(slider):
		return null
	if slider.has_meta("driven_edit"):
		var sid := slider.get_instance_id()
		_driven[sid] = slider
		if not slider.has_meta("driven_exit_hook"):
			slider.tree_exiting.connect(_on_driven_exiting.bind(sid))
			slider.set_meta("driven_exit_hook", true)
		return _as_edit(slider.get_meta("driven_edit"))
	var host := slider.get_parent()
	if host == null:
		return null
	var insert_at := slider.get_index()
	var wrap_host: Node = host
	var old_hbox: HBoxContainer = null
	if host is HBoxContainer and slider.has_meta("slider_spin_link"):
		old_hbox = host as HBoxContainer
		wrap_host = host.get_parent()
		if wrap_host == null:
			return null
		insert_at = host.get_index()
		var spin := _as_spin(_meta_live(slider, "slider_spin_link"))
		if spin:
			spin.visible = false
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.clip_contents = false
	wrap.set_meta("is_driven_wrap", true)
	wrap_host.add_child(wrap)
	wrap_host.move_child(wrap, insert_at)
	slider.reparent(wrap)
	slider.custom_minimum_size = Vector2(40, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if old_hbox != null and is_instance_valid(old_hbox):
		old_hbox.queue_free()
	var edit_row := HBoxContainer.new()
	edit_row.add_theme_constant_override("separation", 6)
	edit_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(edit_row)
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(DRIVEN_EDIT_WIDTH, 28)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.placeholder_text = "bass * 10"
	edit.caret_blink = true
	edit.editable = true
	edit.context_menu_enabled = true
	edit.shortcut_keys_enabled = true
	edit.select_all_on_focus = true
	edit.tooltip_text = "Type or paste a number, a driver (bass, volume), or math: -bass, bass * 10, volume + 1. Ctrl+V works."
	var txt := _fmt_num(slider.value)
	edit.text = txt
	edit_row.add_child(edit)
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(DRIVER_OPTION_WIDTH, 28)
	opt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	opt.size_flags_horizontal = Control.SIZE_SHRINK_END
	opt.clip_text = false
	opt.fit_to_longest_item = false
	opt.tooltip_text = "Insert a driver name into this field"
	edit_row.add_child(opt)
	slider.set_meta("driven_edit", edit)
	slider.set_meta("driven_option", opt)
	slider.set_meta("driven_wrap", wrap)
	slider.set_meta("driven_expr", txt)
	slider.set_meta("driven_div", divisor if divisor > 0.0 else 1.0)
	slider.set_meta("driven_change", on_change)
	slider.set_meta("linked_value", slider.value)
	_driven[slider.get_instance_id()] = slider
	_busy[slider.get_instance_id()] = false
	var sid := slider.get_instance_id()
	if not slider.has_meta("driven_exit_hook"):
		slider.tree_exiting.connect(_on_driven_exiting.bind(sid))
		slider.set_meta("driven_exit_hook", true)
	_fill_driven_option(slider)
	if not slider.value_changed.is_connected(_on_driven_slider):
		slider.value_changed.connect(_on_driven_slider.bind(slider))
	edit.text_submitted.connect(func(s: String) -> void: _commit_driven_edit(slider, s))
	edit.focus_exited.connect(func() -> void: _commit_driven_edit(slider, edit.text))
	edit.text_changed.connect(func(s: String) -> void: _on_driven_text_changed(slider, s))
	opt.item_selected.connect(func(idx: int) -> void: _on_driven_option(slider, idx))
	var popup := opt.get_popup()
	if popup and not popup.about_to_popup.is_connected(_on_driven_about_to_popup.bind(slider)):
		popup.about_to_popup.connect(_on_driven_about_to_popup.bind(slider))
	return edit


static func attach_driven_choice(opt: OptionButton, on_change: Callable = Callable()) -> LineEdit:
	## Discrete picker + LineEdit + Driver. Expression maps to item index (wraps).
	if opt == null or not is_instance_valid(opt):
		return null
	if opt.has_meta("driven_edit"):
		var oid := opt.get_instance_id()
		_driven_choices[oid] = opt
		if not opt.has_meta("driven_exit_hook"):
			opt.tree_exiting.connect(_on_driven_exiting.bind(oid))
			opt.set_meta("driven_exit_hook", true)
		return _as_edit(opt.get_meta("driven_edit"))
	var host := opt.get_parent()
	if host == null:
		return null
	var insert_at := opt.get_index()
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.clip_contents = false
	wrap.set_meta("is_driven_wrap", true)
	host.add_child(wrap)
	host.move_child(wrap, insert_at)
	opt.reparent(wrap)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var edit_row := HBoxContainer.new()
	edit_row.add_theme_constant_override("separation", 6)
	edit_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(edit_row)
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(DRIVEN_EDIT_WIDTH, 28)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.placeholder_text = "lfo1 * 15"
	edit.caret_blink = true
	edit.editable = true
	edit.context_menu_enabled = true
	edit.shortcut_keys_enabled = true
	edit.select_all_on_focus = true
	edit.tooltip_text = "Driver or math → style index (wraps). Examples: time, lfo1 * 15, bass * 10. Or pick a style above."
	var sel := opt.selected
	if sel < 0:
		sel = 0
	var txt := str(sel)
	edit.text = txt
	edit_row.add_child(edit)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(DRIVER_OPTION_WIDTH, 28)
	picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picker.size_flags_horizontal = Control.SIZE_SHRINK_END
	picker.clip_text = false
	picker.fit_to_longest_item = false
	picker.tooltip_text = "Insert a driver name into this field"
	edit_row.add_child(picker)
	opt.set_meta("driven_edit", edit)
	opt.set_meta("driven_option", picker)
	opt.set_meta("driven_wrap", wrap)
	opt.set_meta("driven_expr", txt)
	opt.set_meta("driven_change", on_change)
	_driven_choices[opt.get_instance_id()] = opt
	_busy[opt.get_instance_id()] = false
	var oid := opt.get_instance_id()
	if not opt.has_meta("driven_exit_hook"):
		opt.tree_exiting.connect(_on_driven_exiting.bind(oid))
		opt.set_meta("driven_exit_hook", true)
	_fill_choice_picker(opt)
	if not opt.item_selected.is_connected(_on_choice_item):
		opt.item_selected.connect(_on_choice_item.bind(opt))
	edit.text_submitted.connect(func(s: String) -> void: _commit_choice_edit(opt, s))
	edit.focus_exited.connect(func() -> void: _commit_choice_edit(opt, edit.text))
	edit.text_changed.connect(func(s: String) -> void: _on_choice_text_changed(opt, s))
	picker.item_selected.connect(func(idx: int) -> void: _on_choice_driver_picked(opt, idx))
	var popup := picker.get_popup()
	if popup and not popup.about_to_popup.is_connected(_on_choice_about_to_popup.bind(opt)):
		popup.about_to_popup.connect(_on_choice_about_to_popup.bind(opt))
	return edit


static func choice_expr_of(opt: OptionButton) -> String:
	if not _live(opt):
		return "0"
	if opt.has_meta("driven_expr"):
		return str(opt.get_meta("driven_expr"))
	var sel := opt.selected
	return str(sel if sel >= 0 else 0)


static func choice_param(opt: OptionButton) -> Variant:
	var e := choice_expr_of(opt).strip_edges()
	if e.is_empty():
		return float(opt.selected if opt.selected >= 0 else 0)
	if _Expr.is_plain_number(e):
		return e.to_float()
	return e


static func choice_is_expr(opt: OptionButton) -> bool:
	if not _live(opt):
		return false
	return _Expr.looks_like_expr(choice_expr_of(opt))


static func set_choice_expr(opt: OptionButton, expr: String, emit_change: bool = true) -> void:
	if not _live(opt):
		return
	var e := expr.strip_edges()
	if e.is_empty():
		e = str(opt.selected if opt.selected >= 0 else 0)
	opt.set_meta("driven_expr", e)
	var edit := _as_edit(_meta_live(opt, "driven_edit"))
	if edit and edit.text != e:
		edit.text = e
	if _Expr.is_plain_number(e):
		var idx := _choice_index_from_value(e.to_float(), opt.item_count)
		_set_busy(opt, true)
		opt.set_block_signals(true)
		opt.select(idx)
		opt.set_block_signals(false)
		_set_busy(opt, false)
	if emit_change:
		_emit_choice(opt)


static func reset_choice_to_index(opt: OptionButton, idx: int, emit_change: bool = false) -> void:
	if not _live(opt):
		return
	var n := opt.item_count
	var i := 0 if n <= 0 else clampi(idx, 0, n - 1)
	set_choice_expr(opt, str(i), emit_change)
	var picker := _as_opt(_meta_live(opt, "driven_option"))
	if picker:
		picker.set_block_signals(true)
		picker.select(0)
		picker.set_block_signals(false)


static func _choice_index_from_value(v: float, count: int) -> int:
	if count <= 0:
		return 0
	return posmod(int(floor(v)), count)


static func _emit_choice(opt: OptionButton) -> void:
	if not _live(opt):
		return
	var cb: Variant = opt.get_meta("driven_change") if opt.has_meta("driven_change") else null
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call()


static func _commit_choice_edit(opt: OptionButton, text: String) -> void:
	if opt == null or _is_busy(opt):
		return
	set_choice_expr(opt, text, true)


static func _on_choice_text_changed(opt: OptionButton, text: String) -> void:
	if opt == null or _is_busy(opt):
		return
	var e := text.strip_edges()
	if e.is_empty():
		return
	opt.set_meta("driven_expr", e)
	if _Expr.is_plain_number(e):
		var idx := _choice_index_from_value(e.to_float(), opt.item_count)
		_set_busy(opt, true)
		opt.set_block_signals(true)
		opt.select(idx)
		opt.set_block_signals(false)
		_set_busy(opt, false)
	_emit_choice(opt)


static func _on_choice_item(idx: int, opt: OptionButton) -> void:
	if not _live(opt) or _is_busy(opt):
		return
	set_choice_expr(opt, str(idx), true)


static func _on_choice_about_to_popup(opt: OptionButton) -> void:
	_fill_choice_picker(opt)


static func _fill_choice_picker(opt: OptionButton) -> void:
	if not _live(opt):
		return
	var picker := _as_opt(_meta_live(opt, "driven_option"))
	if picker == null:
		return
	picker.set_block_signals(true)
	picker.clear()
	picker.add_item("Driver")
	var names: PackedStringArray = _picker_names()
	for n in names:
		picker.add_item(n)
	picker.add_item("Add new…")
	picker.select(0)
	picker.set_block_signals(false)


static func _on_choice_driver_picked(opt: OptionButton, idx: int) -> void:
	if not _live(opt) or idx <= 0:
		return
	var picker := _as_opt(_meta_live(opt, "driven_option"))
	if picker == null:
		return
	var txt := picker.get_item_text(idx).strip_edges()
	picker.set_block_signals(true)
	picker.select(0)
	picker.set_block_signals(false)
	if txt.is_empty() or txt == "Driver":
		return
	if txt == "Add new…":
		if add_new_handler.is_valid():
			add_new_handler.call(opt)
		return
	set_choice_expr(opt, txt, true)


static func expr_of(slider: HSlider) -> String:
	if not _live(slider):
		return "0"
	if slider.has_meta("driven_expr"):
		return str(slider.get_meta("driven_expr"))
	return _fmt_num(value_of(slider))


static func param_of(slider: HSlider) -> Variant:
	var e := expr_of(slider).strip_edges()
	if e.is_empty():
		return value_of(slider)
	if _Expr.is_plain_number(e):
		return value_of(slider)
	return e


static func mapped_param(slider: HSlider, divisor: float) -> Variant:
	var raw: Variant = param_of(slider)
	if raw is String:
		return raw
	var d := divisor if divisor > 0.0 else 1.0
	return float(raw) / d


static func set_expr(slider: HSlider, expr: String, emit_change: bool = true) -> void:
	if not _live(slider):
		return
	var e := expr.strip_edges()
	if e.is_empty():
		e = _fmt_num(slider.value)
	slider.set_meta("driven_expr", e)
	var edit := _as_edit(_meta_live(slider, "driven_edit"))
	if edit and edit.text != e:
		edit.text = e
	var is_num: bool = _Expr.is_plain_number(e)
	slider.editable = is_num
	if is_num:
		_set_busy(slider, true)
		var v := e.to_float()
		slider.set_meta("linked_value", v)
		slider.set_value_no_signal(clampf(v, slider.min_value, slider.max_value))
		_set_busy(slider, false)
	if emit_change:
		_emit_driven(slider)


static func reset_to_number(slider: HSlider, v: float, emit_change: bool = false) -> void:
	## Factory reset for a driven row: number in the LineEdit, Driver menu on "Driver".
	if not _live(slider):
		return
	set_expr(slider, _fmt_num(v), emit_change)
	var opt := _as_opt(_meta_live(slider, "driven_option"))
	if opt:
		opt.set_block_signals(true)
		opt.select(0)
		opt.set_block_signals(false)


static func set_mapped_param(slider: HSlider, raw: Variant, divisor: float, emit_change: bool = false) -> void:
	if slider == null:
		return
	var d := divisor if divisor > 0.0 else 1.0
	if raw is String and _Expr.looks_like_expr(str(raw)):
		set_expr(slider, str(raw), emit_change)
		return
	var v := 0.0
	if raw is String and _Expr.is_plain_number(str(raw)):
		v = str(raw).to_float() * d
	else:
		v = float(raw) * d
	set_expr(slider, _fmt_num(v), emit_change)


static func refresh_all_previews() -> void:
	var hub := _hub()
	if hub == null:
		return
	var dead: Array = []
	for id_any in _driven.keys():
		var raw: Variant = _driven[id_any]
		if raw == null or not is_instance_valid(raw):
			dead.append(id_any)
			continue
		var slider := raw as HSlider
		if slider == null:
			dead.append(id_any)
			continue
		var e := expr_of(slider).strip_edges()
		if not _Expr.looks_like_expr(e):
			continue
		var ev := float(hub.call("eval_expr", e))
		var div := float(slider.get_meta("driven_div")) if slider.has_meta("driven_div") else 1.0
		if div <= 0.0:
			div = 1.0
		var shown := ev * div
		_set_busy(slider, true)
		# Thumb is visual-only; linked_value keeps the unclamped expression result.
		slider.set_value_no_signal(clampf(shown, slider.min_value, slider.max_value))
		slider.set_meta("linked_value", shown)
		_set_busy(slider, false)
	for d in dead:
		unregister_driven(int(d))
	_refresh_choice_previews()


static func _refresh_choice_previews() -> void:
	var hub := _hub()
	if hub == null:
		return
	var dead: Array = []
	for id_any in _driven_choices.keys():
		var raw: Variant = _driven_choices[id_any]
		if raw == null or not is_instance_valid(raw):
			dead.append(id_any)
			continue
		var opt := raw as OptionButton
		if opt == null:
			dead.append(id_any)
			continue
		var e := choice_expr_of(opt).strip_edges()
		if not _Expr.looks_like_expr(e):
			continue
		var ev := float(hub.call("eval_expr", e))
		var idx := _choice_index_from_value(ev, opt.item_count)
		if opt.selected == idx:
			continue
		_set_busy(opt, true)
		opt.set_block_signals(true)
		opt.select(idx)
		opt.set_block_signals(false)
		_set_busy(opt, false)
	for d in dead:
		unregister_driven(int(d))


static func _on_driven_slider(v: float, slider: HSlider) -> void:
	if not _live(slider) or _is_busy(slider):
		return
	if _Expr.looks_like_expr(expr_of(slider)):
		return
	_set_busy(slider, true)
	slider.set_meta("linked_value", v)
	slider.set_meta("driven_expr", _fmt_num(v))
	var edit := _as_edit(_meta_live(slider, "driven_edit"))
	if edit:
		edit.text = _fmt_num(v)
	_emit_driven(slider)
	_set_busy(slider, false)


static func _commit_driven_edit(slider: HSlider, text: String) -> void:
	if slider == null or _is_busy(slider):
		return
	set_expr(slider, text, true)


static func _on_driven_text_changed(slider: HSlider, text: String) -> void:
	## Paste / typing should apply without requiring Enter. Do not rewrite the LineEdit (cursor).
	if slider == null or _is_busy(slider):
		return
	var e := text.strip_edges()
	if e.is_empty():
		return
	slider.set_meta("driven_expr", e)
	var is_num: bool = _Expr.is_plain_number(e)
	slider.editable = is_num
	if is_num:
		_set_busy(slider, true)
		var v := e.to_float()
		slider.set_meta("linked_value", v)
		slider.set_value_no_signal(clampf(v, slider.min_value, slider.max_value))
		_set_busy(slider, false)
	_emit_driven(slider)


static func _emit_driven(slider: HSlider) -> void:
	if not _live(slider):
		return
	var cb: Variant = slider.get_meta("driven_change") if slider.has_meta("driven_change") else null
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call()
	else:
		slider.value_changed.emit(value_of(slider))


static func _picker_names() -> PackedStringArray:
	var hub := _hub()
	if hub != null and hub.has_method("picker_names"):
		var n: Variant = hub.call("picker_names")
		if n is PackedStringArray and (n as PackedStringArray).size() > 0:
			return n as PackedStringArray
	var out := PackedStringArray()
	for s in FALLBACK_PICKER:
		out.append(str(s))
	return out


static func _on_driven_about_to_popup(slider: HSlider) -> void:
	_fill_driven_option(slider)


static func _fill_driven_option(slider: HSlider) -> void:
	if not _live(slider):
		return
	var opt := _as_opt(_meta_live(slider, "driven_option"))
	if opt == null:
		return
	opt.set_block_signals(true)
	opt.clear()
	opt.add_item("Driver")
	var names: PackedStringArray = _picker_names()
	for n in names:
		opt.add_item(n)
	opt.add_item("Add new…")
	opt.select(0)
	opt.set_block_signals(false)


static func _on_driven_option(slider: HSlider, idx: int) -> void:
	if not _live(slider) or idx <= 0:
		return
	var opt := _as_opt(_meta_live(slider, "driven_option"))
	if opt == null:
		return
	var txt := opt.get_item_text(idx).strip_edges()
	opt.set_block_signals(true)
	opt.select(0)
	opt.set_block_signals(false)
	if txt.is_empty() or txt == "Driver":
		return
	if txt == "Add new…":
		if add_new_handler.is_valid():
			add_new_handler.call(slider)
		return
	set_expr(slider, txt, true)


static func _hub() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("DriverHub")


static func eval_of(slider: HSlider, fallback: float = 0.0) -> float:
	## Live number: expressions go through DriverHub; plain numbers use linked_value.
	if slider == null or not is_instance_valid(slider):
		return fallback
	var hub := _hub()
	var raw: Variant = param_of(slider)
	if hub != null and hub.has_method("eval_value"):
		return float(hub.call("eval_value", raw, value_of(slider)))
	if raw is float or raw is int:
		return float(raw)
	return value_of(slider)


static func replace_spin_with_driven(
		spin: SpinBox,
		on_change: Callable = Callable(),
		divisor: float = 1.0,
		vis_min: float = 0.0,
		vis_max: float = 100.0
	) -> HSlider:
	## Hide a .tscn SpinBox and put the shared slider + LineEdit + Driver row in its place.
	if spin == null or not is_instance_valid(spin):
		return null
	if spin.has_meta("driven_slider"):
		return _as_slider(spin.get_meta("driven_slider"))
	var host := spin.get_parent()
	if host == null:
		return null
	var sl := HSlider.new()
	sl.min_value = vis_min
	sl.max_value = maxf(vis_max, vis_min + 0.001)
	sl.step = spin.step if spin.step > 0.0 else 0.01
	sl.value = spin.value
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.tooltip_text = spin.tooltip_text
	var idx := spin.get_index()
	host.add_child(sl)
	host.move_child(sl, idx)
	spin.visible = false
	attach_driven(sl, on_change, divisor)
	spin.set_meta("driven_slider", sl)
	return sl


static func slider_of_spin(spin: SpinBox) -> HSlider:
	if not _live(spin) or not spin.has_meta("driven_slider"):
		return null
	return _as_slider(spin.get_meta("driven_slider"))


static func eval_spin(spin: SpinBox, fallback: float = 0.0) -> float:
	var sl := slider_of_spin(spin)
	if sl:
		return eval_of(sl, fallback)
	if spin == null:
		return fallback
	return float(spin.value)


static func param_of_spin(spin: SpinBox) -> Variant:
	var sl := slider_of_spin(spin)
	if sl:
		return param_of(sl)
	if spin == null:
		return 0.0
	return float(spin.value)


static func set_spin_driven(spin: SpinBox, raw: Variant, emit_change: bool = false) -> void:
	var sl := slider_of_spin(spin)
	if sl:
		if looks_driven_expr(sl) and not (raw is String and _Expr.looks_like_expr(str(raw))):
			return
		set_mapped_param(sl, raw, 1.0, emit_change)
		return
	if spin == null:
		return
	if raw is String and _Expr.looks_like_expr(str(raw)):
		return
	spin.set_value_no_signal(float(raw) if raw != null else 0.0)


static func looks_driven_expr(slider: HSlider) -> bool:
	if not _live(slider):
		return false
	return _Expr.looks_like_expr(expr_of(slider))


static func _fmt_num(v: float) -> String:
	if is_equal_approx(v, snappedf(v, 1.0)):
		return "%d" % int(round(v))
	var s := "%.3f" % v
	while s.ends_with("0") and s.contains("."):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s
