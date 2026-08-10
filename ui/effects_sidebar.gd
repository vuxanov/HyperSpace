extends PanelContainer

## Right sidebar — effects, ASCII presets, audio reactivity routing.
## Parameter bodies stay hidden until their effect toggle is ON (ASCII Live Visuals pattern).

const RH = preload("res://core/reactivity_hub.gd")

const DRIVER_IDS := ["off", "bass", "mids", "highs", "kick", "energy", "lfo"]
const DRIVER_LABELS := ["Off", "Bass", "Mids", "Highs", "Kick", "Energy", "LFO"]
const CAMERA_PRESETS := ["Off", "Pitch rock", "Roll bank", "Orbit tumble", "Spiral twist", "Kick snap"]
const FX_IDS := ["ascii", "particles", "feedback", "glitch", "chromatic", "pixel_sort"]


@onready var reactivity_toggle: CheckButton = $Margin/Scroll/Column/AudioSection/ReactivityToggle
@onready var reactivity_body: VBoxContainer = $Margin/Scroll/Column/AudioSection/ReactivityBody
@onready var intensity_slider: HSlider = $Margin/Scroll/Column/AudioSection/ReactivityBody/IntensitySlider
@onready var sensitivity_slider: HSlider = $Margin/Scroll/Column/AudioSection/ReactivityBody/SensitivitySlider
@onready var scale_amount_spin: SpinBox = $Margin/Scroll/Column/AudioSection/ReactivityBody/ScaleAmountSpin
@onready var energy_bar: ProgressBar = $Margin/Scroll/Column/AudioSection/ReactivityBody/EnergyBar
@onready var bass_bar: ProgressBar = $Margin/Scroll/Column/AudioSection/ReactivityBody/BassBar

@onready var targets: VBoxContainer = $Margin/Scroll/Column/Targets
@onready var affect_scale: CheckButton = $Margin/Scroll/Column/Targets/AffectScale
@onready var scale_source: OptionButton = $Margin/Scroll/Column/Targets/ScaleSource
@onready var scale_x: CheckButton = $Margin/Scroll/Column/Targets/AxisRow/ScaleX
@onready var scale_y: CheckButton = $Margin/Scroll/Column/Targets/AxisRow/ScaleY
@onready var scale_z: CheckButton = $Margin/Scroll/Column/Targets/AxisRow/ScaleZ
@onready var affect_light: CheckButton = $Margin/Scroll/Column/Targets/AffectLight
@onready var light_source: OptionButton = $Margin/Scroll/Column/Targets/LightSource
@onready var affect_emission: CheckButton = $Margin/Scroll/Column/Targets/AffectEmission
@onready var emission_source: OptionButton = $Margin/Scroll/Column/Targets/EmissionSource
@onready var affect_rotation: CheckButton = $Margin/Scroll/Column/Targets/AffectRotation
@onready var rotation_source: OptionButton = $Margin/Scroll/Column/Targets/RotationSource
@onready var affect_noise: CheckButton = $Margin/Scroll/Column/Targets/AffectNoise
@onready var noise_source: OptionButton = $Margin/Scroll/Column/Targets/NoiseSource
@onready var noise_target: OptionButton = $Margin/Scroll/Column/Targets/NoiseTarget
@onready var noise_amount: HSlider = $Margin/Scroll/Column/Targets/NoiseAmount
@onready var noise_scale: HSlider = $Margin/Scroll/Column/Targets/NoiseScale
@onready var target_option: OptionButton = $Margin/Scroll/Column/Targets/TargetOption
@onready var camera_preset: OptionButton = $Margin/Scroll/Column/Targets/CameraPreset
@onready var camera_rate: HSlider = $Margin/Scroll/Column/Targets/CameraRate
@onready var camera_depth: HSlider = $Margin/Scroll/Column/Targets/CameraDepth

@onready var play_all_toggle: CheckButton = $Margin/Scroll/Column/FxSection/PlayAllToggle
@onready var play_all_body: VBoxContainer = $Margin/Scroll/Column/FxSection/PlayAllBody
@onready var play_cycle_slider: HSlider = $Margin/Scroll/Column/FxSection/PlayAllBody/PlayCycleSlider
@onready var play_active_slider: HSlider = $Margin/Scroll/Column/FxSection/PlayAllBody/PlayActiveSlider

@onready var ascii_toggle: CheckButton = $Margin/Scroll/Column/FxSection/AsciiToggle
@onready var ascii_body: VBoxContainer = $Margin/Scroll/Column/FxSection/AsciiBody
@onready var ascii_preset: OptionButton = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiPreset
@onready var ascii_density_min: HSlider = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiDensityMin
@onready var ascii_density_max: HSlider = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiDensityMax
@onready var ascii_invert: CheckButton = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiInvert
@onready var style_switch_toggle: CheckButton = $Margin/Scroll/Column/FxSection/AsciiBody/StyleSwitchToggle
@onready var style_switch_body: VBoxContainer = $Margin/Scroll/Column/FxSection/AsciiBody/StyleSwitchBody
@onready var style_interval_slider: HSlider = $Margin/Scroll/Column/FxSection/AsciiBody/StyleSwitchBody/StyleIntervalSlider
@onready var style_jitter_toggle: CheckButton = $Margin/Scroll/Column/FxSection/AsciiBody/StyleSwitchBody/StyleJitterToggle
@onready var ascii_schedule: CheckButton = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiSchedule

@onready var particles_toggle: CheckButton = $Margin/Scroll/Column/FxSection/ParticlesToggle
@onready var particles_body: VBoxContainer = $Margin/Scroll/Column/FxSection/ParticlesBody
@onready var particles_target: OptionButton = $Margin/Scroll/Column/FxSection/ParticlesBody/ParticlesTarget
@onready var particles_schedule: CheckButton = $Margin/Scroll/Column/FxSection/ParticlesBody/ParticlesSchedule

@onready var feedback_toggle: CheckButton = $Margin/Scroll/Column/FxSection/FeedbackToggle
@onready var feedback_body: VBoxContainer = $Margin/Scroll/Column/FxSection/FeedbackBody
@onready var feedback_mix_slider: HSlider = $Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackMixSlider
@onready var feedback_persist_slider: HSlider = $Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackPersistSlider
@onready var feedback_schedule: CheckButton = $Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackSchedule

@onready var glitch_toggle: CheckButton = $Margin/Scroll/Column/FxSection/GlitchToggle
@onready var glitch_body: VBoxContainer = $Margin/Scroll/Column/FxSection/GlitchBody
@onready var glitch_amount_slider: HSlider = $Margin/Scroll/Column/FxSection/GlitchBody/GlitchAmountSlider
@onready var glitch_speed_slider: HSlider = $Margin/Scroll/Column/FxSection/GlitchBody/GlitchSpeedSlider
@onready var glitch_hsize_slider: HSlider = $Margin/Scroll/Column/FxSection/GlitchBody/GlitchHSizeSlider
@onready var glitch_rgb_slider: HSlider = $Margin/Scroll/Column/FxSection/GlitchBody/GlitchRgbSlider
@onready var glitch_chaos_slider: HSlider = $Margin/Scroll/Column/FxSection/GlitchBody/GlitchChaosSlider
@onready var glitch_schedule: CheckButton = $Margin/Scroll/Column/FxSection/GlitchBody/GlitchSchedule

@onready var chromatic_toggle: CheckButton = $Margin/Scroll/Column/FxSection/ChromaticToggle
@onready var chromatic_body: VBoxContainer = $Margin/Scroll/Column/FxSection/ChromaticBody
@onready var chromatic_amount_slider: HSlider = $Margin/Scroll/Column/FxSection/ChromaticBody/ChromaticAmountSlider
@onready var chromatic_schedule: CheckButton = $Margin/Scroll/Column/FxSection/ChromaticBody/ChromaticSchedule

@onready var pixel_sort_toggle: CheckButton = $Margin/Scroll/Column/FxSection/PixelSortToggle
@onready var pixel_sort_body: VBoxContainer = $Margin/Scroll/Column/FxSection/PixelSortBody
@onready var pixel_sort_amount_slider: HSlider = $Margin/Scroll/Column/FxSection/PixelSortBody/PixelSortAmountSlider
@onready var pixel_sort_threshold_slider: HSlider = $Margin/Scroll/Column/FxSection/PixelSortBody/PixelSortThresholdSlider
@onready var pixel_sort_stretch_slider: HSlider = $Margin/Scroll/Column/FxSection/PixelSortBody/PixelSortStretchSlider
@onready var pixel_sort_schedule: CheckButton = $Margin/Scroll/Column/FxSection/PixelSortBody/PixelSortSchedule

@onready var cue_container: HFlowContainer = $Margin/Scroll/Column/CueSection/CueContainer

var _syncing_ui: bool = false


func _ready() -> void:
	for preset_name in AsciiEffect.PRESETS.keys():
		ascii_preset.add_item(str(preset_name))
	target_option.clear()
	target_option.add_item("Centerpiece", 0)
	target_option.add_item("Scatter", 1)
	target_option.add_item("Environment", 2)
	target_option.add_item("Lights", 3)
	target_option.add_item("Everything", 4)
	_fill_driver(scale_source)
	_fill_driver(emission_source)
	_fill_driver(rotation_source)
	_fill_driver(light_source)
	_fill_driver(noise_source)
	camera_preset.clear()
	for p in CAMERA_PRESETS:
		camera_preset.add_item(p)
	reactivity_toggle.button_pressed = bool(RH.get_field("enabled", true))
	affect_scale.button_pressed = bool(RH.get_field("affect_scale", true))
	scale_x.button_pressed = bool(RH.get_field("scale_x", true))
	scale_y.button_pressed = bool(RH.get_field("scale_y", true))
	scale_z.button_pressed = bool(RH.get_field("scale_z", true))
	affect_light.button_pressed = bool(RH.get_field("affect_light", true))
	affect_emission.button_pressed = bool(RH.get_field("affect_emission", false))
	affect_rotation.button_pressed = bool(RH.get_field("affect_rotation", true))
	affect_noise.button_pressed = bool(RH.get_field("affect_noise", false))
	scale_amount_spin.value = RH.scale_amount()
	noise_amount.value = float(RH.get_field("noise_amount", 18.0))
	noise_scale.value = float(RH.get_field("noise_scale", RH.get_field("noise_speed", 4.0)))
	_select_target_option(RH.target())
	_select_driver(scale_source, str(RH.get_field("scale_source", "bass")))
	_select_driver(emission_source, str(RH.get_field("emission_source", "mids")))
	_select_driver(rotation_source, str(RH.get_field("rotation_source", "highs")))
	_select_driver(light_source, str(RH.get_field("light_source", "energy")))
	_select_driver(noise_source, str(RH.get_field("noise_source", "energy")))
	_select_camera_preset(str(RH.get_field("camera_preset", "Off")))
	# Camera rate/depth UI are 1–100 ints; settings store float rate and 0–1 depth.
	camera_rate.value = clampf(float(RH.get_field("camera_rate", 1.0)) * 20.0, 1.0, 100.0)
	camera_depth.value = clampf(float(RH.get_field("camera_depth", 0.55)) * 100.0, 0.0, 100.0)
	particles_target.clear()
	particles_target.add_item("Everything", 0)
	particles_target.add_item("Main character", 1)
	particles_target.add_item("Scatter", 2)
	particles_target.add_item("Environment", 3)
	particles_target.add_item("Lights", 4)
	particles_target.add_item("Media (images)", 5)
	_select_particles_target(str(RH.get_field("particles_target", "all")))
	noise_target.clear()
	noise_target.add_item("Everything", 0)
	noise_target.add_item("Main character", 1)
	noise_target.add_item("Scatter", 2)
	noise_target.add_item("Environment", 3)
	noise_target.add_item("Lights", 4)
	_select_noise_target(str(RH.get_field("noise_target", "all")))

	reactivity_toggle.toggled.connect(_on_reactivity_toggled)
	intensity_slider.value_changed.connect(func(v: float) -> void: AudioAnalyzer.master_intensity = v)
	sensitivity_slider.value_changed.connect(func(v: float) -> void: AudioAnalyzer.band_sensitivity = v)
	scale_amount_spin.value_changed.connect(_on_scale_amount)
	affect_scale.toggled.connect(_on_affect_scale)
	scale_x.toggled.connect(func(v: bool) -> void: RH.set_field("scale_x", v))
	scale_y.toggled.connect(func(v: bool) -> void: RH.set_field("scale_y", v))
	scale_z.toggled.connect(func(v: bool) -> void: RH.set_field("scale_z", v))
	affect_light.toggled.connect(_on_affect_light)
	affect_emission.toggled.connect(_on_affect_emission)
	affect_rotation.toggled.connect(_on_affect_rotation)
	affect_noise.toggled.connect(_on_affect_noise)
	scale_source.item_selected.connect(func(i: int) -> void: RH.set_field("scale_source", DRIVER_IDS[i]))
	emission_source.item_selected.connect(func(i: int) -> void: RH.set_field("emission_source", DRIVER_IDS[i]))
	rotation_source.item_selected.connect(func(i: int) -> void: RH.set_field("rotation_source", DRIVER_IDS[i]))
	light_source.item_selected.connect(func(i: int) -> void: RH.set_field("light_source", DRIVER_IDS[i]))
	noise_source.item_selected.connect(func(i: int) -> void: RH.set_field("noise_source", DRIVER_IDS[i]))
	noise_target.item_selected.connect(_on_noise_target_selected)
	noise_amount.value_changed.connect(func(v: float) -> void: RH.set_field("noise_amount", v))
	noise_scale.value_changed.connect(func(v: float) -> void: RH.set_field("noise_scale", v))
	camera_preset.item_selected.connect(_on_camera_preset)
	camera_rate.value_changed.connect(func(v: float) -> void: RH.set_field("camera_rate", v / 20.0))
	camera_depth.value_changed.connect(func(v: float) -> void: RH.set_field("camera_depth", v / 100.0))
	target_option.item_selected.connect(_on_target_selected)

	play_all_toggle.toggled.connect(_on_play_all_toggled)
	play_cycle_slider.value_changed.connect(_on_play_timing_changed)
	play_active_slider.value_changed.connect(_on_play_timing_changed)
	style_switch_toggle.toggled.connect(_on_style_switch_toggled)
	style_interval_slider.value_changed.connect(_on_style_interval)
	style_jitter_toggle.toggled.connect(_on_style_jitter)

	ascii_toggle.toggled.connect(_on_ascii_toggled)
	ascii_preset.item_selected.connect(_on_ascii_preset)
	ascii_density_min.value_changed.connect(_on_ascii_density_range)
	ascii_density_max.value_changed.connect(_on_ascii_density_range)
	ascii_invert.toggled.connect(_on_ascii_invert)
	ascii_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("ascii", v))

	particles_toggle.toggled.connect(_on_particles_toggled)
	particles_target.item_selected.connect(_on_particles_target_selected)
	particles_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("particles", v))

	feedback_toggle.toggled.connect(_on_feedback_toggled)
	feedback_mix_slider.value_changed.connect(_on_feedback_params)
	feedback_persist_slider.value_changed.connect(_on_feedback_params)
	feedback_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("feedback", v))

	glitch_toggle.toggled.connect(_on_glitch_toggled)
	glitch_amount_slider.value_changed.connect(_on_glitch_params)
	glitch_speed_slider.value_changed.connect(_on_glitch_params)
	glitch_hsize_slider.value_changed.connect(_on_glitch_params)
	glitch_rgb_slider.value_changed.connect(_on_glitch_params)
	glitch_chaos_slider.value_changed.connect(_on_glitch_params)
	glitch_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("glitch", v))

	chromatic_toggle.toggled.connect(_on_chromatic_toggled)
	chromatic_amount_slider.value_changed.connect(_on_chromatic_params)
	chromatic_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("chromatic", v))

	pixel_sort_toggle.toggled.connect(_on_pixel_sort_toggled)
	pixel_sort_amount_slider.value_changed.connect(_on_pixel_sort_params)
	pixel_sort_threshold_slider.value_changed.connect(_on_pixel_sort_params)
	pixel_sort_stretch_slider.value_changed.connect(_on_pixel_sort_params)
	pixel_sort_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("pixel_sort", v))

	ShowDirector.show_loaded.connect(func(_n: String) -> void: _rebuild_cues())
	ShowDirector.effect_style_advanced.connect(_on_style_advanced_ui)
	AudioAnalyzer.state_updated.connect(_on_audio)
	_rebuild_cues()
	_sync_conditional_ui()


func _fill_driver(opt: OptionButton) -> void:
	opt.clear()
	for label in DRIVER_LABELS:
		opt.add_item(label)


func _select_driver(opt: OptionButton, src: String) -> void:
	var idx := DRIVER_IDS.find(src)
	opt.select(idx if idx >= 0 else 0)


func _select_camera_preset(preset: String) -> void:
	var resolved := preset
	match preset:
		"Sine pan", "Figure-8":
			resolved = "Orbit tumble"
		"Sine tilt":
			resolved = "Pitch rock"
		"Noise wander":
			resolved = "Spiral twist"
		"Pulse":
			resolved = "Kick snap"
	var idx := CAMERA_PRESETS.find(resolved)
	camera_preset.select(idx if idx >= 0 else 0)
	if resolved != preset and idx >= 0:
		RH.set_field("camera_preset", resolved)


func _on_camera_preset(index: int) -> void:
	RH.set_field("camera_preset", CAMERA_PRESETS[index])
	_sync_conditional_ui()


func _on_audio(state: AudioState) -> void:
	energy_bar.value = clampf(state.energy, 0.0, 1.0)
	bass_bar.value = clampf(state.bass, 0.0, 1.0)


func _on_reactivity_toggled(enabled: bool) -> void:
	RH.set_enabled(enabled)
	_sync_conditional_ui()


func _sync_conditional_ui() -> void:
	## Accordion: hide (not disable) anything that is switched off.
	var react_on := RH.enabled()
	reactivity_body.visible = react_on
	targets.visible = react_on

	var scale_on := react_on and affect_scale.button_pressed
	scale_source.visible = scale_on
	$Margin/Scroll/Column/Targets/AxisRow.visible = scale_on

	var light_on := react_on and affect_light.button_pressed
	light_source.visible = light_on

	var emission_on := react_on and affect_emission.button_pressed
	emission_source.visible = emission_on

	var rotation_on := react_on and affect_rotation.button_pressed
	rotation_source.visible = rotation_on

	var noise_on := react_on and affect_noise.button_pressed
	noise_source.visible = noise_on
	$Margin/Scroll/Column/Targets/NoiseTargetLabel.visible = noise_on
	noise_target.visible = noise_on
	$Margin/Scroll/Column/Targets/NoiseAmountLabel.visible = noise_on
	noise_amount.visible = noise_on
	$Margin/Scroll/Column/Targets/NoiseScaleLabel.visible = noise_on
	noise_scale.visible = noise_on

	var cam_on := react_on and camera_preset.selected > 0
	$Margin/Scroll/Column/Targets/CameraRateLabel.visible = cam_on
	camera_rate.visible = cam_on
	$Margin/Scroll/Column/Targets/CameraDepthLabel.visible = cam_on
	camera_depth.visible = cam_on

	ascii_body.visible = ascii_toggle.button_pressed
	style_switch_body.visible = ascii_toggle.button_pressed and style_switch_toggle.button_pressed
	particles_body.visible = particles_toggle.button_pressed
	feedback_body.visible = feedback_toggle.button_pressed
	glitch_body.visible = glitch_toggle.button_pressed
	chromatic_body.visible = chromatic_toggle.button_pressed
	pixel_sort_body.visible = pixel_sort_toggle.button_pressed
	play_all_body.visible = play_all_toggle.button_pressed

	cue_container.get_parent().visible = cue_container.get_child_count() > 0


func _select_particles_target(t: String) -> void:
	match t:
		"centerpiece", "foreground":
			particles_target.select(1)
		"scatter":
			particles_target.select(2)
		"environment":
			particles_target.select(3)
		"lights", "light":
			particles_target.select(4)
		"media":
			particles_target.select(5)
		_:
			particles_target.select(0)


func _select_noise_target(t: String) -> void:
	match t:
		"centerpiece", "foreground", "main":
			noise_target.select(1)
		"scatter":
			noise_target.select(2)
		"environment":
			noise_target.select(3)
		"lights", "light":
			noise_target.select(4)
		_:
			noise_target.select(0)


func _on_particles_target_selected(index: int) -> void:
	var t := "all"
	match index:
		1:
			t = "centerpiece"
		2:
			t = "scatter"
		3:
			t = "environment"
		4:
			t = "lights"
		5:
			t = "media"
	RH.set_field("particles_target", t)
	if particles_toggle.button_pressed:
		ShowDirector.set_effect("particles", true, {"intensity": intensity_slider.value, "target": t})


func _on_noise_target_selected(index: int) -> void:
	var t := "all"
	match index:
		1:
			t = "centerpiece"
		2:
			t = "scatter"
		3:
			t = "environment"
		4:
			t = "lights"
	RH.set_field("noise_target", t)


func _on_affect_scale(enabled: bool) -> void:
	RH.set_field("affect_scale", enabled)
	_sync_conditional_ui()


func _on_affect_light(enabled: bool) -> void:
	RH.set_field("affect_light", enabled)
	_sync_conditional_ui()


func _on_affect_emission(enabled: bool) -> void:
	RH.set_field("affect_emission", enabled)
	_sync_conditional_ui()


func _on_affect_rotation(enabled: bool) -> void:
	RH.set_field("affect_rotation", enabled)
	_sync_conditional_ui()


func _on_affect_noise(enabled: bool) -> void:
	RH.set_field("affect_noise", enabled)
	_sync_conditional_ui()


func _on_scale_amount(value: float) -> void:
	RH.set_scale_amount(value)


func _select_target_option(t: String) -> void:
	match t:
		"scatter":
			target_option.select(1)
		"environment":
			target_option.select(2)
		"lights", "light":
			target_option.select(3)
		"all":
			target_option.select(4)
		_:
			target_option.select(0)


func _on_target_selected(index: int) -> void:
	var t := "centerpiece"
	match index:
		1:
			t = "scatter"
		2:
			t = "environment"
		3:
			t = "lights"
		4:
			t = "all"
	RH.set_field("target", t)


func _ascii_params() -> Dictionary:
	var preset_name := ascii_preset.get_item_text(ascii_preset.selected)
	var params: Dictionary = AsciiEffect.PRESETS.get(preset_name, {}).duplicate()
	var dmin := ascii_density_min.value
	var dmax := ascii_density_max.value
	if dmin > dmax:
		var tmp := dmin
		dmin = dmax
		dmax = tmp
	params["density_min"] = dmin
	params["density_max"] = dmax
	params["density"] = lerpf(dmin, dmax, 0.5)
	params["invert"] = ascii_invert.button_pressed
	return params


func _on_ascii_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("ascii", enabled, _ascii_params())
	_sync_conditional_ui()


func _on_ascii_preset(index: int) -> void:
	var preset_name := ascii_preset.get_item_text(index)
	var params: Dictionary = AsciiEffect.PRESETS[preset_name].duplicate()
	var dens := float(params.get("density", 80.0))
	ascii_density_min.value = maxf(1.0, dens * 0.65)
	ascii_density_max.value = dens
	params["invert"] = ascii_invert.button_pressed
	params["density_min"] = ascii_density_min.value
	params["density_max"] = ascii_density_max.value
	if ascii_toggle.button_pressed:
		ShowDirector.set_effect("ascii", true, params)


func _on_ascii_density_range(_v: float = 0.0) -> void:
	if ascii_density_min.value > ascii_density_max.value:
		if _v == ascii_density_min.value:
			ascii_density_max.value = ascii_density_min.value
		else:
			ascii_density_min.value = ascii_density_max.value
	if ascii_toggle.button_pressed:
		ShowDirector.set_effect("ascii", true, _ascii_params())


func _on_ascii_invert(enabled: bool) -> void:
	if ascii_toggle.button_pressed:
		var params := _ascii_params()
		params["invert"] = enabled
		ShowDirector.set_effect("ascii", true, params)


func _on_particles_toggled(enabled: bool) -> void:
	var t := str(RH.get_field("particles_target", "all"))
	ShowDirector.set_effect("particles", enabled, {"intensity": intensity_slider.value, "target": t})
	_sync_conditional_ui()


func _feedback_params() -> Dictionary:
	return {
		"intensity": intensity_slider.value,
		"mix_amount": feedback_mix_slider.value / 100.0,
		"persistence": feedback_persist_slider.value / 100.0,
	}


func _on_feedback_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("feedback", enabled, _feedback_params())
	_sync_conditional_ui()


func _on_feedback_params(_v: float = 0.0) -> void:
	if feedback_toggle.button_pressed:
		ShowDirector.set_effect("feedback", true, _feedback_params())


func _glitch_params() -> Dictionary:
	# UI 1–100 → strong shader drive (40 ≈ 1.0, 100 ≈ 2.5)
	return {
		"intensity": glitch_amount_slider.value / 40.0,
		"rate": glitch_speed_slider.value / 4.0,
		"h_size": glitch_hsize_slider.value / 100.0,
		"rgb_split": glitch_rgb_slider.value / 100.0,
		"slice_chaos": glitch_chaos_slider.value / 100.0,
	}


func _on_glitch_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("glitch", enabled, _glitch_params())
	_sync_conditional_ui()


func _on_glitch_params(_v: float = 0.0) -> void:
	if glitch_toggle.button_pressed:
		ShowDirector.set_effect("glitch", true, _glitch_params())


func _chromatic_params() -> Dictionary:
	return {
		"intensity": maxf(intensity_slider.value / 4.0, 0.5),
		"amount": chromatic_amount_slider.value / 40.0,
	}


func _on_chromatic_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("chromatic", enabled, _chromatic_params())
	_sync_conditional_ui()


func _on_chromatic_params(_v: float = 0.0) -> void:
	if chromatic_toggle.button_pressed:
		ShowDirector.set_effect("chromatic", true, _chromatic_params())


func _pixel_sort_params() -> Dictionary:
	return {
		"intensity": pixel_sort_amount_slider.value / 40.0,
		"threshold": pixel_sort_threshold_slider.value / 100.0,
		"stretch": pixel_sort_stretch_slider.value / 100.0,
	}


func _on_pixel_sort_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("pixel_sort", enabled, _pixel_sort_params())
	_sync_conditional_ui()


func _on_pixel_sort_params(_v: float = 0.0) -> void:
	if pixel_sort_toggle.button_pressed:
		ShowDirector.set_effect("pixel_sort", true, _pixel_sort_params())


func _on_effect_schedule(effect_id: String, on: bool) -> void:
	var cycle := play_cycle_slider.value
	var active := mini(play_active_slider.value, cycle * 0.95)
	ShowDirector.fx_automation.set_gate_times(effect_id, cycle, active)
	ShowDirector.fx_automation.set_gate_enabled(effect_id, on)
	ShowDirector.refresh_effect(effect_id)


func _on_play_all_toggled(on: bool) -> void:
	_sync_conditional_ui()
	if on:
		if ascii_toggle.button_pressed and not style_switch_toggle.button_pressed:
			style_switch_toggle.button_pressed = true
		_syncing_ui = true
		for sid in [
			[ascii_toggle, ascii_schedule],
			[particles_toggle, particles_schedule],
			[feedback_toggle, feedback_schedule],
			[glitch_toggle, glitch_schedule],
			[chromatic_toggle, chromatic_schedule],
			[pixel_sort_toggle, pixel_sort_schedule],
		]:
			var master: CheckButton = sid[0]
			var sched: CheckButton = sid[1]
			if master.button_pressed and not sched.button_pressed:
				sched.button_pressed = true
		_syncing_ui = false
		ShowDirector.set_play_all_effects(true, play_cycle_slider.value, play_active_slider.value)
		ShowDirector.fx_automation.set_style_interval(style_interval_slider.value)
		ShowDirector.fx_automation.set_style_jitter(style_jitter_toggle.button_pressed)
	else:
		ShowDirector.set_play_all_effects(false)
		_syncing_ui = true
		ascii_schedule.button_pressed = false
		particles_schedule.button_pressed = false
		feedback_schedule.button_pressed = false
		glitch_schedule.button_pressed = false
		chromatic_schedule.button_pressed = false
		pixel_sort_schedule.button_pressed = false
		style_switch_toggle.button_pressed = false
		_syncing_ui = false
		_sync_conditional_ui()


func _on_play_timing_changed(_v: float = 0.0) -> void:
	var cycle := play_cycle_slider.value
	var active := mini(play_active_slider.value, cycle * 0.95)
	for eid in FX_IDS:
		if ShowDirector.fx_automation.is_gate_enabled(eid):
			ShowDirector.fx_automation.set_gate_times(eid, cycle, active)


func _on_style_switch_toggled(on: bool) -> void:
	if _syncing_ui:
		_sync_conditional_ui()
		return
	ShowDirector.fx_automation.set_style_interval(style_interval_slider.value)
	ShowDirector.fx_automation.set_style_jitter(style_jitter_toggle.button_pressed)
	ShowDirector.fx_automation.set_style_active(on)
	_sync_conditional_ui()


func _on_style_interval(v: float) -> void:
	ShowDirector.fx_automation.set_style_interval(v)


func _on_style_jitter(on: bool) -> void:
	ShowDirector.fx_automation.set_style_jitter(on)


func _on_style_advanced_ui(preset_name: String) -> void:
	_syncing_ui = true
	for i in ascii_preset.item_count:
		if ascii_preset.get_item_text(i) == preset_name:
			ascii_preset.select(i)
			var params: Dictionary = AsciiEffect.PRESETS.get(preset_name, {})
			if params.has("density"):
				var dens := float(params["density"])
				ascii_density_min.value = maxf(1.0, dens * 0.65)
				ascii_density_max.value = dens
			break
	_syncing_ui = false


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
	_sync_conditional_ui()
