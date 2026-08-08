extends PanelContainer

## Right sidebar — effects, ASCII presets, audio reactivity routing.

const RH = preload("res://core/reactivity_hub.gd")


@onready var reactivity_toggle: CheckButton = $Margin/Column/AudioSection/ReactivityToggle
@onready var intensity_slider: HSlider = $Margin/Column/AudioSection/IntensitySlider
@onready var sensitivity_slider: HSlider = $Margin/Column/AudioSection/SensitivitySlider
@onready var scale_amount_spin: SpinBox = $Margin/Column/AudioSection/ScaleAmountSpin
@onready var energy_bar: ProgressBar = $Margin/Column/AudioSection/EnergyBar
@onready var bass_bar: ProgressBar = $Margin/Column/AudioSection/BassBar

@onready var affect_scale: CheckButton = $Margin/Column/Targets/AffectScale
@onready var scale_x: CheckButton = $Margin/Column/Targets/AxisRow/ScaleX
@onready var scale_y: CheckButton = $Margin/Column/Targets/AxisRow/ScaleY
@onready var scale_z: CheckButton = $Margin/Column/Targets/AxisRow/ScaleZ
@onready var affect_light: CheckButton = $Margin/Column/Targets/AffectLight
@onready var affect_emission: CheckButton = $Margin/Column/Targets/AffectEmission
@onready var affect_rotation: CheckButton = $Margin/Column/Targets/AffectRotation
@onready var target_option: OptionButton = $Margin/Column/Targets/TargetOption

@onready var ascii_toggle: CheckButton = $Margin/Column/FxSection/AsciiToggle
@onready var ascii_preset: OptionButton = $Margin/Column/FxSection/AsciiPreset
@onready var ascii_density_slider: HSlider = $Margin/Column/FxSection/AsciiDensitySlider
@onready var particles_toggle: CheckButton = $Margin/Column/FxSection/ParticlesToggle
@onready var feedback_toggle: CheckButton = $Margin/Column/FxSection/FeedbackToggle
@onready var cue_container: HFlowContainer = $Margin/Column/CueSection/CueContainer


func _ready() -> void:
	for preset_name in AsciiEffect.PRESETS.keys():
		ascii_preset.add_item(str(preset_name))
	target_option.clear()
	target_option.add_item("Centerpiece", 0)
	target_option.add_item("Scatter", 1)
	target_option.add_item("Environment", 2)
	target_option.add_item("Everything", 3)
	reactivity_toggle.button_pressed = bool(RH.get_field("enabled", true))
	affect_scale.button_pressed = bool(RH.get_field("affect_scale", true))
	scale_x.button_pressed = bool(RH.get_field("scale_x", true))
	scale_y.button_pressed = bool(RH.get_field("scale_y", true))
	scale_z.button_pressed = bool(RH.get_field("scale_z", true))
	affect_light.button_pressed = bool(RH.get_field("affect_light", true))
	affect_emission.button_pressed = bool(RH.get_field("affect_emission", true))
	affect_rotation.button_pressed = bool(RH.get_field("affect_rotation", true))
	scale_amount_spin.value = RH.scale_amount()
	_select_target_option(RH.target())
	reactivity_toggle.toggled.connect(_on_reactivity_toggled)
	intensity_slider.value_changed.connect(func(v: float) -> void: AudioAnalyzer.master_intensity = v)
	sensitivity_slider.value_changed.connect(func(v: float) -> void: AudioAnalyzer.band_sensitivity = v)
	scale_amount_spin.value_changed.connect(_on_scale_amount)
	affect_scale.toggled.connect(_on_affect_scale)
	scale_x.toggled.connect(func(v: bool) -> void: RH.set_field("scale_x", v))
	scale_y.toggled.connect(func(v: bool) -> void: RH.set_field("scale_y", v))
	scale_z.toggled.connect(func(v: bool) -> void: RH.set_field("scale_z", v))
	affect_light.toggled.connect(func(v: bool) -> void: RH.set_field("affect_light", v))
	affect_emission.toggled.connect(func(v: bool) -> void: RH.set_field("affect_emission", v))
	affect_rotation.toggled.connect(func(v: bool) -> void: RH.set_field("affect_rotation", v))
	target_option.item_selected.connect(_on_target_selected)
	ascii_toggle.toggled.connect(_on_ascii_toggled)
	ascii_preset.item_selected.connect(_on_ascii_preset)
	ascii_density_slider.value_changed.connect(_on_ascii_density)
	particles_toggle.toggled.connect(_on_particles_toggled)
	feedback_toggle.toggled.connect(_on_feedback_toggled)
	ShowDirector.show_loaded.connect(func(_n: String) -> void: _rebuild_cues())
	AudioAnalyzer.state_updated.connect(_on_audio)
	_rebuild_cues()
	_sync_target_controls()


func _on_audio(state: AudioState) -> void:
	energy_bar.value = clampf(state.energy, 0.0, 1.0)
	bass_bar.value = clampf(state.bass, 0.0, 1.0)


func _on_reactivity_toggled(enabled: bool) -> void:
	RH.set_enabled(enabled)
	_sync_target_controls()


func _sync_target_controls() -> void:
	var on := RH.enabled()
	affect_scale.disabled = not on
	scale_x.disabled = not on
	scale_y.disabled = not on
	scale_z.disabled = not on
	affect_light.disabled = not on
	affect_emission.disabled = not on
	affect_rotation.disabled = not on
	target_option.disabled = not on
	scale_amount_spin.editable = on


func _on_affect_scale(enabled: bool) -> void:
	RH.set_field("affect_scale", enabled)
	scale_x.disabled = not (RH.enabled() and enabled)
	scale_y.disabled = not (RH.enabled() and enabled)
	scale_z.disabled = not (RH.enabled() and enabled)


func _on_scale_amount(value: float) -> void:
	RH.set_scale_amount(value)


func _select_target_option(t: String) -> void:
	match t:
		"scatter":
			target_option.select(1)
		"environment":
			target_option.select(2)
		"all":
			target_option.select(3)
		_:
			target_option.select(0)  # centerpiece / foreground


func _on_target_selected(index: int) -> void:
	var t := "centerpiece"
	match index:
		1:
			t = "scatter"
		2:
			t = "environment"
		3:
			t = "all"
	RH.set_field("target", t)


func _on_ascii_toggled(enabled: bool) -> void:
	var preset_name := ascii_preset.get_item_text(ascii_preset.selected)
	var params: Dictionary = AsciiEffect.PRESETS.get(preset_name, {}).duplicate()
	params["density"] = ascii_density_slider.value
	ShowDirector.set_effect("ascii", enabled, params)


func _on_ascii_preset(index: int) -> void:
	var preset_name := ascii_preset.get_item_text(index)
	var params: Dictionary = AsciiEffect.PRESETS[preset_name].duplicate()
	ascii_density_slider.value = float(params.get("density", 80.0))
	if ascii_toggle.button_pressed:
		ShowDirector.set_effect("ascii", true, params)


func _on_ascii_density(value: float) -> void:
	if ascii_toggle.button_pressed:
		var preset_name := ascii_preset.get_item_text(ascii_preset.selected)
		var params: Dictionary = AsciiEffect.PRESETS.get(preset_name, {}).duplicate()
		params["density"] = value
		ShowDirector.set_effect("ascii", true, params)


func _on_particles_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("particles", enabled, {"intensity": intensity_slider.value})


func _on_feedback_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("feedback", enabled, {"intensity": intensity_slider.value, "mix_amount": 0.7})


func _rebuild_cues() -> void:
	for child in cue_container.get_children():
		child.queue_free()
	for cue in ShowDirector.cues:
		if cue is Dictionary:
			var cue_id := str(cue.get("id", ""))
			var btn := Button.new()
			btn.text = cue_id
			btn.custom_minimum_size = Vector2(88, 32)
			btn.pressed.connect(func() -> void: ShowDirector.trigger_cue(cue_id))
			cue_container.add_child(btn)
