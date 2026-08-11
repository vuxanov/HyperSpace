extends PanelContainer

## Right sidebar — effects, ASCII presets, audio reactivity routing.
## Parameter bodies stay hidden until their effect toggle is ON (ASCII Live Visuals pattern).

const RH = preload("res://core/reactivity_hub.gd")
const DualRangeSliderScr = preload("res://ui/dual_range_slider.gd")
const ScheduleSecondsPairScr = preload("res://ui/schedule_seconds_pair.gd")

const DRIVER_IDS := ["off", "bass", "mids", "highs", "kick", "energy", "lfo"]
const DRIVER_LABELS := ["Off", "Bass", "Mids", "Highs", "Kick", "Energy", "LFO"]
const FX_DRIVE_IDS := ["audio", "lfo", "auto"]
const FX_DRIVE_LABELS := ["Audio", "LFO", "Auto"]
const ASCII_LFO_WAVE_IDS := ["sine", "triangle", "saw", "square"]
const ASCII_LFO_WAVE_LABELS := ["Sine", "Triangle", "Saw", "Square"]
const CAMERA_PRESETS := ["Off", "Pitch rock", "Roll bank", "Orbit tumble", "Spiral twist", "Kick snap"]
const FX_IDS := ["ascii", "particles", "feedback", "glitch", "chromatic", "pixel_sort", "wireframe"]


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
@onready var scale_schedule: CheckButton = $Margin/Scroll/Column/Targets/ScaleSchedule
@onready var scale_schedule_host: VBoxContainer = $Margin/Scroll/Column/Targets/ScaleScheduleHost
@onready var affect_light: CheckButton = $Margin/Scroll/Column/Targets/AffectLight
@onready var light_source: OptionButton = $Margin/Scroll/Column/Targets/LightSource
@onready var light_schedule: CheckButton = $Margin/Scroll/Column/Targets/LightSchedule
@onready var light_schedule_host: VBoxContainer = $Margin/Scroll/Column/Targets/LightScheduleHost
@onready var affect_emission: CheckButton = $Margin/Scroll/Column/Targets/AffectEmission
@onready var emission_source: OptionButton = $Margin/Scroll/Column/Targets/EmissionSource
@onready var emission_schedule: CheckButton = $Margin/Scroll/Column/Targets/EmissionSchedule
@onready var emission_schedule_host: VBoxContainer = $Margin/Scroll/Column/Targets/EmissionScheduleHost
@onready var affect_rotation: CheckButton = $Margin/Scroll/Column/Targets/AffectRotation
@onready var rotation_source: OptionButton = $Margin/Scroll/Column/Targets/RotationSource
@onready var rotation_amount_spin: SpinBox = $Margin/Scroll/Column/Targets/RotationAmountSpin
@onready var rotation_x: CheckButton = $Margin/Scroll/Column/Targets/RotationAxisRow/RotationX
@onready var rotation_y: CheckButton = $Margin/Scroll/Column/Targets/RotationAxisRow/RotationY
@onready var rotation_z: CheckButton = $Margin/Scroll/Column/Targets/RotationAxisRow/RotationZ
@onready var rotation_schedule: CheckButton = $Margin/Scroll/Column/Targets/RotationSchedule
@onready var rotation_schedule_host: VBoxContainer = $Margin/Scroll/Column/Targets/RotationScheduleHost
@onready var affect_noise: CheckButton = $Margin/Scroll/Column/Targets/AffectNoise
@onready var noise_source: OptionButton = $Margin/Scroll/Column/Targets/NoiseSource
@onready var noise_target: OptionButton = $Margin/Scroll/Column/Targets/NoiseTarget
@onready var noise_amount: HSlider = $Margin/Scroll/Column/Targets/NoiseAmount
@onready var noise_scale: HSlider = $Margin/Scroll/Column/Targets/NoiseScale
@onready var noise_x: CheckButton = $Margin/Scroll/Column/Targets/NoiseAxisRow/NoiseX
@onready var noise_y: CheckButton = $Margin/Scroll/Column/Targets/NoiseAxisRow/NoiseY
@onready var noise_z: CheckButton = $Margin/Scroll/Column/Targets/NoiseAxisRow/NoiseZ
@onready var noise_schedule: CheckButton = $Margin/Scroll/Column/Targets/NoiseSchedule
@onready var noise_schedule_host: VBoxContainer = $Margin/Scroll/Column/Targets/NoiseScheduleHost
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
@onready var ascii_drive: OptionButton = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiDrive
@onready var ascii_preset: OptionButton = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiPreset
@onready var ascii_density_min: HSlider = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiDensityMin
@onready var ascii_density_max: HSlider = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiDensityMax
@onready var ascii_density_random: CheckButton = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiDensityRandom
@onready var ascii_density_host: VBoxContainer = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiDensityRangeHost
@onready var ascii_invert: CheckButton = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiInvert
@onready var style_switch_toggle: CheckButton = $Margin/Scroll/Column/FxSection/AsciiBody/StyleSwitchToggle
@onready var style_switch_body: VBoxContainer = $Margin/Scroll/Column/FxSection/AsciiBody/StyleSwitchBody
@onready var style_interval_slider: HSlider = $Margin/Scroll/Column/FxSection/AsciiBody/StyleSwitchBody/StyleIntervalSlider
@onready var style_jitter_toggle: CheckButton = $Margin/Scroll/Column/FxSection/AsciiBody/StyleSwitchBody/StyleJitterToggle
@onready var ascii_schedule: CheckButton = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiSchedule
@onready var ascii_schedule_host: VBoxContainer = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiScheduleHost

@onready var particles_toggle: CheckButton = $Margin/Scroll/Column/FxSection/ParticlesToggle
@onready var particles_body: VBoxContainer = $Margin/Scroll/Column/FxSection/ParticlesBody
@onready var particles_drive: OptionButton = $Margin/Scroll/Column/FxSection/ParticlesBody/ParticlesDrive
@onready var particles_target: OptionButton = $Margin/Scroll/Column/FxSection/ParticlesBody/ParticlesTarget
@onready var particles_schedule: CheckButton = $Margin/Scroll/Column/FxSection/ParticlesBody/ParticlesSchedule
@onready var particles_schedule_host: VBoxContainer = $Margin/Scroll/Column/FxSection/ParticlesBody/ParticlesScheduleHost

@onready var feedback_toggle: CheckButton = $Margin/Scroll/Column/FxSection/FeedbackToggle
@onready var feedback_body: VBoxContainer = $Margin/Scroll/Column/FxSection/FeedbackBody
@onready var feedback_drive: OptionButton = $Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackDrive
@onready var feedback_mix_slider: HSlider = $Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackMixSlider
@onready var feedback_persist_slider: HSlider = $Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackPersistSlider
@onready var feedback_sens_slider: HSlider = $Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackSensSlider
@onready var feedback_lfo_rate: HSlider = $Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackLfoRate
@onready var feedback_schedule: CheckButton = $Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackSchedule
@onready var feedback_schedule_host: VBoxContainer = $Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackScheduleHost

@onready var glitch_toggle: CheckButton = $Margin/Scroll/Column/FxSection/GlitchToggle
@onready var glitch_body: VBoxContainer = $Margin/Scroll/Column/FxSection/GlitchBody
@onready var glitch_drive: OptionButton = $Margin/Scroll/Column/FxSection/GlitchBody/GlitchDrive
@onready var glitch_amount_slider: HSlider = $Margin/Scroll/Column/FxSection/GlitchBody/GlitchAmountSlider
@onready var glitch_speed_slider: HSlider = $Margin/Scroll/Column/FxSection/GlitchBody/GlitchSpeedSlider
@onready var glitch_hsize_slider: HSlider = $Margin/Scroll/Column/FxSection/GlitchBody/GlitchHSizeSlider
@onready var glitch_rgb_slider: HSlider = $Margin/Scroll/Column/FxSection/GlitchBody/GlitchRgbSlider
@onready var glitch_chaos_slider: HSlider = $Margin/Scroll/Column/FxSection/GlitchBody/GlitchChaosSlider
@onready var glitch_schedule: CheckButton = $Margin/Scroll/Column/FxSection/GlitchBody/GlitchSchedule
@onready var glitch_schedule_host: VBoxContainer = $Margin/Scroll/Column/FxSection/GlitchBody/GlitchScheduleHost

@onready var chromatic_toggle: CheckButton = $Margin/Scroll/Column/FxSection/ChromaticToggle
@onready var chromatic_body: VBoxContainer = $Margin/Scroll/Column/FxSection/ChromaticBody
@onready var chromatic_drive: OptionButton = $Margin/Scroll/Column/FxSection/ChromaticBody/ChromaticDrive
@onready var chromatic_amount_slider: HSlider = $Margin/Scroll/Column/FxSection/ChromaticBody/ChromaticAmountSlider
@onready var chromatic_schedule: CheckButton = $Margin/Scroll/Column/FxSection/ChromaticBody/ChromaticSchedule
@onready var chromatic_schedule_host: VBoxContainer = $Margin/Scroll/Column/FxSection/ChromaticBody/ChromaticScheduleHost

@onready var pixel_sort_toggle: CheckButton = $Margin/Scroll/Column/FxSection/PixelSortToggle
@onready var pixel_sort_body: VBoxContainer = $Margin/Scroll/Column/FxSection/PixelSortBody
@onready var pixel_sort_drive: OptionButton = $Margin/Scroll/Column/FxSection/PixelSortBody/PixelSortDrive
@onready var pixel_sort_amount_slider: HSlider = $Margin/Scroll/Column/FxSection/PixelSortBody/PixelSortAmountSlider
@onready var pixel_sort_threshold_slider: HSlider = $Margin/Scroll/Column/FxSection/PixelSortBody/PixelSortThresholdSlider
@onready var pixel_sort_stretch_slider: HSlider = $Margin/Scroll/Column/FxSection/PixelSortBody/PixelSortStretchSlider
@onready var pixel_sort_schedule: CheckButton = $Margin/Scroll/Column/FxSection/PixelSortBody/PixelSortSchedule
@onready var pixel_sort_schedule_host: VBoxContainer = $Margin/Scroll/Column/FxSection/PixelSortBody/PixelSortScheduleHost

@onready var wireframe_toggle: CheckButton = $Margin/Scroll/Column/FxSection/WireframeToggle
@onready var wireframe_body: VBoxContainer = $Margin/Scroll/Column/FxSection/WireframeBody
@onready var wireframe_drive: OptionButton = $Margin/Scroll/Column/FxSection/WireframeBody/WireframeDrive
@onready var wireframe_schedule: CheckButton = $Margin/Scroll/Column/FxSection/WireframeBody/WireframeSchedule
@onready var wireframe_schedule_host: VBoxContainer = $Margin/Scroll/Column/FxSection/WireframeBody/WireframeScheduleHost

@onready var cue_container: HFlowContainer = $Margin/Scroll/Column/CueSection/CueContainer

var _syncing_ui: bool = false
var _fx_drive_opts: Dictionary = {}
var _density_range  # DualRangeSlider (ASCII density only)
var _play_schedule_range  # ScheduleSecondsPair
var _schedule_ranges: Dictionary = {}  # effect_id -> ScheduleSecondsPair
var _user_density_min: float = 8.0
var _user_density_max: float = 80.0
var _ascii_lfo_wave: OptionButton
var _ascii_lfo_rate: HSlider
var _ascii_lfo_wave_label: Label
var _ascii_lfo_rate_label: Label


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
	_fx_drive_opts = {
		"ascii": ascii_drive,
		"particles": particles_drive,
		"feedback": feedback_drive,
		"glitch": glitch_drive,
		"chromatic": chromatic_drive,
		"pixel_sort": pixel_sort_drive,
		"wireframe": wireframe_drive,
	}
	for opt in _fx_drive_opts.values():
		_fill_fx_drive(opt as OptionButton)
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
	rotation_amount_spin.value = float(RH.get_field("rotation_amount", 20.0))
	rotation_x.button_pressed = bool(RH.get_field("rotation_x", true))
	rotation_y.button_pressed = bool(RH.get_field("rotation_y", true))
	rotation_z.button_pressed = bool(RH.get_field("rotation_z", true))
	noise_amount.value = float(RH.get_field("noise_amount", 28.0))
	noise_scale.value = float(RH.get_field("noise_scale", RH.get_field("noise_speed", 4.0)))
	noise_x.button_pressed = bool(RH.get_field("noise_x", true))
	noise_y.button_pressed = bool(RH.get_field("noise_y", true))
	noise_z.button_pressed = bool(RH.get_field("noise_z", true))
	_select_target_option(RH.target())
	_select_driver(scale_source, str(RH.get_field("scale_source", "bass")))
	_select_driver(emission_source, str(RH.get_field("emission_source", "mids")))
	_select_driver(rotation_source, str(RH.get_field("rotation_source", "highs")))
	_select_driver(light_source, str(RH.get_field("light_source", "energy")))
	_select_driver(noise_source, str(RH.get_field("noise_source", "bass")))
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
	scale_amount_spin.value_changed.connect(_on_scale_amount)
	rotation_amount_spin.value_changed.connect(_on_rotation_amount)
	affect_scale.toggled.connect(_on_affect_scale)
	scale_x.toggled.connect(func(v: bool) -> void: RH.set_field("scale_x", v))
	scale_y.toggled.connect(func(v: bool) -> void: RH.set_field("scale_y", v))
	scale_z.toggled.connect(func(v: bool) -> void: RH.set_field("scale_z", v))
	affect_light.toggled.connect(_on_affect_light)
	affect_emission.toggled.connect(_on_affect_emission)
	affect_rotation.toggled.connect(_on_affect_rotation)
	affect_noise.toggled.connect(_on_affect_noise)
	rotation_x.toggled.connect(func(v: bool) -> void: RH.set_field("rotation_x", v))
	rotation_y.toggled.connect(func(v: bool) -> void: RH.set_field("rotation_y", v))
	rotation_z.toggled.connect(func(v: bool) -> void: RH.set_field("rotation_z", v))
	scale_source.item_selected.connect(func(i: int) -> void: RH.set_field("scale_source", DRIVER_IDS[i]))
	emission_source.item_selected.connect(func(i: int) -> void: RH.set_field("emission_source", DRIVER_IDS[i]))
	rotation_source.item_selected.connect(func(i: int) -> void: RH.set_field("rotation_source", DRIVER_IDS[i]))
	light_source.item_selected.connect(func(i: int) -> void: RH.set_field("light_source", DRIVER_IDS[i]))
	noise_source.item_selected.connect(func(i: int) -> void: RH.set_field("noise_source", DRIVER_IDS[i]))
	noise_target.item_selected.connect(_on_noise_target_selected)
	noise_amount.value_changed.connect(func(v: float) -> void: RH.set_field("noise_amount", v))
	noise_scale.value_changed.connect(func(v: float) -> void: RH.set_field("noise_scale", v))
	noise_x.toggled.connect(func(v: bool) -> void: RH.set_field("noise_x", v))
	noise_y.toggled.connect(func(v: bool) -> void: RH.set_field("noise_y", v))
	noise_z.toggled.connect(func(v: bool) -> void: RH.set_field("noise_z", v))
	scale_schedule.toggled.connect(func(v: bool) -> void: _on_react_schedule("scale", v))
	light_schedule.toggled.connect(func(v: bool) -> void: _on_react_schedule("light", v))
	emission_schedule.toggled.connect(func(v: bool) -> void: _on_react_schedule("emission", v))
	rotation_schedule.toggled.connect(func(v: bool) -> void: _on_react_schedule("rotation", v))
	noise_schedule.toggled.connect(func(v: bool) -> void: _on_react_schedule("noise", v))
	camera_preset.item_selected.connect(_on_camera_preset)
	camera_rate.value_changed.connect(func(v: float) -> void: RH.set_field("camera_rate", v / 20.0))
	camera_depth.value_changed.connect(func(v: float) -> void: RH.set_field("camera_depth", v / 100.0))
	target_option.item_selected.connect(_on_target_selected)

	play_all_toggle.toggled.connect(_on_play_all_toggled)
	style_switch_toggle.toggled.connect(_on_style_switch_toggled)
	style_interval_slider.value_changed.connect(_on_style_interval)
	style_jitter_toggle.toggled.connect(_on_style_jitter)

	ascii_toggle.toggled.connect(_on_ascii_toggled)
	ascii_drive.item_selected.connect(func(_i: int) -> void:
		_sync_ascii_lfo_ui()
		_refresh_effect_if_on("ascii")
	)
	ascii_preset.item_selected.connect(_on_ascii_preset)
	ascii_invert.toggled.connect(_on_ascii_invert)
	ascii_density_random.toggled.connect(_on_density_random_toggled)
	ascii_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("ascii", v))

	particles_toggle.toggled.connect(_on_particles_toggled)
	particles_drive.item_selected.connect(func(_i: int) -> void: _refresh_effect_if_on("particles"))
	particles_target.item_selected.connect(_on_particles_target_selected)
	particles_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("particles", v))

	feedback_toggle.toggled.connect(_on_feedback_toggled)
	feedback_drive.item_selected.connect(_on_feedback_drive_changed)
	feedback_mix_slider.value_changed.connect(_on_feedback_params)
	feedback_persist_slider.value_changed.connect(_on_feedback_params)
	feedback_sens_slider.value_changed.connect(_on_feedback_params)
	feedback_lfo_rate.value_changed.connect(_on_feedback_lfo_rate)
	feedback_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("feedback", v))

	glitch_toggle.toggled.connect(_on_glitch_toggled)
	glitch_drive.item_selected.connect(func(_i: int) -> void: _refresh_effect_if_on("glitch"))
	glitch_amount_slider.value_changed.connect(_on_glitch_params)
	glitch_speed_slider.value_changed.connect(_on_glitch_params)
	glitch_hsize_slider.value_changed.connect(_on_glitch_params)
	glitch_rgb_slider.value_changed.connect(_on_glitch_params)
	glitch_chaos_slider.value_changed.connect(_on_glitch_params)
	glitch_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("glitch", v))

	chromatic_toggle.toggled.connect(_on_chromatic_toggled)
	chromatic_drive.item_selected.connect(func(_i: int) -> void: _refresh_effect_if_on("chromatic"))
	chromatic_amount_slider.value_changed.connect(_on_chromatic_params)
	chromatic_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("chromatic", v))

	pixel_sort_toggle.toggled.connect(_on_pixel_sort_toggled)
	pixel_sort_drive.item_selected.connect(func(_i: int) -> void: _refresh_effect_if_on("pixel_sort"))
	pixel_sort_amount_slider.value_changed.connect(_on_pixel_sort_params)
	pixel_sort_threshold_slider.value_changed.connect(_on_pixel_sort_params)
	pixel_sort_stretch_slider.value_changed.connect(_on_pixel_sort_params)
	pixel_sort_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("pixel_sort", v))

	wireframe_toggle.toggled.connect(_on_wireframe_toggled)
	wireframe_drive.item_selected.connect(func(_i: int) -> void: _refresh_effect_if_on("wireframe"))
	wireframe_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("wireframe", v))

	_setup_dual_ranges()
	_setup_ascii_lfo_controls()
	ShowDirector.show_loaded.connect(func(_n: String) -> void: _rebuild_cues())
	ShowDirector.effect_style_advanced.connect(_on_style_advanced_ui)
	ShowDirector.fx_automation.density_randomize_tick.connect(_on_density_random_tick)
	AudioAnalyzer.state_updated.connect(_on_audio)
	AudioAnalyzer.master_intensity = intensity_slider.value
	# Band sensitivity UI 1–20 maps into analyzer; default mid keeps headroom.
	AudioAnalyzer.band_sensitivity = sensitivity_slider.value * 0.35
	sensitivity_slider.value_changed.connect(func(v: float) -> void: AudioAnalyzer.band_sensitivity = v * 0.35)
	_rebuild_cues()
	_sync_conditional_ui()
	_sync_feedback_mode_ui()
	_sync_ascii_lfo_ui()


func _setup_ascii_lfo_controls() -> void:
	_ascii_lfo_wave_label = Label.new()
	_ascii_lfo_wave_label.text = "Density LFO wave"
	ascii_body.add_child(_ascii_lfo_wave_label)
	ascii_body.move_child(_ascii_lfo_wave_label, ascii_drive.get_index() + 1)
	_ascii_lfo_wave = OptionButton.new()
	for label in ASCII_LFO_WAVE_LABELS:
		_ascii_lfo_wave.add_item(label)
	_ascii_lfo_wave.select(0)
	_ascii_lfo_wave.item_selected.connect(func(_i: int) -> void: _refresh_effect_if_on("ascii"))
	ascii_body.add_child(_ascii_lfo_wave)
	ascii_body.move_child(_ascii_lfo_wave, _ascii_lfo_wave_label.get_index() + 1)
	_ascii_lfo_rate_label = Label.new()
	_ascii_lfo_rate_label.text = "Density LFO rate (Hz)"
	ascii_body.add_child(_ascii_lfo_rate_label)
	ascii_body.move_child(_ascii_lfo_rate_label, _ascii_lfo_wave.get_index() + 1)
	_ascii_lfo_rate = HSlider.new()
	_ascii_lfo_rate.min_value = 0.05
	_ascii_lfo_rate.max_value = 4.0
	_ascii_lfo_rate.step = 0.05
	_ascii_lfo_rate.value = 0.45
	_ascii_lfo_rate.value_changed.connect(func(_v: float) -> void: _refresh_effect_if_on("ascii"))
	ascii_body.add_child(_ascii_lfo_rate)
	ascii_body.move_child(_ascii_lfo_rate, _ascii_lfo_rate_label.get_index() + 1)


func _setup_dual_ranges() -> void:
	_density_range = DualRangeSliderScr.new()
	_density_range.min_value = 1.0
	_density_range.max_value = 200.0
	_density_range.step = 1.0
	_density_range.set_range_values(ascii_density_min.value, ascii_density_max.value)
	_user_density_min = ascii_density_min.value
	_user_density_max = ascii_density_max.value
	_density_range.range_changed.connect(_on_density_range_changed)
	ascii_density_host.add_child(_density_range)

	var play_lbl := Label.new()
	play_lbl.text = "Default schedule"
	play_all_body.add_child(play_lbl)
	_play_schedule_range = ScheduleSecondsPairScr.new()
	_play_schedule_range.min_value = 1.0
	_play_schedule_range.max_value = 60.0
	_play_schedule_range.step = 1.0
	_play_schedule_range.set_range_values(4.0, 4.0)
	_play_schedule_range.range_changed.connect(_on_play_schedule_range)
	play_all_body.add_child(_play_schedule_range)

	var hosts := {
		"ascii": ascii_schedule_host,
		"particles": particles_schedule_host,
		"feedback": feedback_schedule_host,
		"glitch": glitch_schedule_host,
		"chromatic": chromatic_schedule_host,
		"pixel_sort": pixel_sort_schedule_host,
		"wireframe": wireframe_schedule_host,
		"react_scale": scale_schedule_host,
		"react_light": light_schedule_host,
		"react_emission": emission_schedule_host,
		"react_rotation": rotation_schedule_host,
		"react_noise": noise_schedule_host,
	}
	for eid in hosts.keys():
		var host: VBoxContainer = hosts[eid]
		var rs = ScheduleSecondsPairScr.new()
		rs.min_value = 1.0
		rs.max_value = 60.0
		rs.step = 1.0
		rs.set_range_values(4.0, 4.0)
		var captured := str(eid)
		rs.range_changed.connect(func(a: float, i: float) -> void: _on_effect_schedule_range(captured, a, i))
		host.add_child(rs)
		_schedule_ranges[eid] = rs
		host.custom_minimum_size = Vector2(0, 96)


func _fill_driver(opt: OptionButton) -> void:
	opt.clear()
	for label in DRIVER_LABELS:
		opt.add_item(label)


func _fill_fx_drive(opt: OptionButton) -> void:
	opt.clear()
	for label in FX_DRIVE_LABELS:
		opt.add_item(label)
	opt.select(0)


func _fx_drive_mode(opt: OptionButton) -> String:
	var i := opt.selected
	if i < 0 or i >= FX_DRIVE_IDS.size():
		return "audio"
	return FX_DRIVE_IDS[i]


func _refresh_effect_if_on(effect_id: String) -> void:
	match effect_id:
		"ascii":
			if ascii_toggle.button_pressed:
				ShowDirector.set_effect("ascii", true, _ascii_params())
		"particles":
			if particles_toggle.button_pressed:
				_on_particles_toggled(true)
		"feedback":
			if feedback_toggle.button_pressed:
				ShowDirector.set_effect("feedback", true, _feedback_params())
		"glitch":
			if glitch_toggle.button_pressed:
				ShowDirector.set_effect("glitch", true, _glitch_params())
		"chromatic":
			if chromatic_toggle.button_pressed:
				ShowDirector.set_effect("chromatic", true, _chromatic_params())
		"pixel_sort":
			if pixel_sort_toggle.button_pressed:
				ShowDirector.set_effect("pixel_sort", true, _pixel_sort_params())
		"wireframe":
			if wireframe_toggle.button_pressed:
				ShowDirector.set_effect("wireframe", true, _wireframe_params())


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
	scale_schedule.visible = scale_on
	scale_schedule_host.visible = scale_on and scale_schedule.button_pressed

	var light_on := react_on and affect_light.button_pressed
	light_source.visible = light_on
	light_schedule.visible = light_on
	light_schedule_host.visible = light_on and light_schedule.button_pressed

	var emission_on := react_on and affect_emission.button_pressed
	emission_source.visible = emission_on
	emission_schedule.visible = emission_on
	emission_schedule_host.visible = emission_on and emission_schedule.button_pressed

	var rotation_on := react_on and affect_rotation.button_pressed
	rotation_source.visible = rotation_on
	$Margin/Scroll/Column/Targets/RotationAmountLabel.visible = rotation_on
	rotation_amount_spin.visible = rotation_on
	$Margin/Scroll/Column/Targets/RotationAxisRow.visible = rotation_on
	rotation_schedule.visible = rotation_on
	rotation_schedule_host.visible = rotation_on and rotation_schedule.button_pressed

	var noise_on := react_on and affect_noise.button_pressed
	noise_source.visible = noise_on
	$Margin/Scroll/Column/Targets/NoiseTargetLabel.visible = noise_on
	noise_target.visible = noise_on
	$Margin/Scroll/Column/Targets/NoiseAmountLabel.visible = noise_on
	noise_amount.visible = noise_on
	$Margin/Scroll/Column/Targets/NoiseScaleLabel.visible = noise_on
	noise_scale.visible = noise_on
	$Margin/Scroll/Column/Targets/NoiseAxisRow.visible = noise_on
	noise_schedule.visible = noise_on
	noise_schedule_host.visible = noise_on and noise_schedule.button_pressed

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
	wireframe_body.visible = wireframe_toggle.button_pressed
	play_all_body.visible = play_all_toggle.button_pressed
	ascii_schedule_host.visible = ascii_toggle.button_pressed and ascii_schedule.button_pressed
	particles_schedule_host.visible = particles_toggle.button_pressed and particles_schedule.button_pressed
	feedback_schedule_host.visible = feedback_toggle.button_pressed and feedback_schedule.button_pressed
	glitch_schedule_host.visible = glitch_toggle.button_pressed and glitch_schedule.button_pressed
	chromatic_schedule_host.visible = chromatic_toggle.button_pressed and chromatic_schedule.button_pressed
	pixel_sort_schedule_host.visible = pixel_sort_toggle.button_pressed and pixel_sort_schedule.button_pressed
	wireframe_schedule_host.visible = wireframe_toggle.button_pressed and wireframe_schedule.button_pressed
	_sync_feedback_mode_ui()
	_sync_ascii_lfo_ui()

	cue_container.get_parent().visible = cue_container.get_child_count() > 0


func _sync_ascii_lfo_ui() -> void:
	var show_lfo := ascii_toggle.button_pressed and _fx_drive_mode(ascii_drive) == "lfo"
	if _ascii_lfo_wave_label:
		_ascii_lfo_wave_label.visible = show_lfo
	if _ascii_lfo_wave:
		_ascii_lfo_wave.visible = show_lfo
	if _ascii_lfo_rate_label:
		_ascii_lfo_rate_label.visible = show_lfo
	if _ascii_lfo_rate:
		_ascii_lfo_rate.visible = show_lfo


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
		ShowDirector.set_effect("particles", true, {
			"intensity": intensity_slider.value,
			"target": t,
			"drive_mode": _fx_drive_mode(particles_drive),
		})


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


func _on_rotation_amount(value: float) -> void:
	RH.set_rotation_amount(value)


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
	var dmin := _user_density_min
	var dmax := _user_density_max
	if _density_range:
		dmin = _density_range.get_low()
		dmax = _density_range.get_high()
	if dmin > dmax:
		var tmp := dmin
		dmin = dmax
		dmax = tmp
	params["density_min"] = dmin
	params["density_max"] = dmax
	params["density"] = lerpf(dmin, dmax, 0.5)
	params["invert"] = ascii_invert.button_pressed
	params["drive_mode"] = _fx_drive_mode(ascii_drive)
	if _ascii_lfo_wave:
		var wi := _ascii_lfo_wave.selected
		params["lfo_wave"] = ASCII_LFO_WAVE_IDS[wi] if wi >= 0 and wi < ASCII_LFO_WAVE_IDS.size() else "sine"
	if _ascii_lfo_rate:
		params["lfo_rate"] = float(_ascii_lfo_rate.value)
	return params


func _on_ascii_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("ascii", enabled, _ascii_params())
	_sync_conditional_ui()


func _on_ascii_preset(index: int) -> void:
	## Manual preset pick may update density; Style Switch must NOT (handled in _on_style_advanced_ui).
	if _syncing_ui:
		return
	var preset_name := ascii_preset.get_item_text(index)
	var params: Dictionary = AsciiEffect.PRESETS[preset_name].duplicate()
	if not ascii_density_random.button_pressed:
		var dens := float(params.get("density", 80.0))
		_user_density_min = maxf(1.0, dens * 0.65)
		_user_density_max = dens
		if _density_range:
			_density_range.set_range_values(_user_density_min, _user_density_max)
		ascii_density_min.value = _user_density_min
		ascii_density_max.value = _user_density_max
	params["invert"] = ascii_invert.button_pressed
	params["density_min"] = _density_range.get_low() if _density_range else _user_density_min
	params["density_max"] = _density_range.get_high() if _density_range else _user_density_max
	params["drive_mode"] = _fx_drive_mode(ascii_drive)
	if ascii_toggle.button_pressed:
		ShowDirector.set_effect("ascii", true, params)


func _on_density_range_changed(lo: float, hi: float) -> void:
	if ascii_density_random.button_pressed and not _syncing_ui:
		# User dragged while random on — treat as new baseline.
		pass
	if not ascii_density_random.button_pressed:
		_user_density_min = lo
		_user_density_max = hi
	ascii_density_min.value = lo
	ascii_density_max.value = hi
	if ascii_toggle.button_pressed:
		ShowDirector.set_effect("ascii", true, _ascii_params())


func _on_density_random_toggled(on: bool) -> void:
	ShowDirector.fx_automation.set_density_random(on)
	if not on and _density_range:
		_syncing_ui = true
		_density_range.set_range_values(_user_density_min, _user_density_max)
		_syncing_ui = false
		if ascii_toggle.button_pressed:
			ShowDirector.set_effect("ascii", true, _ascii_params())


func _on_density_random_tick() -> void:
	if not ascii_density_random.button_pressed or _density_range == null:
		return
	var a := float(randi_range(1, 160))
	var b := float(randi_range(int(a), 200))
	_syncing_ui = true
	_density_range.set_range_values(a, b)
	_syncing_ui = false
	ascii_density_min.value = a
	ascii_density_max.value = b
	if ascii_toggle.button_pressed:
		ShowDirector.set_effect("ascii", true, _ascii_params())


func _on_ascii_invert(enabled: bool) -> void:
	if ascii_toggle.button_pressed:
		var params := _ascii_params()
		params["invert"] = enabled
		ShowDirector.set_effect("ascii", true, params)


func _on_particles_toggled(enabled: bool) -> void:
	var t := str(RH.get_field("particles_target", "all"))
	ShowDirector.set_effect("particles", enabled, {
		"intensity": intensity_slider.value,
		"target": t,
		"drive_mode": _fx_drive_mode(particles_drive),
	})
	_sync_conditional_ui()


func _feedback_params() -> Dictionary:
	return {
		"intensity": 1.0,
		"mix_amount": feedback_mix_slider.value / 100.0,
		"persistence": feedback_persist_slider.value / 100.0,
		"drive_mode": _fx_drive_mode(feedback_drive),
		"audio_sensitivity": feedback_sens_slider.value / 100.0,
	}


func _on_feedback_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("feedback", enabled, _feedback_params())
	_sync_conditional_ui()
	_sync_feedback_mode_ui()


func _on_feedback_params(_v: float = 0.0) -> void:
	if feedback_toggle.button_pressed:
		ShowDirector.set_effect("feedback", true, _feedback_params())


func _on_feedback_drive_changed(_i: int = 0) -> void:
	_sync_feedback_mode_ui()
	_refresh_effect_if_on("feedback")


func _on_feedback_lfo_rate(v: float) -> void:
	# Shared LFO rate also drives camera when a preset is on — keep usable for FX LFO.
	RH.set_field("camera_rate", clampf(v / 20.0, 0.05, 5.0))
	camera_rate.value = v
	_refresh_effect_if_on("feedback")


func _sync_feedback_mode_ui() -> void:
	if feedback_sens_slider == null:
		return
	var mode := _fx_drive_mode(feedback_drive)
	var audio_on := mode == "audio"
	var lfo_on := mode == "lfo"
	feedback_sens_slider.visible = audio_on
	$Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackSensLabel.visible = audio_on
	feedback_lfo_rate.visible = lfo_on
	$Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackLfoRateLabel.visible = lfo_on
	# Mix/persistence always editable — Auto applies them directly.
	feedback_mix_slider.visible = true
	feedback_persist_slider.visible = true


func _glitch_params() -> Dictionary:
	# UI 1–100 → strong shader drive (28 ≈ 1.0, 100 ≈ 3.5)
	return {
		"intensity": glitch_amount_slider.value / 28.0,
		"rate": glitch_speed_slider.value / 3.0,
		"h_size": glitch_hsize_slider.value / 100.0,
		"rgb_split": glitch_rgb_slider.value / 100.0,
		"slice_chaos": glitch_chaos_slider.value / 100.0,
		"drive_mode": _fx_drive_mode(glitch_drive),
	}


func _on_glitch_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("glitch", enabled, _glitch_params())
	_sync_conditional_ui()


func _on_glitch_params(_v: float = 0.0) -> void:
	if glitch_toggle.button_pressed:
		ShowDirector.set_effect("glitch", true, _glitch_params())


func _chromatic_params() -> Dictionary:
	return {
		"intensity": 1.0,
		"amount": chromatic_amount_slider.value / 28.0,
		"drive_mode": _fx_drive_mode(chromatic_drive),
	}


func _on_chromatic_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("chromatic", enabled, _chromatic_params())
	_sync_conditional_ui()


func _on_chromatic_params(_v: float = 0.0) -> void:
	if chromatic_toggle.button_pressed:
		ShowDirector.set_effect("chromatic", true, _chromatic_params())


func _pixel_sort_params() -> Dictionary:
	return {
		"intensity": pixel_sort_amount_slider.value / 35.0,
		"threshold": pixel_sort_threshold_slider.value / 100.0,
		"stretch": pixel_sort_stretch_slider.value / 100.0,
		"drive_mode": _fx_drive_mode(pixel_sort_drive),
	}


func _on_pixel_sort_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("pixel_sort", enabled, _pixel_sort_params())
	_sync_conditional_ui()


func _on_pixel_sort_params(_v: float = 0.0) -> void:
	if pixel_sort_toggle.button_pressed:
		ShowDirector.set_effect("pixel_sort", true, _pixel_sort_params())


func _wireframe_params() -> Dictionary:
	return {
		"intensity": 1.0,
		"drive_mode": _fx_drive_mode(wireframe_drive),
	}


func _on_wireframe_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("wireframe", enabled, _wireframe_params())
	_sync_conditional_ui()


func _on_effect_schedule(effect_id: String, on: bool) -> void:
	var active := 6.0
	var inactive := 6.0
	if _schedule_ranges.has(effect_id):
		var rs = _schedule_ranges[effect_id]
		active = float(rs.get_active())
		inactive = float(rs.get_inactive())
	elif _play_schedule_range:
		active = float(_play_schedule_range.get_active())
		inactive = float(_play_schedule_range.get_inactive())
	ShowDirector.fx_automation.set_gate_active_inactive(effect_id, active, inactive)
	ShowDirector.fx_automation.set_gate_enabled(effect_id, on)
	ShowDirector.refresh_effect(effect_id)
	_sync_conditional_ui()


func _on_react_schedule(property: String, on: bool) -> void:
	## Reactivity drives use react_<property> gate ids (same Active/Inactive model as post FX).
	var gate_id := RH.schedule_gate_id(property)
	var active := 6.0
	var inactive := 6.0
	if _schedule_ranges.has(gate_id):
		var rs = _schedule_ranges[gate_id]
		active = float(rs.get_active())
		inactive = float(rs.get_inactive())
	ShowDirector.fx_automation.set_gate_active_inactive(gate_id, active, inactive)
	ShowDirector.fx_automation.set_gate_enabled(gate_id, on)
	_sync_conditional_ui()


func _on_effect_schedule_range(effect_id: String, active: float, inactive: float) -> void:
	ShowDirector.fx_automation.set_gate_active_inactive(effect_id, active, inactive)
	if ShowDirector.fx_automation.is_gate_enabled(effect_id):
		# Post FX refresh; reactivity gates are read live via RH.property_active.
		if not str(effect_id).begins_with("react_"):
			ShowDirector.refresh_effect(effect_id)


func _on_play_schedule_range(active: float, inactive: float) -> void:
	for eid in FX_IDS:
		ShowDirector.fx_automation.set_gate_active_inactive(eid, active, inactive)
		if _schedule_ranges.has(eid):
			_schedule_ranges[eid].set_range_values(active, inactive)
		if ShowDirector.fx_automation.is_gate_enabled(eid):
			ShowDirector.refresh_effect(eid)
	# Also push onto any enabled reactivity schedules.
	for prop in ["scale", "light", "emission", "rotation", "noise"]:
		var gid := RH.schedule_gate_id(prop)
		if ShowDirector.fx_automation.is_gate_enabled(gid):
			ShowDirector.fx_automation.set_gate_active_inactive(gid, active, inactive)
			if _schedule_ranges.has(gid):
				_schedule_ranges[gid].set_range_values(active, inactive)


func _on_play_all_toggled(on: bool) -> void:
	_sync_conditional_ui()
	if on:
		# Bootstrap something meaningful if nothing is enabled yet.
		if not ascii_toggle.button_pressed \
				and not particles_toggle.button_pressed \
				and not feedback_toggle.button_pressed \
				and not glitch_toggle.button_pressed \
				and not chromatic_toggle.button_pressed \
				and not pixel_sort_toggle.button_pressed \
				and not wireframe_toggle.button_pressed:
			ascii_toggle.button_pressed = true
		var active: float = float(_play_schedule_range.get_active()) if _play_schedule_range else 4.0
		var inactive: float = float(_play_schedule_range.get_inactive()) if _play_schedule_range else 4.0
		# Enable schedules on every currently-on effect (and sync Active/Inactive sliders).
		var pairs := [
			[ascii_toggle, ascii_schedule, "ascii"],
			[particles_toggle, particles_schedule, "particles"],
			[feedback_toggle, feedback_schedule, "feedback"],
			[glitch_toggle, glitch_schedule, "glitch"],
			[chromatic_toggle, chromatic_schedule, "chromatic"],
			[pixel_sort_toggle, pixel_sort_schedule, "pixel_sort"],
			[wireframe_toggle, wireframe_schedule, "wireframe"],
		]
		var enabled_ids: Array = []
		_syncing_ui = true
		for sid in pairs:
			var master: CheckButton = sid[0]
			var sched: CheckButton = sid[1]
			var eid: String = str(sid[2])
			if master.button_pressed:
				enabled_ids.append(eid)
				sched.button_pressed = true
				if _schedule_ranges.has(eid):
					_schedule_ranges[eid].set_range_values(active, inactive)
				ShowDirector.fx_automation.set_gate_active_inactive(eid, active, inactive)
				ShowDirector.fx_automation.set_gate_enabled(eid, true)
		if ascii_toggle.button_pressed:
			style_switch_toggle.button_pressed = true
		_syncing_ui = false
		# Apply style + gates explicitly (UI toggles may no-op under _syncing_ui).
		ShowDirector.fx_automation.set_style_interval(style_interval_slider.value)
		ShowDirector.fx_automation.set_style_jitter(style_jitter_toggle.button_pressed)
		ShowDirector.fx_automation.set_style_active(ascii_toggle.button_pressed)
		ShowDirector.set_play_all_effects(true, active + inactive, active)
		for eid2 in enabled_ids:
			ShowDirector.refresh_effect(str(eid2))
		_sync_conditional_ui()
	else:
		ShowDirector.set_play_all_effects(false)
		_syncing_ui = true
		ascii_schedule.button_pressed = false
		particles_schedule.button_pressed = false
		feedback_schedule.button_pressed = false
		glitch_schedule.button_pressed = false
		chromatic_schedule.button_pressed = false
		pixel_sort_schedule.button_pressed = false
		wireframe_schedule.button_pressed = false
		style_switch_toggle.button_pressed = false
		_syncing_ui = false
		ShowDirector.fx_automation.set_style_active(false)
		for eid3 in FX_IDS:
			ShowDirector.fx_automation.set_gate_enabled(eid3, false)
			ShowDirector.refresh_effect(eid3)
		_sync_conditional_ui()


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
	## Cycle charset/style only — never touch user density min/max.
	_syncing_ui = true
	for i in ascii_preset.item_count:
		if ascii_preset.get_item_text(i) == preset_name:
			ascii_preset.select(i)
			break
	_syncing_ui = false
	if ascii_toggle.button_pressed:
		ShowDirector.set_effect("ascii", true, _ascii_params())


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
