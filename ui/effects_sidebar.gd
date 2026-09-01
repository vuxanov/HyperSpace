extends PanelContainer

## Right sidebar — effects stack + Drivers (expressions, analyzer EQ).
## Parameter bodies stay hidden until their effect toggle is ON (ASCII Live Visuals pattern).

const RH = preload("res://core/reactivity_hub.gd")
const DualRangeSliderScr = preload("res://ui/dual_range_slider.gd")
const ScheduleSecondsPairScr = preload("res://ui/schedule_seconds_pair.gd")
const SliderSpinLinkScr = preload("res://ui/slider_spin_link.gd")
const DriverExprScr = preload("res://core/driver_expr.gd")
const DriverHubScr = preload("res://autoload/driver_hub.gd")
const CycleRandomScr = preload("res://ui/cycle_random.gd")
const FxPresetStoreScr = preload("res://core/fx_preset_store.gd")

const DRIVER_IDS := ["off", "bass", "mids", "highs", "kick", "energy", "lfo"]
const DRIVER_LABELS := ["Off", "Bass", "Mids", "Highs", "Kick", "Energy", "LFO"]
const FX_DRIVE_IDS := ["audio", "lfo", "auto"]
const FX_DRIVE_LABELS := ["Audio", "LFO", "Static"]
const FX_DRIVE_TOOLTIPS := [
	"Live audio. Audio amount scales how hard this effect reacts.",
	"Oscillator. Rate (Hz) and Depth control the wave.",
	"Hold sliders as set — no audio or LFO. Schedules can still turn the effect on and off.",
]
const ASCII_LFO_WAVE_IDS := ["sine", "triangle", "saw", "square"]
const ASCII_LFO_WAVE_LABELS := ["Sine", "Triangle", "Saw", "Square"]
const CAMERA_PRESETS := ["Off", "Walk", "Pitch rock", "Roll bank", "Orbit tumble", "Spiral twist", "Kick snap"]
const FX_IDS := ["ascii", "feedback", "glitch", "chromatic", "tone", "hole", "wireframe", "point_cloud", "camera_fx", "material_override", "fog"]
const HOLE_SHAPE_NAMES := ["Circular", "Rectangle"]
const MAT_OVERRIDE_LOOK_NAMES := ["White cladding", "Chrome", "Gold", "Normal", "Shiny black"]
## How the previous frame is composited onto the live one. Order must match the shader's
## BLEND_* constants and FeedbackEffect.BLEND_NAMES. Normal is the pre-selector look.
const FEEDBACK_BLEND_NAMES := ["Normal", "Brightest", "Darkest", "Edges", "Contrast"]
const FEEDBACK_DEFAULT_OPACITY := 100.0
const FEEDBACK_DEFAULT_PERSISTENCE := 100.0
const FEEDBACK_DEFAULT_BLUR := 20.0
const FEEDBACK_DEFAULT_BLEND := "Edges"

## One flat effect list: an effect row is prominent, its settings body is indented and quieter.
const FX_HEADER_FONT_SIZE := 15
const FX_CONTROL_FONT_SIZE := 14
const FX_HEADER_COLOR := Color(0.94, 0.96, 0.99)
const FX_SETTING_FONT_SIZE := 11
const FX_SETTING_LABEL_COLOR := Color(0.70, 0.75, 0.81)
const FX_SETTING_INDENT := 16
const FX_SETTING_PAD := 6
const FX_SETTING_BG := Color(1.0, 1.0, 1.0, 0.026)
const FX_SETTING_RULE := Color(0.45, 0.95, 0.7, 0.34)


@onready var reactivity_toggle: CheckButton = $Margin/Scroll/Column/AudioSection/ReactivityToggle
@onready var reactivity_body: VBoxContainer = $Margin/Scroll/Column/AudioSection/ReactivityBody
@onready var input_device_option: OptionButton = $Margin/Scroll/Column/AudioSection/ReactivityBody/InputDeviceRow/InputDeviceOption
@onready var refresh_devices_btn: Button = $Margin/Scroll/Column/AudioSection/ReactivityBody/InputDeviceRow/RefreshDevicesBtn
@onready var capture_status_label: Label = $Margin/Scroll/Column/AudioSection/ReactivityBody/CaptureStatusLabel
var _audio_source_ids: PackedStringArray = PackedStringArray()
@onready var input_level_bar: ProgressBar = $Margin/Scroll/Column/AudioSection/ReactivityBody/InputLevelBar
@onready var spectrum_bars: HBoxContainer = $Margin/Scroll/Column/AudioSection/ReactivityBody/SpectrumBars
@onready var intensity_slider: HSlider = $Margin/Scroll/Column/AudioSection/ReactivityBody/IntensitySlider
@onready var sensitivity_slider: HSlider = $Margin/Scroll/Column/AudioSection/ReactivityBody/SensitivitySlider
@onready var noise_floor_slider: HSlider = $Margin/Scroll/Column/AudioSection/ReactivityBody/NoiseFloorSlider
@onready var scale_amount_spin: SpinBox = $Margin/Scroll/Column/AudioSection/ReactivityBody/ScaleAmountSpin
@onready var energy_bar: ProgressBar = $Margin/Scroll/Column/AudioSection/ReactivityBody/EnergyBar
@onready var bass_bar: ProgressBar = $Margin/Scroll/Column/AudioSection/ReactivityBody/BassBar
@onready var mids_bar: ProgressBar = $Margin/Scroll/Column/AudioSection/ReactivityBody/MidsBar
@onready var highs_bar: ProgressBar = $Margin/Scroll/Column/AudioSection/ReactivityBody/HighsBar
@onready var reset_defaults_btn: Button = $Margin/Scroll/Column/ResetDefaultsBtn
var _preset_actions: HBoxContainer
var save_preset_btn: Button
## Auto Mode body hosts Presets | Play All radios; only one branch drives FX.
var play_all_settings: VBoxContainer
var auto_mode_presets_radio: CheckBox
var auto_mode_play_all_radio: CheckBox
var _auto_mode_group: ButtonGroup
var play_preset_body: VBoxContainer
var play_preset_menu: OptionButton
var _preset_dialog: AcceptDialog
var _preset_name: LineEdit
var _preset_manager_dialog: AcceptDialog
var _preset_manager_list: VBoxContainer
var _preset_delete_dialog: ConfirmationDialog
var _preset_delete_key: String = ""
var _preset_menu_busy: bool = false
var _auto_mode_branch_busy: bool = false
const EDIT_PRESETS_MENU_ITEM := "Edit presets…"

var _spectrum_bar_nodes: Array[ColorRect] = []
var _input_level_fill: ColorRect = null
const SPECTRUM_BAR_H := 64.0
const SPECTRUM_BAR_COLOR := Color(0.45, 0.95, 0.7, 0.95)
const SPECTRUM_BAR_BG := Color(0.12, 0.14, 0.16, 0.9)

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
@onready var rotation_target_row: HBoxContainer = $Margin/Scroll/Column/Targets/RotationTargetRow
@onready var rotation_target_main: CheckButton = $Margin/Scroll/Column/Targets/RotationTargetRow/RotationTargetMain
@onready var rotation_target_scatter: CheckButton = $Margin/Scroll/Column/Targets/RotationTargetRow/RotationTargetScatter
@onready var rotation_target_environment: CheckButton = $Margin/Scroll/Column/Targets/RotationTargetRow/RotationTargetEnvironment
@onready var rotation_target_lights: CheckButton = $Margin/Scroll/Column/Targets/RotationTargetRow/RotationTargetLights
@onready var rotation_target_camera: CheckButton = $Margin/Scroll/Column/Targets/RotationTargetRow/RotationTargetCamera
@onready var rotation_amount_spin: SpinBox = $Margin/Scroll/Column/Targets/RotationAmountSpin
@onready var rotation_x: CheckButton = $Margin/Scroll/Column/Targets/RotationAxisRow/RotationX
@onready var rotation_y: CheckButton = $Margin/Scroll/Column/Targets/RotationAxisRow/RotationY
@onready var rotation_z: CheckButton = $Margin/Scroll/Column/Targets/RotationAxisRow/RotationZ
@onready var rotation_schedule: CheckButton = $Margin/Scroll/Column/Targets/RotationSchedule
@onready var rotation_schedule_host: VBoxContainer = $Margin/Scroll/Column/Targets/RotationScheduleHost
@onready var affect_noise: CheckButton = $Margin/Scroll/Column/Targets/AffectNoise
@onready var noise_source: OptionButton = $Margin/Scroll/Column/Targets/NoiseSource
@onready var noise_target_row: HBoxContainer = $Margin/Scroll/Column/Targets/NoiseTargetRow
@onready var noise_target_main: CheckButton = $Margin/Scroll/Column/Targets/NoiseTargetRow/NoiseTargetMain
@onready var noise_target_scatter: CheckButton = $Margin/Scroll/Column/Targets/NoiseTargetRow/NoiseTargetScatter
@onready var noise_target_environment: CheckButton = $Margin/Scroll/Column/Targets/NoiseTargetRow/NoiseTargetEnvironment
@onready var noise_target_lights: CheckButton = $Margin/Scroll/Column/Targets/NoiseTargetRow/NoiseTargetLights
@onready var noise_amount: HSlider = $Margin/Scroll/Column/Targets/NoiseAmount
@onready var noise_scale: HSlider = $Margin/Scroll/Column/Targets/NoiseScale
@onready var noise_x: CheckButton = $Margin/Scroll/Column/Targets/NoiseAxisRow/NoiseX
@onready var noise_y: CheckButton = $Margin/Scroll/Column/Targets/NoiseAxisRow/NoiseY
@onready var noise_z: CheckButton = $Margin/Scroll/Column/Targets/NoiseAxisRow/NoiseZ
@onready var noise_schedule: CheckButton = $Margin/Scroll/Column/Targets/NoiseSchedule
@onready var noise_schedule_host: VBoxContainer = $Margin/Scroll/Column/Targets/NoiseScheduleHost
@onready var target_row: HBoxContainer = $Margin/Scroll/Column/Targets/TargetRow
@onready var target_main: CheckButton = $Margin/Scroll/Column/Targets/TargetRow/TargetMain
@onready var target_scatter: CheckButton = $Margin/Scroll/Column/Targets/TargetRow/TargetScatter
@onready var target_environment: CheckButton = $Margin/Scroll/Column/Targets/TargetRow/TargetEnvironment
@onready var target_lights: CheckButton = $Margin/Scroll/Column/Targets/TargetRow/TargetLights
@onready var camera_motion_toggle: CheckButton = $Margin/Scroll/Column/Targets/CameraMotionToggle
@onready var camera_body: VBoxContainer = $Margin/Scroll/Column/Targets/CameraBody
@onready var camera_preset: OptionButton = $Margin/Scroll/Column/Targets/CameraBody/CameraPreset
@onready var camera_rate: HSlider = $Margin/Scroll/Column/Targets/CameraBody/CameraRate
@onready var camera_depth: HSlider = $Margin/Scroll/Column/Targets/CameraBody/CameraDepth
@onready var camera_schedule: CheckButton = $Margin/Scroll/Column/Targets/CameraBody/CameraSchedule
@onready var camera_schedule_host: VBoxContainer = $Margin/Scroll/Column/Targets/CameraBody/CameraScheduleHost

@onready var play_all_toggle: CheckButton = $Margin/Scroll/Column/FxSection/PlayAllToggle
@onready var play_all_body: VBoxContainer = $Margin/Scroll/Column/FxSection/PlayAllBody
@onready var play_mode: OptionButton = $Margin/Scroll/Column/FxSection/PlayAllBody/PlayMode
@onready var play_audio_reactive: CheckButton = $Margin/Scroll/Column/FxSection/PlayAllBody/PlayAudioReactive

@onready var ascii_toggle: CheckButton = $Margin/Scroll/Column/FxSection/AsciiToggle
@onready var ascii_body: VBoxContainer = $Margin/Scroll/Column/FxSection/AsciiBody
@onready var ascii_drive: OptionButton = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiDrive
@onready var ascii_preset: OptionButton = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiPreset
@onready var ascii_density_min: HSlider = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiDensityMin
@onready var ascii_density_max: HSlider = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiDensityMax
@onready var ascii_density_random: CheckButton = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiDensityRandom
@onready var ascii_density_host: VBoxContainer = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiDensityRangeHost
@onready var ascii_density_label: Label = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiDensityLabel
@onready var ascii_invert: CheckButton = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiInvert
@onready var style_switch_toggle: CheckButton = $Margin/Scroll/Column/FxSection/AsciiBody/StyleSwitchToggle
@onready var style_switch_body: VBoxContainer = $Margin/Scroll/Column/FxSection/AsciiBody/StyleSwitchBody
@onready var style_interval_slider: HSlider = $Margin/Scroll/Column/FxSection/AsciiBody/StyleSwitchBody/StyleIntervalSlider
@onready var ascii_schedule: CheckButton = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiSchedule
@onready var ascii_schedule_host: VBoxContainer = $Margin/Scroll/Column/FxSection/AsciiBody/AsciiScheduleHost

var particles_toggle: CheckButton
var particles_body: VBoxContainer
var particles_drive: OptionButton
var particles_target_row: HBoxContainer
var particles_target_main: CheckButton
var particles_target_scatter: CheckButton
var particles_target_environment: CheckButton
var particles_target_lights: CheckButton
var particles_target_media: CheckButton
var particles_schedule: CheckButton
var particles_schedule_host: VBoxContainer

@onready var feedback_toggle: CheckButton = $Margin/Scroll/Column/FxSection/FeedbackToggle
@onready var feedback_body: VBoxContainer = $Margin/Scroll/Column/FxSection/FeedbackBody
@onready var feedback_drive: OptionButton = $Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackDrive
@onready var feedback_mix_slider: HSlider = $Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackMixSlider
@onready var feedback_persist_slider: HSlider = $Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackPersistSlider
@onready var feedback_sens_slider: HSlider = $Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackSensSlider
@onready var feedback_lfo_rate: HSlider = $Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackLfoRate
@onready var feedback_schedule: CheckButton = $Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackSchedule
@onready var feedback_schedule_host: VBoxContainer = $Margin/Scroll/Column/FxSection/FeedbackBody/FeedbackScheduleHost
var feedback_blur_slider: HSlider
var feedback_blend: OptionButton

@onready var glitch_toggle: CheckButton = $Margin/Scroll/Column/FxSection/GlitchToggle
@onready var glitch_body: VBoxContainer = $Margin/Scroll/Column/FxSection/GlitchBody
@onready var glitch_drive: OptionButton = $Margin/Scroll/Column/FxSection/GlitchBody/GlitchDrive
@onready var glitch_vsize_slider: HSlider = $Margin/Scroll/Column/FxSection/GlitchBody/GlitchVSizeSlider
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

var pixel_sort_toggle: CheckButton
var pixel_sort_body: VBoxContainer
var pixel_sort_drive: OptionButton
var pixel_sort_amount_slider: HSlider
var pixel_sort_threshold_slider: HSlider
var pixel_sort_stretch_slider: HSlider
var pixel_sort_schedule: CheckButton
var pixel_sort_schedule_host: VBoxContainer

@onready var wireframe_toggle: CheckButton = $Margin/Scroll/Column/FxSection/WireframeToggle
@onready var wireframe_body: VBoxContainer = $Margin/Scroll/Column/FxSection/WireframeBody
@onready var wireframe_drive: OptionButton = $Margin/Scroll/Column/FxSection/WireframeBody/WireframeDrive
@onready var wireframe_schedule: CheckButton = $Margin/Scroll/Column/FxSection/WireframeBody/WireframeSchedule
@onready var wireframe_schedule_host: VBoxContainer = $Margin/Scroll/Column/FxSection/WireframeBody/WireframeScheduleHost

var cloth_toggle: CheckButton
var cloth_body: VBoxContainer
var cloth_drive: OptionButton
var cloth_amount_slider: HSlider
var cloth_stiffness_slider: HSlider
var cloth_damping_slider: HSlider
var cloth_wind_slider: HSlider
var cloth_schedule: CheckButton
var cloth_schedule_host: VBoxContainer
var hole_toggle: CheckButton
var hole_body: VBoxContainer
var hole_shape: OptionButton
var hole_strength_slider: HSlider
var hole_size_slider: HSlider
var hole_twist_slider: HSlider
var hole_softness_slider: HSlider
var hole_flow_slider: HSlider
var hole_cx_slider: HSlider
var hole_cy_slider: HSlider
var hole_schedule: CheckButton
var hole_schedule_host: VBoxContainer
var tone_toggle: CheckButton
var tone_body: VBoxContainer
var tone_invert_slider: HSlider
var tone_brightness_slider: HSlider
var tone_contrast_slider: HSlider
var tone_saturation_slider: HSlider
var tone_schedule: CheckButton
var tone_schedule_host: VBoxContainer
## body VBox -> PanelContainer wrapper that draws the nesting indent / tint / left rule.
var _setting_nests: Dictionary = {}
var _shuffle_slots: Dictionary = {}
var _random_groups: Dictionary = {}
var _play_all_audio_drivers_active: bool = false
var _play_all_audio_snapshot: Dictionary = {}
var _play_all_audio_wireframe_expr: String = ""

@onready var point_cloud_toggle: CheckButton = $Margin/Scroll/Column/FxSection/PointCloudToggle
@onready var point_cloud_body: VBoxContainer = $Margin/Scroll/Column/FxSection/PointCloudBody
@onready var point_cloud_drive: OptionButton = $Margin/Scroll/Column/FxSection/PointCloudBody/PointCloudDrive
@onready var point_cloud_size_slider: HSlider = $Margin/Scroll/Column/FxSection/PointCloudBody/PointCloudSizeSlider
@onready var point_cloud_schedule: CheckButton = $Margin/Scroll/Column/FxSection/PointCloudBody/PointCloudSchedule
@onready var point_cloud_schedule_host: VBoxContainer = $Margin/Scroll/Column/FxSection/PointCloudBody/PointCloudScheduleHost

@onready var camera_fx_toggle: CheckButton = $Margin/Scroll/Column/FxSection/CameraFxToggle
@onready var camera_fx_body: VBoxContainer = $Margin/Scroll/Column/FxSection/CameraFxBody
@onready var camera_fx_drive: OptionButton = $Margin/Scroll/Column/FxSection/CameraFxBody/CameraFxDrive
@onready var camera_fx_focal_slider: HSlider = $Margin/Scroll/Column/FxSection/CameraFxBody/CameraFxFocalSlider
@onready var camera_fx_aperture_slider: HSlider = $Margin/Scroll/Column/FxSection/CameraFxBody/CameraFxApertureSlider
@onready var camera_fx_focus_label: Label = $Margin/Scroll/Column/FxSection/CameraFxBody/CameraFxFocusLabel
@onready var camera_fx_focus_slider: HSlider = $Margin/Scroll/Column/FxSection/CameraFxBody/CameraFxFocusSlider
@onready var camera_fx_focus_far_label: Label = $Margin/Scroll/Column/FxSection/CameraFxBody/CameraFxFocusFarLabel
@onready var camera_fx_focus_far_slider: HSlider = $Margin/Scroll/Column/FxSection/CameraFxBody/CameraFxFocusFarSlider
@onready var camera_fx_falloff_slider: HSlider = $Margin/Scroll/Column/FxSection/CameraFxBody/CameraFxFalloffSlider
@onready var camera_fx_bokeh_slider: HSlider = $Margin/Scroll/Column/FxSection/CameraFxBody/CameraFxBokehSlider
@onready var camera_fx_schedule: CheckButton = $Margin/Scroll/Column/FxSection/CameraFxBody/CameraFxSchedule
@onready var camera_fx_schedule_host: VBoxContainer = $Margin/Scroll/Column/FxSection/CameraFxBody/CameraFxScheduleHost

var nonlinear_camera_toggle: CheckButton
var nonlinear_camera_body: VBoxContainer
var np_strength_slider: HSlider
var np_start_slider: HSlider
var np_end_slider: HSlider
var np_bend_slider: HSlider
var np_auto_center: CheckButton
var np_lift_slider: HSlider
var nonlinear_camera_schedule: CheckButton
var nonlinear_camera_schedule_host: VBoxContainer
var material_override_toggle: CheckButton
var material_override_body: VBoxContainer
var material_override_look: OptionButton
var material_override_schedule: CheckButton
var material_override_schedule_host: VBoxContainer
var fog_toggle: CheckButton
var fog_body: VBoxContainer
var fog_density_slider: HSlider
var fog_begin_slider: HSlider
var fog_end_slider: HSlider
var fog_tint_slider: HSlider
var fog_schedule: CheckButton
var fog_schedule_host: VBoxContainer

@onready var cue_container: HFlowContainer = $Margin/Scroll/Column/CueSection/CueContainer
@onready var search_row: Control = $Margin/Scroll/Column/SearchRow
@onready var search_edit: LineEdit = $Margin/Scroll/Column/SearchRow/SearchMargin/SearchContent/SearchEdit
@onready var audio_section: VBoxContainer = $Margin/Scroll/Column/AudioSection
@onready var fx_section: VBoxContainer = $Margin/Scroll/Column/FxSection
@onready var cue_section: VBoxContainer = $Margin/Scroll/Column/CueSection
@onready var fx_label: Label = $Margin/Scroll/Column/FxSection/FxLabel
@onready var targets_label: Label = $Margin/Scroll/Column/Targets/TargetsLabel

var _syncing_ui: bool = false
var _fx_drive_opts: Dictionary = {}
var _density_range  # DualRangeSlider (ASCII numeric/random window)
var _ascii_density_slider: HSlider
var _scale_amount_slider: HSlider
var _rotation_amount_slider: HSlider
var _cloth_gravity_slider: HSlider
var _schedule_ranges: Dictionary = {}  # effect_id -> ScheduleSecondsPair
var _user_density_min: float = 8.0
var _user_density_max: float = 80.0
var _ascii_lfo_wave: OptionButton
var _ascii_lfo_wave_label: Label
var _fx_lfo: Dictionary = {}  # effect_id -> {rate, depth, rate_label, depth_label, audio, audio_label}
var _pc_target_row: HBoxContainer
var _pc_target_label: Label
var _pc_target_checks: Dictionary = {}
var _camera_fx_lens_slider: HSlider
var _camera_fx_lens_label: Label
var _content_tab: int = 0
var _tab_bar: TabBar
var _drivers_section: VBoxContainer
var _stage_camera_section: VBoxContainer
var _stage_camera_toggle: CheckButton
var _drivers_builtin_list: VBoxContainer
var _drivers_signal_list: VBoxContainer
var _driver_live_labels: Dictionary = {}
var _driver_card_writes: Array = []
var _driver_modal: AcceptDialog
var _driver_assign_slider: HSlider
var _driver_assign_choice: OptionButton
var _modal_name: LineEdit
var _modal_type: OptionButton
var _modal_params: VBoxContainer
var _modal_rate: SpinBox
var _modal_depth: SpinBox
var _modal_wave: OptionButton
var _modal_speed: SpinBox
var _modal_smooth: SpinBox
var _modal_rmin: SpinBox
var _modal_rmax: SpinBox
## Accordion bodies created at runtime so each effect's controls nest under its toggle.
var _scale_body: VBoxContainer
var _light_body: VBoxContainer
var _emission_body: VBoxContainer
var _rotation_body: VBoxContainer
var _noise_body: VBoxContainer
## Search filter rows: {section, header, body, text} — body may be null.
var _filter_items: Array = []

const PLAY_MODE_IDS := ["cycle", "random", "evolution"]
const PLAY_MODE_LABELS := ["Cycle", "Random", "Evolution"]
const PLAY_MODE_TOOLTIPS := [
	"Keep the selected effect stack active continuously.",
	"Reshuffle which effects are on and their looks over time.",
	"Start with one effect, add up to a small stack, then remove back to one and repeat.",
]
const PLAY_ALL_AUDIO_DRIVERS: PackedStringArray = [
	"volume", "energy", "bass", "mids", "highs", "kick", "beat",
]
const PLAY_ALL_AUDIO_SHUFFLE_MULS: Array = [2.0, 3.0, 5.0, 10.0]
const PLAY_ALL_INTERNAL_ACTIVE_SEC := 4.0
const PLAY_ALL_INTERNAL_INACTIVE_SEC := 4.0


func _ready() -> void:
	_nest_react_bodies()
	_setup_search_filter()
	for preset_name in AsciiEffect.PRESETS.keys():
		ascii_preset.add_item(str(preset_name))
	_fill_driver(scale_source)
	_fill_driver(emission_source)
	_fill_driver(rotation_source)
	_fill_driver(light_source)
	_fill_driver(noise_source)
	_fx_drive_opts = {
		"ascii": ascii_drive,
		"feedback": feedback_drive,
		"glitch": glitch_drive,
		"chromatic": chromatic_drive,
		"wireframe": wireframe_drive,
		"point_cloud": point_cloud_drive,
		"camera_fx": camera_fx_drive,
	}
	_hide_fx_drive_ui()
	_hide_deform_legacy()
	if ascii_invert:
		ascii_invert.visible = false
	if ascii_density_random:
		ascii_density_random.visible = false
	if ascii_density_host:
		ascii_density_host.visible = false
	if ascii_density_label:
		ascii_density_label.visible = true
		ascii_density_label.text = "Density"
		ascii_density_label.tooltip_text = "Glyph density. Type or paste bass * 80, or pick from Driver."
	RH.set_field("target_lights", false)
	RH.set_field("rotation_target_lights", false)
	RH.set_field("noise_target_lights", false)
	RH.set_field("particles_target_lights", false)
	RH.set_field("particles_target_media", false)
	camera_preset.clear()
	for p in CAMERA_PRESETS:
		camera_preset.add_item(p)
	play_mode.clear()
	for i in PLAY_MODE_LABELS.size():
		play_mode.add_item(PLAY_MODE_LABELS[i])
		if i < PLAY_MODE_TOOLTIPS.size():
			play_mode.set_item_tooltip(i, PLAY_MODE_TOOLTIPS[i])
	play_mode.select(0)
	play_mode.tooltip_text = "Play All mode. Cycle, Random, and Evolution are mutually exclusive. Audio reactive applies to any mode."
	if play_audio_reactive:
		play_audio_reactive.tooltip_text = "With Play All: put every effect slider on Driver and assign an audio source (volume, bass, mids, bands, …). Shuffle mode also randomizes which source and multiplies amounts (2×–10×)."
	reactivity_toggle.button_pressed = bool(RH.get_field("enabled", false))
	affect_scale.button_pressed = bool(RH.get_field("affect_scale", false))
	scale_x.button_pressed = bool(RH.get_field("scale_x", true))
	scale_y.button_pressed = bool(RH.get_field("scale_y", true))
	scale_z.button_pressed = bool(RH.get_field("scale_z", true))
	affect_light.button_pressed = bool(RH.get_field("affect_light", false))
	affect_emission.button_pressed = bool(RH.get_field("affect_emission", false))
	affect_rotation.button_pressed = bool(RH.get_field("affect_rotation", false))
	affect_noise.button_pressed = bool(RH.get_field("affect_noise", false))
	scale_amount_spin.value = RH.scale_amount()
	rotation_amount_spin.value = float(RH.get_field("rotation_amount", 1.0))
	rotation_x.button_pressed = bool(RH.get_field("rotation_x", true))
	rotation_y.button_pressed = bool(RH.get_field("rotation_y", true))
	rotation_z.button_pressed = bool(RH.get_field("rotation_z", true))
	noise_amount.value = float(RH.get_field("noise_amount", 2.0))
	noise_scale.value = float(RH.get_field("noise_scale", RH.get_field("noise_speed", 2.0)))
	noise_x.button_pressed = bool(RH.get_field("noise_x", true))
	noise_y.button_pressed = bool(RH.get_field("noise_y", true))
	noise_z.button_pressed = bool(RH.get_field("noise_z", true))
	_sync_target_checkboxes_from_rh()
	_select_driver(scale_source, str(RH.get_field("scale_source", "off")))
	_select_driver(emission_source, str(RH.get_field("emission_source", "mids")))
	_select_driver(rotation_source, str(RH.get_field("rotation_source", "highs")))
	_select_driver(light_source, str(RH.get_field("light_source", "energy")))
	_select_driver(noise_source, str(RH.get_field("noise_source", "bass")))
	_select_camera_preset(str(RH.get_field("camera_preset", "Off")))
	camera_motion_toggle.button_pressed = str(RH.get_field("camera_preset", "Off")) != "Off"
	# Camera rate/depth UI are 1–100; settings retain the normalized values.
	camera_rate.value = clampf(float(RH.get_field("camera_rate", 0.4)) * 20.0, 1.0, 100.0)
	camera_depth.value = clampf(float(RH.get_field("camera_depth", 0.75)) * 100.0, 0.0, 100.0)

	reactivity_toggle.toggled.connect(_on_reactivity_toggled)
	if reset_defaults_btn:
		reset_defaults_btn.pressed.connect(_on_reset_to_defaults)
	ShowDirector.stage_defaults_restored.connect(_sync_reactivity_widgets_from_rh)
	ShowDirector.stage_defaults_restored.connect(_sync_stage_camera_card)
	intensity_slider.value_changed.connect(func(_v: float) -> void: AudioAnalyzer.master_intensity = SliderSpinLinkScr.eval_of(intensity_slider))
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
	_connect_target_checkboxes()
	# Noise/camera amounts are written from attach_driven + _push_driven_reactivity (expressions).
	noise_x.toggled.connect(func(v: bool) -> void: RH.set_field("noise_x", v))
	noise_y.toggled.connect(func(v: bool) -> void: RH.set_field("noise_y", v))
	noise_z.toggled.connect(func(v: bool) -> void: RH.set_field("noise_z", v))
	scale_schedule.toggled.connect(func(v: bool) -> void: _on_react_schedule("scale", v))
	light_schedule.toggled.connect(func(v: bool) -> void: _on_react_schedule("light", v))
	emission_schedule.toggled.connect(func(v: bool) -> void: _on_react_schedule("emission", v))
	rotation_schedule.toggled.connect(func(v: bool) -> void: _on_react_schedule("rotation", v))
	noise_schedule.toggled.connect(func(v: bool) -> void: _on_react_schedule("noise", v))
	camera_schedule.toggled.connect(func(v: bool) -> void: _on_react_schedule("camera", v))
	camera_motion_toggle.toggled.connect(_on_camera_motion_toggled)
	camera_preset.item_selected.connect(_on_camera_preset)
	# Camera motion has its own mapping, so typed/driver values above 100 stay useful.

	play_all_toggle.toggled.connect(_on_play_all_toggled)
	play_all_toggle.tooltip_text = "Auto Mode: drive effects with Presets (one saved look) or Play All (full stack). Not both."
	play_mode.item_selected.connect(_on_play_mode_selected)
	play_audio_reactive.toggled.connect(_on_play_audio_reactive)
	style_switch_toggle.toggled.connect(_on_style_switch_toggled)
	style_interval_slider.value_changed.connect(_on_style_interval)

	ascii_toggle.toggled.connect(_on_ascii_toggled)
	ascii_preset.item_selected.connect(_on_ascii_preset)
	ascii_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("ascii", v))

	feedback_toggle.toggled.connect(_on_feedback_toggled)
	feedback_mix_slider.value_changed.connect(_on_feedback_params)
	feedback_persist_slider.value_changed.connect(_on_feedback_params)
	feedback_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("feedback", v))

	glitch_toggle.toggled.connect(_on_glitch_toggled)
	glitch_vsize_slider.value_changed.connect(_on_glitch_params)
	glitch_amount_slider.value_changed.connect(_on_glitch_params)
	glitch_speed_slider.value_changed.connect(_on_glitch_params)
	glitch_hsize_slider.value_changed.connect(_on_glitch_params)
	glitch_rgb_slider.value_changed.connect(_on_glitch_params)
	glitch_chaos_slider.value_changed.connect(_on_glitch_params)
	glitch_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("glitch", v))

	chromatic_toggle.toggled.connect(_on_chromatic_toggled)
	chromatic_amount_slider.value_changed.connect(_on_chromatic_params)
	chromatic_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("chromatic", v))

	wireframe_toggle.toggled.connect(_on_wireframe_toggled)
	wireframe_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("wireframe", v))

	point_cloud_toggle.toggled.connect(_on_point_cloud_toggled)
	point_cloud_size_slider.value_changed.connect(_on_point_cloud_params)
	point_cloud_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("point_cloud", v))

	camera_fx_toggle.toggled.connect(_on_camera_fx_toggled)
	camera_fx_focal_slider.value_changed.connect(_on_camera_fx_params)
	camera_fx_aperture_slider.value_changed.connect(_on_camera_fx_params)
	camera_fx_focus_slider.value_changed.connect(_on_camera_fx_params)
	camera_fx_focus_far_slider.value_changed.connect(_on_camera_fx_params)
	camera_fx_falloff_slider.value_changed.connect(_on_camera_fx_params)
	camera_fx_bokeh_slider.value_changed.connect(_on_camera_fx_params)
	camera_fx_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("camera_fx", v))

	_setup_hole()
	_setup_tone()
	_setup_nonlinear_camera()
	_setup_material_override()
	_setup_fog()
	_setup_feedback_blur()
	_setup_dual_ranges()
	_setup_ascii_density_driver()
	_attach_slider_value_fields()
	_setup_camera_lens_control()
	_setup_point_cloud_targets()
	_setup_auto_mode_section()
	_setup_shuffle_and_random()
	_flatten_effect_list()
	_apply_effect_hierarchy_styling()
	_setup_search_filter()
	_setup_content_tabs()
	# Playlist creates the stage-camera fields and shuffle controls during its own ready.
	# Defer one frame, then place it directly after the Auto Mode card.
	call_deferred("_move_stage_camera_controls_here")
	_setup_driver_modal()
	_setup_preset_ui()
	SliderSpinLinkScr.add_new_handler = _open_driver_modal_for
	ShowDirector.show_loaded.connect(func(_n: String) -> void: _rebuild_cues())
	ShowDirector.effect_style_advanced.connect(_on_style_advanced_ui)
	AudioAnalyzer.state_updated.connect(_on_audio)
	AudioAnalyzer.devices_changed.connect(_on_devices_changed)
	AudioAnalyzer.capture_status_changed.connect(_on_capture_status)
	AudioAnalyzer.master_intensity = intensity_slider.value
	# Band sensitivity UI 1–20 maps into analyzer once (not double-applied).
	AudioAnalyzer.band_sensitivity = sensitivity_slider.value * 0.35
	AudioAnalyzer.set_noise_floor(noise_floor_slider.value)
	_setup_audio_source_picker()
	_setup_spectrum_bars()
	_setup_input_level_meter()
	if capture_status_label:
		capture_status_label.text = AudioAnalyzer.get_capture_status()
		capture_status_label.modulate = Color.WHITE
		_on_capture_status(AudioAnalyzer.get_capture_status())
	_rebuild_cues()
	_sync_conditional_ui()
	search_edit.text_changed.connect(_on_search_text_changed)
	set_process(true)
	var hub := get_node_or_null("/root/DriverHub")
	if hub:
		hub.connect("drivers_changed", _rebuild_driver_cards)
		hub.connect("values_updated", _on_driver_values)


func _attach_slider_value_fields() -> void:
	## Every numeric FX / analyzer / schedule field: slider + LineEdit + Driver.
	SliderSpinLinkScr.attach_driven(intensity_slider, func(_v: float = 0.0) -> void:
		AudioAnalyzer.master_intensity = SliderSpinLinkScr.eval_of(intensity_slider)
	, 1.0)
	SliderSpinLinkScr.attach_driven(sensitivity_slider, func(_v: float = 0.0) -> void:
		AudioAnalyzer.band_sensitivity = SliderSpinLinkScr.eval_of(sensitivity_slider) * 0.35
	, 1.0)
	SliderSpinLinkScr.attach_driven(noise_floor_slider, func(_v: float = 0.0) -> void:
		AudioAnalyzer.set_noise_floor(SliderSpinLinkScr.eval_of(noise_floor_slider))
	, 1.0)
	SliderSpinLinkScr.attach_driven(style_interval_slider, _on_style_interval, 1.0)
	SliderSpinLinkScr.attach_driven(noise_amount, func(_v: float = 0.0) -> void: RH.set_field("noise_amount", _deform_num(noise_amount)), 1.0)
	SliderSpinLinkScr.attach_driven(noise_scale, func(_v: float = 0.0) -> void: RH.set_field("noise_scale", _deform_num(noise_scale)), 1.0)
	SliderSpinLinkScr.attach_driven(camera_rate, func(_v: float = 0.0) -> void: RH.set_field("camera_rate", _camera_motion_rate()), 1.0)
	SliderSpinLinkScr.attach_driven(camera_depth, func(_v: float = 0.0) -> void: RH.set_field("camera_depth", _camera_motion_depth()), 1.0)
	camera_rate.tooltip_text = "Walking cadence. The default is deliberately slow; higher values speed it up gently."
	camera_depth.tooltip_text = "Walking presence. Values above 100 keep growing softly instead of becoming violent."
	SliderSpinLinkScr.attach_driven(feedback_mix_slider, _on_feedback_params, 100.0)
	SliderSpinLinkScr.attach_driven(feedback_persist_slider, _on_feedback_params, 100.0)
	if feedback_mix_slider:
		feedback_mix_slider.tooltip_text = "How strongly the new frame is drawn on top of the trail. 100 = fully visible."
	if feedback_persist_slider:
		feedback_persist_slider.tooltip_text = "How long leftover pixels stay. 100 = they never fade (Windows-style trail). 0 = no trail."
	SliderSpinLinkScr.attach_driven(glitch_vsize_slider, _on_glitch_params, 1.0)
	SliderSpinLinkScr.attach_driven(glitch_amount_slider, _on_glitch_params, 28.0)
	SliderSpinLinkScr.attach_driven(glitch_speed_slider, _on_glitch_params, 3.0)
	SliderSpinLinkScr.attach_driven(glitch_hsize_slider, _on_glitch_params, 1.0)
	SliderSpinLinkScr.attach_driven(glitch_rgb_slider, _on_glitch_params, 100.0)
	SliderSpinLinkScr.attach_driven(glitch_chaos_slider, _on_glitch_params, 100.0)
	if glitch_vsize_slider:
		glitch_vsize_slider.tooltip_text = "Height of each glitch slice in pixels. 1 = 1 pixel."
	if glitch_hsize_slider:
		glitch_hsize_slider.tooltip_text = "Width of each glitch slice in pixels. 1 = 1 pixel."
	if glitch_amount_slider:
		glitch_amount_slider.tooltip_text = "How strong the glitch is (shift mix), not slice size."
	if glitch_speed_slider:
		glitch_speed_slider.tooltip_text = "How fast the glitch pattern animates."
	if glitch_chaos_slider:
		glitch_chaos_slider.tooltip_text = "Randomizes slice layout (irregular bands, jitter). Not animation speed."
	SliderSpinLinkScr.attach_driven(chromatic_amount_slider, _on_chromatic_params, 28.0)
	SliderSpinLinkScr.attach_driven(point_cloud_size_slider, _on_point_cloud_params, 1.0)
	SliderSpinLinkScr.attach_driven(camera_fx_focal_slider, _on_camera_fx_params, 1.0)
	SliderSpinLinkScr.attach_driven(camera_fx_aperture_slider, _on_camera_fx_params, 1.0)
	SliderSpinLinkScr.attach_driven(camera_fx_focus_slider, _on_camera_fx_params, 1.0)
	SliderSpinLinkScr.attach_driven(camera_fx_focus_far_slider, _on_camera_fx_params, 1.0)
	SliderSpinLinkScr.attach_driven(camera_fx_falloff_slider, _on_camera_fx_params, 100.0)
	SliderSpinLinkScr.attach_driven(camera_fx_bokeh_slider, _on_camera_fx_params, 100.0)
	if _ascii_density_slider:
		SliderSpinLinkScr.attach_driven(_ascii_density_slider, _on_ascii_density_driven, 1.0)
	if ascii_preset:
		ascii_preset.tooltip_text = "Style / charset. Driver maps a signal to style index (wraps). Try lfo1 * 15 or time."
		SliderSpinLinkScr.attach_driven_choice(ascii_preset, _on_ascii_style_driven)
	_setup_deform_amount_sliders()
	SliderSpinLinkScr.configure_spin(scale_amount_spin, 0.001)
	SliderSpinLinkScr.configure_spin(rotation_amount_spin, 0.001)


func _setup_deform_amount_sliders() -> void:
	## Scale/rotation were SpinBoxes — same Driver row as Glitch.
	_scale_amount_slider = _spin_to_driven_slider(
		scale_amount_spin, 0.0, 200.0, 1.0,
		func(_v: float = 0.0) -> void: RH.set_scale_amount(_deform_num(_scale_amount_slider))
	)
	_rotation_amount_slider = _spin_to_driven_slider(
		rotation_amount_spin, 0.0, 200.0, 1.0,
		func(_v: float = 0.0) -> void: RH.set_rotation_amount(_deform_num(_rotation_amount_slider))
	)


func _spin_to_driven_slider(spin: SpinBox, lo: float, hi: float, step: float, on_change: Callable) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = spin.value if spin else lo
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var host := spin.get_parent()
	var idx := spin.get_index()
	host.add_child(sl)
	host.move_child(sl, idx)
	spin.visible = false
	SliderSpinLinkScr.attach_driven(sl, on_change, 1.0)
	return sl


func _setup_search_filter() -> void:
	## Build searchable rows after nested bodies exist. Match against effect / setting labels.
	_filter_items = [
		{
			"section": "audio",
			"header": reactivity_toggle,
			"body": reactivity_body,
			"text": "audio reactivity master intensity band sensitivity noise floor input device spectrum equalizer graph energy bass mids highs",
		},
		{
			"section": "fx",
			"header": affect_scale,
			"body": _scale_body,
			"text": "scale deform scale amount driver affects main scatter outer lights schedule",
		},
		{
			"section": "fx",
			"header": affect_rotation,
			"body": _rotation_body,
			"text": "rotation deform amount axes schedule main scatter environment outer camera",
		},
		{
			"section": "fx",
			"header": affect_noise,
			"body": _noise_body,
			"text": "noise displace deform strength scale schedule main scatter environment outer",
		},
		{
			"section": "fx",
			"header": camera_motion_toggle,
			"body": camera_body,
			"text": "camera motion deform lfo speed amount schedule",
		},
		{
			"section": "fx",
			"header": play_all_toggle,
			"body": play_all_body,
			"text": "auto mode presets play all mode audio reactive schedule full stack saved snapshot look",
		},
		{
			"section": "fx",
			"header": ascii_toggle,
			"body": ascii_body,
			"text": "ascii preset style density invert style switch schedule",
		},
		{
			"section": "fx",
			"header": feedback_toggle,
			"body": feedback_body,
			"text": "feedback trail mix opacity persistence blur sharp ghost echo schedule blend mode normal brightest darkest edges contrast",
		},
		{
			"section": "fx",
			"header": glitch_toggle,
			"body": glitch_body,
			"text": "glitch vertical size horizontal size intensity amount speed rgb slice chaos schedule",
		},
		{
			"section": "fx",
			"header": chromatic_toggle,
			"body": chromatic_body,
			"text": "chromatic aberration amount schedule",
		},
		{
			"section": "fx",
			"header": tone_toggle,
			"body": tone_body,
			"text": "tone invert negative brightness lightness exposure contrast saturation colour color schedule",
		},
		{
			"section": "fx",
			"header": wireframe_toggle,
			"body": wireframe_body,
			"text": "wireframe schedule",
		},
		{
			"section": "fx",
			"header": hole_toggle,
			"body": hole_body,
			"text": "hole suck fall stretch event horizon wormhole funnel twist spiral circular rectangle",
		},
		{
			"section": "fx",
			"header": point_cloud_toggle,
			"body": point_cloud_body,
			"text": "point cloud size vertices dots lidar schedule lfo audio amount main scatter outer environment media",
		},
		{
			"section": "fx",
			"header": camera_fx_toggle,
			"body": camera_fx_body,
			"text": "camera lens dof bokeh focal length aperture focus near far range distortion fisheye equirectangular schedule lfo",
		},
		{
			"section": "fx",
			"header": material_override_toggle,
			"body": material_override_body,
			"text": "material override cladding chrome gold normal map shiny black schedule shuffle",
		},
		{
			"section": "fx",
			"header": fog_toggle,
			"body": fog_body,
			"text": "fog mist haze atmosphere distance density noise volumetric aerial perspective tint hue rainbow spectrum",
		},
		{
			"section": "fx",
			"header": nonlinear_camera_toggle,
			"body": nonlinear_camera_body,
			"text": "bend space band space nonlinear camera projection warp bend lift top-down far near hyperspace driver input strength auto center offset schedule",
		},
		{
			"section": "cues",
			"header": cue_section.get_node("CueLabel"),
			"body": cue_container,
			"text": "cues cue",
		},
	]
	# Fold visible button/label text into search haystack.
	for item in _filter_items:
		var extra := ""
		var header: Control = item.header
		if header is BaseButton:
			extra = str((header as BaseButton).text)
		elif header is Label:
			extra = str((header as Label).text)
		item.text = (str(item.text) + " " + extra).to_lower()


func _on_search_text_changed(_new_text: String) -> void:
	_sync_conditional_ui()


func _apply_search_filter() -> void:
	if search_edit == null or _filter_items.is_empty():
		return
	var q := search_edit.text.strip_edges().to_lower()
	var filtering := not q.is_empty()
	var hits := {"audio": false, "targets": false, "fx": false, "cues": false}

	for item in _filter_items:
		var header: Control = item.header
		if header == null or not is_instance_valid(header):
			continue
		var hit := not filtering or str(item.text).contains(q)
		var body = item.body
		header.visible = hit
		if body != null and is_instance_valid(body):
			if not hit:
				(body as CanvasItem).visible = false
			# On hit, leave body visibility as set by accordion sync above.
		if hit:
			hits[str(item.section)] = true

	# No group headers any more: one flat effect list lives in fx_section.
	fx_label.visible = false
	targets.visible = false
	if filtering:
		audio_section.visible = hits.audio
		fx_section.visible = hits.fx
		cue_section.visible = hits.cues and cue_container.get_child_count() > 0
	else:
		audio_section.visible = true
		fx_section.visible = true
		# cue_section already set by accordion sync


func _nest_react_bodies() -> void:
	## Nest each Targets effect's controls under a Body VBox (accordion pattern like FX).
	var targets_node: VBoxContainer = targets
	_scale_body = _make_nested_body(targets_node, affect_scale, "ScaleBody")
	_reparent_into(_scale_body, [
		target_row,
		$Margin/Scroll/Column/AudioSection/ReactivityBody/ScaleAmountLabel,
		scale_amount_spin,
		scale_source,
		$Margin/Scroll/Column/Targets/AxisRow,
		scale_schedule,
		scale_schedule_host,
	])
	var scale_affects_lbl := Label.new()
	scale_affects_lbl.text = "Affects"
	_scale_body.add_child(scale_affects_lbl)
	_scale_body.move_child(scale_affects_lbl, target_row.get_index())
	# Mode label for Scale source (matches FX Mode pattern).
	var scale_mode_lbl := Label.new()
	scale_mode_lbl.text = "Mode"
	_scale_body.add_child(scale_mode_lbl)
	_scale_body.move_child(scale_mode_lbl, scale_source.get_index())

	_light_body = _make_nested_body(targets_node, affect_light, "LightBody")
	_reparent_into(_light_body, [light_source, light_schedule, light_schedule_host])
	var light_mode_lbl := Label.new()
	light_mode_lbl.text = "Mode"
	_light_body.add_child(light_mode_lbl)
	_light_body.move_child(light_mode_lbl, light_source.get_index())

	_emission_body = _make_nested_body(targets_node, affect_emission, "EmissionBody")
	_reparent_into(_emission_body, [emission_source, emission_schedule, emission_schedule_host])
	var emission_mode_lbl := Label.new()
	emission_mode_lbl.text = "Mode"
	_emission_body.add_child(emission_mode_lbl)
	_emission_body.move_child(emission_mode_lbl, emission_source.get_index())

	_rotation_body = _make_nested_body(targets_node, affect_rotation, "RotationBody")
	_reparent_into(_rotation_body, [
		rotation_source,
		$Margin/Scroll/Column/Targets/RotationTargetLabel,
		rotation_target_row,
		$Margin/Scroll/Column/Targets/RotationAmountLabel,
		rotation_amount_spin,
		$Margin/Scroll/Column/Targets/RotationAxisRow,
		rotation_schedule,
		rotation_schedule_host,
	])
	var rot_mode_lbl := Label.new()
	rot_mode_lbl.text = "Mode"
	_rotation_body.add_child(rot_mode_lbl)
	_rotation_body.move_child(rot_mode_lbl, rotation_source.get_index())

	_noise_body = _make_nested_body(targets_node, affect_noise, "NoiseBody")
	_reparent_into(_noise_body, [
		noise_source,
		$Margin/Scroll/Column/Targets/NoiseTargetLabel,
		noise_target_row,
		$Margin/Scroll/Column/Targets/NoiseAmountLabel,
		noise_amount,
		$Margin/Scroll/Column/Targets/NoiseScaleLabel,
		noise_scale,
		$Margin/Scroll/Column/Targets/NoiseAxisRow,
		noise_schedule,
		noise_schedule_host,
	])
	var noise_mode_lbl := Label.new()
	noise_mode_lbl.text = "Mode"
	_noise_body.add_child(noise_mode_lbl)
	_noise_body.move_child(noise_mode_lbl, noise_source.get_index())


func _effect_rows() -> Array:
	## The single flat effect list, top to bottom: [header, settings body].
	## Auto Mode leads so its global playback choice is always immediately available.
	return [
		[play_all_toggle, play_all_body],
		[camera_motion_toggle, camera_body],
		[camera_fx_toggle, camera_fx_body],
		[nonlinear_camera_toggle, nonlinear_camera_body],
		[affect_scale, _scale_body],
		[affect_rotation, _rotation_body],
		[affect_noise, _noise_body],
		[ascii_toggle, ascii_body],
		[feedback_toggle, feedback_body],
		[glitch_toggle, glitch_body],
		[chromatic_toggle, chromatic_body],
		[tone_toggle, tone_body],
		[hole_toggle, hole_body],
		[wireframe_toggle, wireframe_body],
		[point_cloud_toggle, point_cloud_body],
		[material_override_toggle, material_override_body],
		[fog_toggle, fog_body],
	]


func _flatten_effect_list() -> void:
	## One list, no group headers. The old Deform rows move out of Targets into FxSection.
	if fx_section == null:
		return
	if fx_label:
		fx_label.visible = false
	if targets_label:
		targets_label.visible = false
	var ordered: Array = []
	for row_any in _effect_rows():
		var row: Array = row_any as Array
		for n_any in row:
			if n_any != null and is_instance_valid(n_any):
				ordered.append(n_any)
	var at := 0
	for n_any in ordered:
		var node: Node = n_any as Node
		if node == null:
			continue
		if node.get_parent() != fx_section:
			node.reparent(fx_section)
		fx_section.move_child(node, at)
		at += 1


func _setting_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = FX_SETTING_BG
	sb.border_color = FX_SETTING_RULE
	sb.border_width_left = 2
	sb.set_corner_radius_all(3)
	sb.content_margin_left = FX_SETTING_INDENT
	sb.content_margin_right = FX_SETTING_PAD
	sb.content_margin_top = FX_SETTING_PAD
	sb.content_margin_bottom = FX_SETTING_PAD
	return sb


func _apply_effect_hierarchy_styling() -> void:
	## Effect rows read as headings; their settings sit inside an indented, tinted panel with a
	## left rule so the parent/child relationship is obvious at a glance.
	for row_any in _effect_rows():
		var row: Array = row_any as Array
		var header := _live_check(row[0])
		if header:
			header.add_theme_font_size_override("font_size", FX_HEADER_FONT_SIZE)
			header.add_theme_color_override("font_color", FX_HEADER_COLOR)
			header.add_theme_color_override("font_hover_color", FX_HEADER_COLOR)
		var body := row[1] as VBoxContainer
		if body == null or not is_instance_valid(body):
			continue
		_nest_setting_body(body)
		_quiet_setting_labels(body)


func _nest_setting_body(body: VBoxContainer) -> void:
	if _setting_nests.has(body):
		return
	var host := body.get_parent()
	if host == null:
		return
	var idx := body.get_index()
	var panel := PanelContainer.new()
	panel.name = str(body.name) + "Nest"
	panel.add_theme_stylebox_override("panel", _setting_panel_style())
	host.add_child(panel)
	host.move_child(panel, idx)
	body.reparent(panel)
	panel.visible = body.visible
	_setting_nests[body] = panel
	# Every accordion / search / Play All write still targets `body.visible`; mirror it so the
	# indent panel never draws around a hidden body.
	body.visibility_changed.connect(func() -> void:
		if is_instance_valid(panel) and is_instance_valid(body):
			panel.visible = body.visible
	)


func _quiet_setting_labels(root: Node) -> void:
	for child in root.get_children():
		if child is Label:
			var lab := child as Label
			lab.add_theme_font_size_override("font_size", FX_SETTING_FONT_SIZE)
			lab.add_theme_color_override("font_color", FX_SETTING_LABEL_COLOR)
		elif child is CheckButton:
			var cb := child as CheckButton
			cb.add_theme_font_size_override("font_size", FX_SETTING_FONT_SIZE + 1)
			cb.add_theme_color_override("font_color", FX_SETTING_LABEL_COLOR)
			cb.add_theme_color_override("font_hover_color", FX_HEADER_COLOR)
		if child.get_child_count() > 0:
			_quiet_setting_labels(child)


func _make_nested_body(parent: Node, after: Control, body_name: String) -> VBoxContainer:
	var body := VBoxContainer.new()
	body.name = body_name
	body.visible = false
	body.add_theme_constant_override("separation", 4)
	parent.add_child(body)
	parent.move_child(body, after.get_index() + 1)
	return body


func _reparent_into(body: VBoxContainer, nodes: Array) -> void:
	for n in nodes:
		if n == null or not is_instance_valid(n):
			continue
		var node: Node = n as Node
		if node == null:
			continue
		var idx := body.get_child_count()
		node.reparent(body)
		body.move_child(node, idx)


func _hide_fx_drive_ui() -> void:
	## Per-effect Audio/LFO/Static pickers moved to the Drivers tab + expressions.
	for opt_any in _fx_drive_opts.values():
		var opt := _live_option(opt_any)
		if opt == null:
			continue
		opt.visible = false
		var p: Node = opt.get_parent()
		if p == null:
			continue
		var idx: int = opt.get_index()
		if idx > 0:
			var prev_lab := _live_label(p.get_child(idx - 1))
			if prev_lab and prev_lab.text.strip_edges() == "Mode":
				prev_lab.visible = false
	if feedback_sens_slider:
		feedback_sens_slider.visible = false
	if feedback_lfo_rate:
		feedback_lfo_rate.visible = false


func _hide_deform_legacy() -> void:
	## Keep Scale/Rotation/Noise/Camera. Hide band pickers, Mode labels, light/emission.
	if targets_label:
		targets_label.visible = false
	for opt in [scale_source, rotation_source, noise_source, light_source, emission_source]:
		if opt == null:
			continue
		opt.visible = false
		var p: Node = opt.get_parent()
		if p == null:
			continue
		var idx: int = opt.get_index()
		if idx > 0:
			var prev_lab := _live_label(p.get_child(idx - 1))
			if prev_lab and prev_lab.text.strip_edges() == "Mode":
				prev_lab.visible = false
	if affect_light:
		affect_light.visible = false
	if affect_emission:
		affect_emission.visible = false
	if _light_body:
		_light_body.visible = false
	if _emission_body:
		_emission_body.visible = false
	if light_schedule:
		light_schedule.visible = false
	if emission_schedule:
		emission_schedule.visible = false
	if light_schedule_host:
		light_schedule_host.visible = false
	if emission_schedule_host:
		emission_schedule_host.visible = false
	var cam_lbl := targets.get_node_or_null("CameraLabel") if targets else null
	if cam_lbl is CanvasItem:
		(cam_lbl as CanvasItem).visible = false
	for btn in [target_lights, rotation_target_lights, noise_target_lights, particles_target_lights, particles_target_media]:
		if btn:
			btn.visible = false


func _setup_cloth_gravity() -> void:
	return


func _setup_camera_lens_control() -> void:
	camera_fx_focal_slider.min_value = 1.0
	camera_fx_focal_slider.max_value = 800.0
	_setup_camera_focus_sliders()
	var after: Node = camera_fx_focal_slider.get_parent()
	if after == null or after == camera_fx_body:
		after = camera_fx_focal_slider
	_camera_fx_lens_label = Label.new()
	_camera_fx_lens_label.text = "Lens distortion"
	camera_fx_body.add_child(_camera_fx_lens_label)
	camera_fx_body.move_child(_camera_fx_lens_label, after.get_index() + 1)
	_camera_fx_lens_slider = HSlider.new()
	_camera_fx_lens_slider.min_value = 0.0
	_camera_fx_lens_slider.max_value = 100.0
	_camera_fx_lens_slider.step = 1.0
	_camera_fx_lens_slider.value = 0.0
	_camera_fx_lens_slider.tooltip_text = "0 = rectilinear, then fisheye, circular, equirectangular wrap."
	_camera_fx_lens_slider.value_changed.connect(_on_camera_fx_params)
	camera_fx_body.add_child(_camera_fx_lens_slider)
	camera_fx_body.move_child(_camera_fx_lens_slider, _camera_fx_lens_label.get_index() + 1)
	SliderSpinLinkScr.attach_driven(_camera_fx_lens_slider, _on_camera_fx_params, 100.0)
	if camera_fx_bokeh_slider:
		camera_fx_bokeh_slider.tooltip_text = "Scales disc blur. Aperture (f-stop) is the main smear: lower f = more blur."
	if camera_fx_aperture_slider:
		camera_fx_aperture_slider.tooltip_text = "Lower f-number = shallower DoF / more blur. Higher f-stop = more in focus."


func _setup_camera_focus_sliders() -> void:
	if camera_fx_focus_label:
		camera_fx_focus_label.text = "Focus near (m)"
		camera_fx_focus_label.tooltip_text = "Closer than this is blurred. Hero is often around 3 m."
	if camera_fx_focus_slider:
		camera_fx_focus_slider.visible = true
		camera_fx_focus_slider.min_value = SceneMeshFx.CAM_FOCUS_NEAR_MIN
		camera_fx_focus_slider.max_value = SceneMeshFx.CAM_FOCUS_FAR_MAX
		camera_fx_focus_slider.step = 0.1
		camera_fx_focus_slider.tooltip_text = "Closer than this (very near the camera) is blurred."
	if camera_fx_focus_far_label:
		camera_fx_focus_far_label.text = "Focus far (m)"
		camera_fx_focus_far_label.tooltip_text = "Leave at max (80) for infinity — background stays sharp. Pull in to soften the rest."
	if camera_fx_focus_far_slider:
		camera_fx_focus_far_slider.min_value = SceneMeshFx.CAM_FOCUS_NEAR_MIN
		camera_fx_focus_far_slider.max_value = SceneMeshFx.CAM_FOCUS_FAR_MAX
		camera_fx_focus_far_slider.step = 0.1
		camera_fx_focus_far_slider.tooltip_text = "Leave at max for infinity — background stays sharp. Pull in to soften the rest."
	if camera_fx_falloff_slider:
		camera_fx_falloff_slider.tooltip_text = "How gradually focus fades into blur. Higher makes a longer, softer focus gradient; lower creates a sharper cutoff."


func _setup_point_cloud_targets() -> void:
	## Main / Scatter / Outer only — same 3D layers wireframe covers in the flythrough.
	if point_cloud_size_slider:
		point_cloud_size_slider.min_value = 1.0
		point_cloud_size_slider.max_value = 64.0
		point_cloud_size_slider.tooltip_text = "Vertex size in pixels (Godot point_size). Visible dots; drag to grow."
	var size_lbl := point_cloud_body.get_node_or_null("PointCloudSizeLabel") as Label
	if size_lbl:
		size_lbl.text = "Vertex size"
	_pc_target_label = Label.new()
	_pc_target_label.text = "Affects"
	_pc_target_label.tooltip_text = "Which 3D layers become points: Main, Scatter, Outer."
	point_cloud_body.add_child(_pc_target_label)
	var after: Node = point_cloud_size_slider.get_parent()
	if after == null or after == point_cloud_body:
		after = point_cloud_size_slider
	point_cloud_body.move_child(_pc_target_label, after.get_index() + 1)
	_pc_target_row = HBoxContainer.new()
	_pc_target_row.add_theme_constant_override("separation", 8)
	point_cloud_body.add_child(_pc_target_row)
	point_cloud_body.move_child(_pc_target_row, _pc_target_label.get_index() + 1)
	var specs: Array = [
		["main", "Main", "Centerpiece"],
		["scatter", "Scatter", "Scattered objects"],
		["environment", "Outer", "Environment / outer world"],
	]
	for spec in specs:
		var id := str(spec[0])
		var btn := CheckButton.new()
		btn.text = str(spec[1])
		btn.tooltip_text = str(spec[2])
		btn.button_pressed = true
		btn.toggled.connect(func(_v: bool) -> void: _on_point_cloud_params())
		_pc_target_row.add_child(btn)
		_pc_target_checks[id] = btn


func _pc_target_on(id: String) -> bool:
	var btn := _live_check(_pc_target_checks.get(id))
	if btn == null:
		return true
	return btn.button_pressed


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
	if ascii_density_label:
		ascii_density_label.text = "Density"
		ascii_density_label.tooltip_text = "Glyph density. Type or paste bass * 80, or pick from Driver."

	var hosts := {
		"ascii": ascii_schedule_host,
		"feedback": feedback_schedule_host,
		"glitch": glitch_schedule_host,
		"chromatic": chromatic_schedule_host,
		"wireframe": wireframe_schedule_host,
		"point_cloud": point_cloud_schedule_host,
		"camera_fx": camera_fx_schedule_host,
		"react_scale": scale_schedule_host,
		"react_light": light_schedule_host,
		"react_emission": emission_schedule_host,
		"react_rotation": rotation_schedule_host,
		"react_noise": noise_schedule_host,
		"react_camera": camera_schedule_host,
	}
	if nonlinear_camera_schedule_host:
		hosts["react_bend"] = nonlinear_camera_schedule_host
	if hole_schedule_host:
		hosts["hole"] = hole_schedule_host
	if tone_schedule_host:
		hosts["tone"] = tone_schedule_host
	if material_override_schedule_host:
		hosts["material_override"] = material_override_schedule_host
	if fog_schedule_host:
		hosts["fog"] = fog_schedule_host
	for eid in hosts.keys():
		var host: VBoxContainer = hosts[eid]
		if host == null:
			continue
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


func _setup_ascii_density_driver() -> void:
	## Live density (number or expression). Dual-range host stays hidden (random window).
	_ascii_density_slider = HSlider.new()
	_ascii_density_slider.min_value = 1.0
	_ascii_density_slider.max_value = 200.0
	_ascii_density_slider.step = 1.0
	_ascii_density_slider.value = _user_density_max
	_ascii_density_slider.tooltip_text = "ASCII glyph density. Type or paste bass * 80, or pick from Driver."
	ascii_body.add_child(_ascii_density_slider)
	ascii_body.move_child(_ascii_density_slider, ascii_density_host.get_index())


func _ascii_density_is_expr() -> bool:
	if _ascii_density_slider == null:
		return false
	return DriverExprScr.looks_like_expr(SliderSpinLinkScr.expr_of(_ascii_density_slider))


func _fill_driver(opt: OptionButton) -> void:
	opt.clear()
	for label in DRIVER_LABELS:
		opt.add_item(label)


func _fill_fx_drive(opt: OptionButton) -> void:
	opt.clear()
	for i in FX_DRIVE_LABELS.size():
		opt.add_item(FX_DRIVE_LABELS[i])
		opt.set_item_tooltip(i, FX_DRIVE_TOOLTIPS[i])
	opt.select(0)
	opt.tooltip_text = "Audio = live sound. LFO = oscillator. Static = hold current sliders (not director automation)."
	var p: Node = opt.get_parent()
	if p:
		var idx: int = opt.get_index()
		if idx > 0:
			var prev_lab := _live_label(p.get_child(idx - 1))
			if prev_lab:
				prev_lab.tooltip_text = opt.tooltip_text


func _fx_drive_mode(opt: OptionButton) -> String:
	var i := opt.selected
	if i < 0 or i >= FX_DRIVE_IDS.size():
		return "audio"
	return FX_DRIVE_IDS[i]


func _refresh_effect_if_on(effect_id: String) -> void:
	_sync_fx_lfo_ui()
	match effect_id:
		"ascii":
			if ascii_toggle.button_pressed:
				ShowDirector.set_effect("ascii", true, _ascii_params())
		"feedback":
			if feedback_toggle.button_pressed:
				ShowDirector.set_effect("feedback", true, _feedback_params())
		"glitch":
			if glitch_toggle.button_pressed:
				ShowDirector.set_effect("glitch", true, _glitch_params())
		"chromatic":
			if chromatic_toggle.button_pressed:
				ShowDirector.set_effect("chromatic", true, _chromatic_params())
		"tone":
			if tone_toggle and tone_toggle.button_pressed:
				ShowDirector.set_effect("tone", true, _tone_params())
		"hole":
			if hole_toggle and hole_toggle.button_pressed:
				ShowDirector.set_effect("hole", true, _hole_params())
		"wireframe":
			if wireframe_toggle.button_pressed:
				ShowDirector.set_effect("wireframe", true, _wireframe_params())
		"point_cloud":
			if point_cloud_toggle.button_pressed:
				ShowDirector.set_effect("point_cloud", true, _point_cloud_params())
		"camera_fx":
			if camera_fx_toggle.button_pressed:
				ShowDirector.set_effect("camera_fx", true, _camera_fx_params())
		"material_override":
			if material_override_toggle and material_override_toggle.button_pressed:
				ShowDirector.set_effect("material_override", true, _material_override_params())
		"fog":
			if fog_toggle and fog_toggle.button_pressed:
				ShowDirector.set_effect("fog", true, _fog_params())


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
	# Keep Camera motion toggle in sync with Off / non-Off.
	var want_on := index > 0
	if camera_motion_toggle.button_pressed != want_on:
		camera_motion_toggle.set_pressed_no_signal(want_on)
	_sync_conditional_ui()


func _setup_spectrum_bars() -> void:
	## ColorRect columns — ProgressBar FILL_BOTTOM_TO_TOP often paints blank in tight HBoxes.
	_spectrum_bar_nodes.clear()
	for child in spectrum_bars.get_children():
		spectrum_bars.remove_child(child)
		child.free()
	spectrum_bars.custom_minimum_size = Vector2(0, SPECTRUM_BAR_H)
	for i in 16:
		var host := Control.new()
		host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		host.size_flags_vertical = Control.SIZE_EXPAND_FILL
		host.custom_minimum_size = Vector2(3, SPECTRUM_BAR_H)
		var bg := ColorRect.new()
		bg.color = SPECTRUM_BAR_BG
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(bg)
		var bar := ColorRect.new()
		bar.color = SPECTRUM_BAR_COLOR
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchor(SIDE_LEFT, 0.0)
		bar.set_anchor(SIDE_RIGHT, 1.0)
		bar.set_anchor(SIDE_BOTTOM, 1.0)
		bar.set_anchor(SIDE_TOP, 1.0)
		bar.offset_left = 0.0
		bar.offset_right = 0.0
		bar.offset_bottom = 0.0
		bar.offset_top = 0.0
		host.add_child(bar)
		spectrum_bars.add_child(host)
		_spectrum_bar_nodes.append(bar)


func _setup_input_level_meter() -> void:
	## ColorRect fill — ProgressBar theme fill is often invisible without a custom StyleBox.
	if input_level_bar == null:
		return
	input_level_bar.min_value = 0.0
	input_level_bar.max_value = 1.0
	input_level_bar.show_percentage = false
	input_level_bar.tooltip_text = "Live capture level, peak-normalized. Empty = silence; typical music fills the bar."
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = SPECTRUM_BAR_COLOR
	fill_sb.set_corner_radius_all(2)
	input_level_bar.add_theme_stylebox_override("fill", fill_sb)
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = SPECTRUM_BAR_BG
	bg_sb.set_corner_radius_all(2)
	input_level_bar.add_theme_stylebox_override("background", bg_sb)
	var bg := ColorRect.new()
	bg.color = SPECTRUM_BAR_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input_level_bar.add_child(bg)
	_input_level_fill = ColorRect.new()
	_input_level_fill.color = SPECTRUM_BAR_COLOR
	_input_level_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_input_level_fill.set_anchor(SIDE_LEFT, 0.0)
	_input_level_fill.set_anchor(SIDE_TOP, 0.0)
	_input_level_fill.set_anchor(SIDE_BOTTOM, 1.0)
	_input_level_fill.set_anchor(SIDE_RIGHT, 0.0)
	_input_level_fill.offset_left = 0.0
	_input_level_fill.offset_top = 0.0
	_input_level_fill.offset_bottom = 0.0
	_input_level_fill.offset_right = 0.0
	input_level_bar.add_child(_input_level_fill)
	if intensity_slider:
		intensity_slider.tooltip_text = "Overall drive of reactive outputs. 0 = almost still. Default 2. Kick ON value also scales with this."
	if sensitivity_slider:
		sensitivity_slider.tooltip_text = "How easily bass/mids/highs (and kick) cross into motion. Higher = quieter hits still fire."
	if noise_floor_slider:
		noise_floor_slider.max_value = 0.25
		noise_floor_slider.tooltip_text = "Noise Floor Gate (noise gain). Raise to ignore mic hiss / room noise so volume stays at 0 when nothing is happening. If a mic hears the speakers, raise this. Does not change the Graph Equalizer shape, only reactivity."


func _setup_audio_source_picker() -> void:
	## One dropdown, one status line. No banners, no call-to-action buttons.
	if reactivity_body:
		var label := reactivity_body.get_node_or_null("InputDeviceLabel") as Label
		if label:
			label.visible = true
			label.text = "Audio Source"
		var row := reactivity_body.get_node_or_null("InputDeviceRow") as CanvasItem
		if row:
			row.visible = true
	if refresh_devices_btn:
		refresh_devices_btn.visible = false
	if input_device_option == null:
		return
	input_device_option.visible = true
	input_device_option.tooltip_text = "Which microphone signal drives the visualizer. Music uses an unprocessed capture so the mic can hear speakers; Voice uses the Windows speech-tuned mic."
	_fill_audio_sources()
	input_device_option.item_selected.connect(_on_audio_source_selected)
	AudioAnalyzer.audio_sources_changed.connect(_fill_audio_sources)


func _fill_audio_sources() -> void:
	if input_device_option == null:
		return
	var sources: Array = AudioAnalyzer.get_audio_sources()
	var current: String = AudioAnalyzer.get_audio_source()
	input_device_option.clear()
	_audio_source_ids.clear()
	for i in sources.size():
		var src: Dictionary = sources[i]
		input_device_option.add_item(String(src.get("label", "")), i)
		_audio_source_ids.append(String(src.get("id", "")))
		if String(src.get("id", "")) == current:
			input_device_option.select(i)


func _on_audio_source_selected(index: int) -> void:
	if index < 0 or index >= _audio_source_ids.size():
		return
	AudioAnalyzer.set_audio_source(_audio_source_ids[index])


func _on_devices_changed(_devices: PackedStringArray) -> void:
	pass


func _on_capture_status(status: String) -> void:
	if capture_status_label == null:
		return
	capture_status_label.text = status
	capture_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	capture_status_label.modulate = Color.WHITE


func _on_audio(state: AudioState) -> void:
	var level := clampf(state.input_level, 0.0, 1.0)
	if input_level_bar:
		input_level_bar.value = level
	if _input_level_fill:
		_input_level_fill.anchor_right = level
	energy_bar.value = clampf(state.energy, 0.0, 1.0)
	bass_bar.value = clampf(state.bass, 0.0, 1.0)
	if mids_bar:
		mids_bar.value = clampf(state.mids, 0.0, 1.0)
	if highs_bar:
		highs_bar.value = clampf(state.highs, 0.0, 1.0)
	var n := mini(_spectrum_bar_nodes.size(), state.bands.size())
	for i in n:
		var v := clampf(state.bands[i], 0.0, 1.0)
		# Grow from the bottom: top offset = -(height * value).
		_spectrum_bar_nodes[i].offset_top = -SPECTRUM_BAR_H * v
	if play_all_toggle.button_pressed and _auto_mode_is_play_all() and play_audio_reactive.button_pressed:
		ShowDirector.fx_automation.set_play_all_audio_energy(clampf(state.energy, 0.0, 1.0))


func _on_reactivity_toggled(enabled: bool) -> void:
	RH.set_enabled(enabled)
	if not enabled:
		ShowDirector.restore_reactive_poses()
	_sync_conditional_ui()


func _on_reset_to_defaults() -> void:
	var playlist := get_node_or_null("../PlaylistSidebar")
	if playlist != null and playlist.has_method("reset_all_to_defaults"):
		playlist.call("reset_all_to_defaults")
	else:
		ShowDirector.reset_stage_to_defaults()
	_sync_all_widgets_after_defaults_reset()


func _setup_preset_ui() -> void:
	_setup_preset_action_row()
	_setup_preset_name_dialog()
	_setup_preset_manager_dialog()
	_setup_preset_delete_dialog()
	_refresh_play_preset_menu()


func _setup_preset_action_row() -> void:
	if reset_defaults_btn == null or not is_instance_valid(reset_defaults_btn):
		return
	var col := reset_defaults_btn.get_parent()
	if col == null:
		return
	var idx := reset_defaults_btn.get_index()
	_preset_actions = HBoxContainer.new()
	_preset_actions.name = "HeaderActions"
	_preset_actions.add_theme_constant_override("separation", 6)
	col.add_child(_preset_actions)
	col.move_child(_preset_actions, idx)
	save_preset_btn = Button.new()
	save_preset_btn.name = "SavePresetBtn"
	save_preset_btn.text = "Save"
	save_preset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_preset_btn.custom_minimum_size = Vector2(0, 28)
	save_preset_btn.add_theme_font_size_override("font_size", FX_CONTROL_FONT_SIZE)
	save_preset_btn.tooltip_text = "Save the current effect stack as a named preset. Play it under Auto Mode → Presets."
	save_preset_btn.pressed.connect(_on_save_preset_pressed)
	_preset_actions.add_child(save_preset_btn)
	reset_defaults_btn.reparent(_preset_actions)
	reset_defaults_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_defaults_btn.custom_minimum_size = Vector2(0, 28)
	reset_defaults_btn.add_theme_font_size_override("font_size", FX_CONTROL_FONT_SIZE)


func _setup_auto_mode_section() -> void:
	## One Auto Mode accordion: radios choose Presets vs Play All; only that branch's settings show.
	if play_all_toggle == null or play_all_body == null:
		return
	if auto_mode_presets_radio != null and is_instance_valid(auto_mode_presets_radio):
		return

	play_all_toggle.text = "Auto Mode"
	play_all_toggle.tooltip_text = "Drive effects automatically. Presets = one saved look. Play All = full default stack."

	play_all_settings = VBoxContainer.new()
	play_all_settings.name = "PlayAllSettings"
	play_all_settings.add_theme_constant_override("separation", 4)
	var existing: Array = play_all_body.get_children()
	for c_any in existing:
		var child: Node = c_any as Node
		if child:
			child.reparent(play_all_settings)

	_auto_mode_group = ButtonGroup.new()
	var mode_row := HBoxContainer.new()
	mode_row.name = "AutoModeBranchRow"
	mode_row.add_theme_constant_override("separation", 12)
	auto_mode_presets_radio = CheckBox.new()
	auto_mode_presets_radio.name = "AutoModePresets"
	auto_mode_presets_radio.text = "Presets"
	auto_mode_presets_radio.button_group = _auto_mode_group
	auto_mode_presets_radio.tooltip_text = "Play one saved snapshot. Extra effects stay off."
	auto_mode_play_all_radio = CheckBox.new()
	auto_mode_play_all_radio.name = "AutoModePlayAll"
	auto_mode_play_all_radio.text = "Play All"
	auto_mode_play_all_radio.button_group = _auto_mode_group
	auto_mode_play_all_radio.button_pressed = true
	auto_mode_play_all_radio.tooltip_text = "Enable the full default effect stack (mode, audio, schedules)."
	mode_row.add_child(auto_mode_presets_radio)
	mode_row.add_child(auto_mode_play_all_radio)

	play_preset_body = VBoxContainer.new()
	play_preset_body.name = "PlayPresetBody"
	play_preset_body.add_theme_constant_override("separation", 4)
	var lab := Label.new()
	lab.name = "PlayPresetLabel"
	lab.text = "Preset"
	play_preset_menu = OptionButton.new()
	play_preset_menu.name = "PlayPresetMenu"
	play_preset_menu.fit_to_longest_item = false
	play_preset_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_preset_menu.tooltip_text = "Choose a saved look. Only those effects play — not the full Play All stack."
	play_preset_menu.item_selected.connect(_on_play_preset_selected)
	play_preset_body.add_child(lab)
	play_preset_body.add_child(play_preset_menu)

	play_all_body.add_child(mode_row)
	play_all_body.add_child(play_preset_body)
	play_all_body.add_child(play_all_settings)

	auto_mode_presets_radio.toggled.connect(_on_auto_mode_presets_toggled)
	auto_mode_play_all_radio.toggled.connect(_on_auto_mode_play_all_toggled)
	_sync_auto_mode_panels()


func _auto_mode_on() -> bool:
	return play_all_toggle != null and play_all_toggle.button_pressed


func _auto_mode_is_presets() -> bool:
	return auto_mode_presets_radio != null and auto_mode_presets_radio.button_pressed


func _auto_mode_is_play_all() -> bool:
	return auto_mode_play_all_radio != null and auto_mode_play_all_radio.button_pressed


func _play_all_driving() -> bool:
	return _auto_mode_on() and _auto_mode_is_play_all()


func _presets_driving() -> bool:
	return _auto_mode_on() and _auto_mode_is_presets()


func _sync_auto_mode_panels() -> void:
	var presets_on := _auto_mode_is_presets()
	if play_preset_body:
		play_preset_body.visible = presets_on
	if play_all_settings:
		play_all_settings.visible = not presets_on


func _on_auto_mode_presets_toggled(on: bool) -> void:
	if not on or _auto_mode_branch_busy:
		return
	_on_auto_mode_branch_changed()


func _on_auto_mode_play_all_toggled(on: bool) -> void:
	if not on or _auto_mode_branch_busy:
		return
	_on_auto_mode_branch_changed()


func _on_auto_mode_branch_changed() -> void:
	_sync_auto_mode_panels()
	if not _auto_mode_on():
		return
	if _auto_mode_is_presets():
		_stop_play_all_keep_look()
		var key := _selected_play_preset_name()
		if key.is_empty():
			_sync_conditional_ui()
			return
		var data: Dictionary = FxPresetStoreScr.get_preset(key)
		if data.is_empty():
			_sync_conditional_ui()
			return
		_apply_fx_preset(data)
		_sync_conditional_ui()
		return
	# Play All branch — never keep a named preset selected as if it were playing.
	_clear_play_preset_selection()
	_enable_default_play_all_stack()


func _set_auto_mode_branch_presets(on: bool) -> void:
	if auto_mode_presets_radio == null or auto_mode_play_all_radio == null:
		return
	_auto_mode_branch_busy = true
	if on:
		auto_mode_presets_radio.button_pressed = true
	else:
		auto_mode_play_all_radio.button_pressed = true
	_auto_mode_branch_busy = false
	_sync_auto_mode_panels()


func _setup_preset_name_dialog() -> void:
	_preset_dialog = AcceptDialog.new()
	_preset_dialog.title = "Save preset"
	_preset_dialog.ok_button_text = "Save"
	_preset_dialog.min_size = Vector2(320, 120)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	var nlab := Label.new()
	nlab.text = "Name"
	body.add_child(nlab)
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = "My look"
	body.add_child(_preset_name)
	_preset_dialog.add_child(body)
	_preset_dialog.register_text_enter(_preset_name)
	_preset_dialog.confirmed.connect(_on_preset_name_confirmed)
	add_child(_preset_dialog)


func _setup_preset_delete_dialog() -> void:
	_preset_delete_dialog = ConfirmationDialog.new()
	_preset_delete_dialog.title = "Delete preset"
	_preset_delete_dialog.ok_button_text = "Delete"
	_preset_delete_dialog.confirmed.connect(_on_preset_delete_confirmed)
	add_child(_preset_delete_dialog)


func _setup_preset_manager_dialog() -> void:
	_preset_manager_dialog = AcceptDialog.new()
	_preset_manager_dialog.title = "Edit presets"
	_preset_manager_dialog.ok_button_text = "Done"
	_preset_manager_dialog.min_size = Vector2(460, 320)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(420, 240)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preset_manager_list = VBoxContainer.new()
	_preset_manager_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_manager_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_preset_manager_list)
	_preset_manager_dialog.add_child(scroll)
	add_child(_preset_manager_dialog)


func _open_preset_manager() -> void:
	if _preset_manager_dialog == null:
		return
	_rebuild_preset_manager()
	_preset_manager_dialog.popup_centered()


func _rebuild_preset_manager() -> void:
	if _preset_manager_list == null:
		return
	for child in _preset_manager_list.get_children():
		child.queue_free()
	var names: PackedStringArray = FxPresetStoreScr.list_names()
	if names.is_empty():
		var empty := Label.new()
		empty.text = "No saved presets yet. Save a look from the Effects panel to add one."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_preset_manager_list.add_child(empty)
		return
	for preset_name_any in names:
		var preset_name := str(preset_name_any)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_edit := LineEdit.new()
		name_edit.text = preset_name
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.tooltip_text = "Change the name, then choose Rename."
		var rename_btn := Button.new()
		rename_btn.text = "Rename"
		rename_btn.pressed.connect(func() -> void:
			_on_preset_rename_pressed(preset_name, name_edit)
		)
		var delete_btn := Button.new()
		delete_btn.text = "Delete"
		delete_btn.tooltip_text = "Delete this preset. A confirmation is required."
		delete_btn.pressed.connect(func() -> void:
			_request_preset_delete(preset_name)
		)
		row.add_child(name_edit)
		row.add_child(rename_btn)
		row.add_child(delete_btn)
		_preset_manager_list.add_child(row)


func _on_preset_rename_pressed(old_name: String, name_edit: LineEdit) -> void:
	if name_edit == null:
		return
	var new_name := name_edit.text.strip_edges()
	if new_name.is_empty() or new_name == old_name:
		return
	var selected := _selected_play_preset_name()
	if not FxPresetStoreScr.rename_preset(old_name, new_name):
		push_warning("Effects: could not rename preset '%s'. Names must be unique." % old_name)
		return
	_refresh_play_preset_menu(new_name if selected == old_name else selected)
	_rebuild_preset_manager()


func _request_preset_delete(key: String) -> void:
	if key.is_empty() or _preset_delete_dialog == null:
		return
	_preset_delete_key = key
	_preset_delete_dialog.dialog_text = "Delete the preset '%s'? This cannot be undone." % key
	_preset_delete_dialog.popup_centered()


func _restore_preset_menu_selection() -> void:
	# Opening the manager is an action, not a preset choice. Return to the first/current preset.
	_refresh_play_preset_menu()


func _on_save_preset_pressed() -> void:
	if _preset_dialog == null or _preset_name == null:
		return
	_preset_name.text = ""
	_preset_dialog.popup_centered()
	_preset_name.grab_focus()


func _on_preset_name_confirmed() -> void:
	if _preset_name == null:
		return
	var key := _preset_name.text.strip_edges()
	if key.is_empty():
		return
	if not FxPresetStoreScr.save_preset(key, _capture_fx_preset()):
		push_warning("Effects: could not save preset '%s'" % key)
		return
	var select := key
	# If Play All is driving, do not display the new name as if that look were playing.
	if _play_all_driving():
		select = ""
	_refresh_play_preset_menu(select)
	_rebuild_preset_manager()


func _refresh_play_preset_menu(select_name: String = "") -> void:
	if play_preset_menu == null:
		return
	var current := _selected_play_preset_name()
	_preset_menu_busy = true
	play_preset_menu.clear()
	var names: PackedStringArray = FxPresetStoreScr.list_names()
	if names.is_empty():
		play_preset_menu.add_item(EDIT_PRESETS_MENU_ITEM)
		play_preset_menu.disabled = false
		play_preset_menu.select(0)
		_preset_menu_busy = false
		return
	play_preset_menu.disabled = false
	for n_any in names:
		play_preset_menu.add_item(str(n_any))
	play_preset_menu.add_separator()
	play_preset_menu.add_item(EDIT_PRESETS_MENU_ITEM)
	var wanted := select_name if not select_name.is_empty() else current
	var select_idx := 0
	for i in names.size():
		if str(names[i]) == wanted:
			select_idx = i
			break
	play_preset_menu.select(select_idx)
	_preset_menu_busy = false


func _on_play_preset_selected(index: int) -> void:
	if _preset_menu_busy or play_preset_menu == null:
		return
	if play_preset_menu.disabled:
		return
	if play_preset_menu.get_item_text(index) == EDIT_PRESETS_MENU_ITEM:
		_open_preset_manager()
		_restore_preset_menu_selection()
		return
	var key := play_preset_menu.get_item_text(index).strip_edges()
	if key.is_empty():
		return
	_start_play_preset(key)


func _on_preset_delete_confirmed() -> void:
	var key := _preset_delete_key
	_preset_delete_key = ""
	if key.is_empty():
		return
	if not FxPresetStoreScr.delete_preset(key):
		push_warning("Effects: could not delete preset '%s'" % key)
		return
	_refresh_play_preset_menu()
	_rebuild_preset_manager()
	if _presets_driving():
		var next_key := _selected_play_preset_name()
		if not next_key.is_empty():
			_start_play_preset(next_key)
		else:
			_set_check_no_signal(play_all_toggle, false)
	_sync_conditional_ui()


func _start_play_preset(key: String) -> void:
	var data: Dictionary = FxPresetStoreScr.get_preset(key)
	if data.is_empty():
		return
	if _play_all_driving():
		_stop_play_all_keep_look()
	_set_auto_mode_branch_presets(true)
	_apply_fx_preset(data)
	_set_check_no_signal(play_all_toggle, true)
	_sync_conditional_ui()


func _clear_play_preset_selection() -> void:
	if play_preset_menu == null or play_preset_menu.disabled:
		return
	_preset_menu_busy = true
	play_preset_menu.select(0)
	_preset_menu_busy = false


func _capture_fx_preset() -> Dictionary:
	var fx: Dictionary = ShowDirector.export_fx_state()
	var enabled: Dictionary = {}
	if fx.get("enabled") is Dictionary:
		enabled = (fx["enabled"] as Dictionary).duplicate(true)
	var params: Dictionary = {}
	if fx.get("params") is Dictionary:
		params = (fx["params"] as Dictionary).duplicate(true)
	var toggles := {
		"ascii": ascii_toggle,
		"feedback": feedback_toggle,
		"glitch": glitch_toggle,
		"chromatic": chromatic_toggle,
		"tone": tone_toggle,
		"hole": hole_toggle,
		"wireframe": wireframe_toggle,
		"point_cloud": point_cloud_toggle,
		"camera_fx": camera_fx_toggle,
		"material_override": material_override_toggle,
		"fog": fog_toggle,
	}
	for eid in toggles.keys():
		var btn: CheckButton = toggles[eid]
		if btn:
			enabled[str(eid)] = btn.button_pressed
	params["ascii"] = _ascii_params()
	params["feedback"] = _feedback_params()
	params["glitch"] = _glitch_params()
	params["chromatic"] = _chromatic_params()
	params["tone"] = _tone_params()
	params["hole"] = _hole_params()
	params["wireframe"] = _wireframe_params()
	params["point_cloud"] = _point_cloud_params()
	params["camera_fx"] = _camera_fx_params()
	params["material_override"] = _material_override_params()
	params["fog"] = _fog_params()
	fx["enabled"] = enabled
	fx["params"] = params
	var schedules := _capture_fx_schedules()
	var play := {
		"mode": _play_mode_id(),
		"audio_reactive": play_audio_reactive.button_pressed if play_audio_reactive else false,
	}
	var deform := {}
	for field in [
		"affect_scale", "scale_x", "scale_y", "scale_z", "scale_amount", "scale_source",
		"affect_rotation", "rotation_x", "rotation_y", "rotation_z", "rotation_amount", "rotation_source",
		"affect_noise", "noise_x", "noise_y", "noise_z", "noise_amount", "noise_scale", "noise_source",
		"camera_preset", "camera_rate", "camera_depth",
		"target_main", "target_scatter", "target_environment", "target_lights",
		"rotation_target_main", "rotation_target_scatter", "rotation_target_environment",
		"rotation_target_lights", "rotation_target_camera",
		"noise_target_main", "noise_target_scatter", "noise_target_environment", "noise_target_lights",
	]:
		deform[field] = RH.get_field(str(field), null)
	deform["camera_motion"] = camera_motion_toggle.button_pressed if camera_motion_toggle else false
	deform["scale_schedule"] = scale_schedule.button_pressed if scale_schedule else false
	deform["rotation_schedule"] = rotation_schedule.button_pressed if rotation_schedule else false
	deform["noise_schedule"] = noise_schedule.button_pressed if noise_schedule else false
	deform["camera_schedule"] = camera_schedule.button_pressed if camera_schedule else false
	var drivers := {}
	var hub = _drv()
	if hub != null and hub.has_method("serialize"):
		var d: Variant = hub.call("serialize")
		if d is Dictionary:
			drivers = d
	return {
		"fx": fx,
		"play_all": play,
		"deform": deform,
		"drivers": drivers,
		"bend": _capture_bend_preset(),
		"schedules": schedules,
	}


func _capture_bend_preset() -> Dictionary:
	return {
		"on": nonlinear_camera_toggle.button_pressed if nonlinear_camera_toggle else false,
		"schedule": nonlinear_camera_schedule.button_pressed if nonlinear_camera_schedule else false,
		"strength": SliderSpinLinkScr.param_of(np_strength_slider) if np_strength_slider else 1.0,
		"near": SliderSpinLinkScr.param_of(np_start_slider) if np_start_slider else 4.0,
		"far": SliderSpinLinkScr.param_of(np_end_slider) if np_end_slider else 35.0,
		"bend": SliderSpinLinkScr.param_of(np_bend_slider) if np_bend_slider else 90.0,
		"auto_center": np_auto_center.button_pressed if np_auto_center else true,
		"lift": SliderSpinLinkScr.param_of(np_lift_slider) if np_lift_slider else 0.0,
	}


func _play_all_fx_pairs() -> Array:
	return [
		[ascii_toggle, ascii_schedule, "ascii"],
		[feedback_toggle, feedback_schedule, "feedback"],
		[glitch_toggle, glitch_schedule, "glitch"],
		[chromatic_toggle, chromatic_schedule, "chromatic"],
		[tone_toggle, tone_schedule, "tone"],
		[hole_toggle, hole_schedule, "hole"],
		[wireframe_toggle, wireframe_schedule, "wireframe"],
		[point_cloud_toggle, point_cloud_schedule, "point_cloud"],
		[camera_fx_toggle, camera_fx_schedule, "camera_fx"],
		[material_override_toggle, material_override_schedule, "material_override"],
	]


func _capture_fx_schedules() -> Dictionary:
	var schedules := {}
	for sid in _play_all_fx_pairs():
		var sched: CheckButton = sid[1]
		if sched:
			schedules[str(sid[2])] = sched.button_pressed
	if fog_schedule:
		schedules["fog"] = fog_schedule.button_pressed
	if style_switch_toggle:
		schedules["style_switch"] = style_switch_toggle.button_pressed
	return schedules


func _selected_play_preset_name() -> String:
	if play_preset_menu == null or play_preset_menu.disabled:
		return ""
	var i := play_preset_menu.selected
	if i < 0 or i >= play_preset_menu.item_count:
		return ""
	var text := play_preset_menu.get_item_text(i).strip_edges()
	if text == EDIT_PRESETS_MENU_ITEM:
		return ""
	return text


func _enabled_play_all_fx_ids(enabled: Dictionary) -> Array:
	var ids: Array = []
	for eid in ShowDirector.PLAY_ALL_FX_IDS:
		if bool(enabled.get(eid, false)):
			ids.append(eid)
	return ids


func _apply_fx_preset(data: Dictionary) -> void:
	## Restore the snapshot only. Never start Play All or force-on extra FX.
	var drv: Variant = data.get("drivers", {})
	if drv is Dictionary and _drv() != null and _drv().has_method("deserialize"):
		_drv().call("deserialize", drv)
		_rebuild_driver_cards()
	var deform: Variant = data.get("deform", {})
	if deform is Dictionary:
		_apply_deform_preset(deform as Dictionary)
	var fx: Variant = data.get("fx", {})
	if fx is Dictionary:
		ShowDirector.import_fx_state(fx as Dictionary)
		_restore_fx_sliders_from_director()
	_apply_bend_preset(data.get("bend", {}))
	var schedules: Variant = data.get("schedules", {})
	if schedules is Dictionary:
		_apply_fx_schedules(schedules as Dictionary)
	_sync_conditional_ui()


func _apply_play_all_preset_knobs(play: Dictionary) -> void:
	var mode := str(play.get("mode", "cycle"))
	# Presets saved before Audio became a separate switch fall back to Cycle.
	if mode == "audio":
		mode = "cycle"
	var mi := PLAY_MODE_IDS.find(mode)
	if play_mode and mi >= 0:
		play_mode.set_block_signals(true)
		play_mode.select(mi)
		play_mode.set_block_signals(false)
	if play_audio_reactive:
		_set_check_no_signal(play_audio_reactive, bool(play.get("audio_reactive", false)))


func _apply_deform_preset(deform: Dictionary) -> void:
	for field in deform.keys():
		var key := str(field)
		if key in ["camera_motion", "scale_schedule", "rotation_schedule", "noise_schedule", "camera_schedule"]:
			continue
		var v: Variant = deform[field]
		if v != null:
			RH.set_field(key, v)
	_syncing_ui = true
	_set_check_no_signal(affect_scale, bool(RH.get_field("affect_scale", false)))
	_set_check_no_signal(affect_rotation, bool(RH.get_field("affect_rotation", false)))
	_set_check_no_signal(affect_noise, bool(RH.get_field("affect_noise", false)))
	_set_check_no_signal(scale_x, bool(RH.get_field("scale_x", true)))
	_set_check_no_signal(scale_y, bool(RH.get_field("scale_y", true)))
	_set_check_no_signal(scale_z, bool(RH.get_field("scale_z", true)))
	_set_check_no_signal(rotation_x, bool(RH.get_field("rotation_x", true)))
	_set_check_no_signal(rotation_y, bool(RH.get_field("rotation_y", true)))
	_set_check_no_signal(rotation_z, bool(RH.get_field("rotation_z", true)))
	_set_check_no_signal(noise_x, bool(RH.get_field("noise_x", true)))
	_set_check_no_signal(noise_y, bool(RH.get_field("noise_y", true)))
	_set_check_no_signal(noise_z, bool(RH.get_field("noise_z", true)))
	_sync_target_checkboxes_from_rh()
	_select_camera_preset(str(RH.get_field("camera_preset", "Off")))
	var cam_on := bool(deform.get("camera_motion", str(RH.get_field("camera_preset", "Off")) != "Off"))
	_set_check_no_signal(camera_motion_toggle, cam_on)
	_select_driver(scale_source, str(RH.get_field("scale_source", "off")))
	_select_driver(rotation_source, str(RH.get_field("rotation_source", "highs")))
	_select_driver(noise_source, str(RH.get_field("noise_source", "bass")))
	_reset_driven_num(_scale_amount_slider, float(RH.get_field("scale_amount", 25.0)))
	if scale_amount_spin:
		scale_amount_spin.set_value_no_signal(float(RH.get_field("scale_amount", 25.0)))
	_reset_driven_num(_rotation_amount_slider, float(RH.get_field("rotation_amount", 1.0)))
	if rotation_amount_spin:
		rotation_amount_spin.set_value_no_signal(float(RH.get_field("rotation_amount", 1.0)))
	_reset_driven_num(noise_amount, float(RH.get_field("noise_amount", 2.0)))
	_reset_driven_num(noise_scale, float(RH.get_field("noise_scale", 2.0)))
	_reset_driven_num(camera_rate, clampf(float(RH.get_field("camera_rate", 0.4)) * 20.0, 1.0, 100.0))
	_reset_driven_num(camera_depth, clampf(float(RH.get_field("camera_depth", 0.75)) * 100.0, 0.0, 100.0))
	if not cam_on:
		_select_camera_preset("Off")
		RH.set_field("camera_preset", "Off")
	if deform.has("scale_schedule"):
		_set_check_no_signal(scale_schedule, bool(deform["scale_schedule"]))
		ShowDirector.fx_automation.set_gate_enabled(RH.schedule_gate_id("scale"), bool(deform["scale_schedule"]))
	if deform.has("rotation_schedule"):
		_set_check_no_signal(rotation_schedule, bool(deform["rotation_schedule"]))
		ShowDirector.fx_automation.set_gate_enabled(RH.schedule_gate_id("rotation"), bool(deform["rotation_schedule"]))
	if deform.has("noise_schedule"):
		_set_check_no_signal(noise_schedule, bool(deform["noise_schedule"]))
		ShowDirector.fx_automation.set_gate_enabled(RH.schedule_gate_id("noise"), bool(deform["noise_schedule"]))
	if deform.has("camera_schedule"):
		_set_check_no_signal(camera_schedule, bool(deform["camera_schedule"]))
		ShowDirector.fx_automation.set_gate_enabled(RH.schedule_gate_id("camera"), bool(deform["camera_schedule"]))
	_syncing_ui = false
	if not bool(RH.get_field("affect_rotation", false)):
		ShowDirector.restore_reactive_poses()


func _apply_bend_preset(raw: Variant) -> void:
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return
	var bend: Dictionary = raw
	_restore_preset_slider(np_strength_slider, bend.get("strength", 1.0))
	_restore_preset_slider(np_start_slider, bend.get("near", 4.0))
	_restore_preset_slider(np_end_slider, bend.get("far", 35.0))
	_restore_preset_slider(np_bend_slider, bend.get("bend", 90.0))
	_restore_preset_slider(np_lift_slider, bend.get("lift", 0.0))
	if np_auto_center:
		_set_check_no_signal(np_auto_center, bool(bend.get("auto_center", true)))
	var on := bool(bend.get("on", false))
	_set_check_no_signal(nonlinear_camera_toggle, on)
	if nonlinear_camera_schedule:
		_set_check_no_signal(nonlinear_camera_schedule, bool(bend.get("schedule", on)))
	_apply_nonlinear_camera(on)


func _restore_preset_slider(slider: HSlider, raw: Variant) -> void:
	if slider == null or not is_instance_valid(slider):
		return
	if raw is String:
		SliderSpinLinkScr.set_expr(slider, str(raw), false)
	else:
		_reset_driven_num(slider, float(raw))


func _sync_all_widgets_after_defaults_reset() -> void:
	## Restore every Effects control (Deform left + FxSection right) to factory defaults.
	_syncing_ui = true
	_set_check_no_signal(reactivity_toggle, false)
	_set_check_no_signal(affect_scale, false)
	_set_check_no_signal(affect_light, false)
	_set_check_no_signal(affect_emission, false)
	_set_check_no_signal(affect_rotation, false)
	_set_check_no_signal(affect_noise, false)
	_set_check_no_signal(camera_motion_toggle, false)
	_set_check_no_signal(scale_x, true)
	_set_check_no_signal(scale_y, true)
	_set_check_no_signal(scale_z, true)
	_set_check_no_signal(rotation_x, true)
	_set_check_no_signal(rotation_y, true)
	_set_check_no_signal(rotation_z, true)
	_set_check_no_signal(noise_x, true)
	_set_check_no_signal(noise_y, true)
	_set_check_no_signal(noise_z, true)
	_sync_target_checkboxes_from_rh()
	_select_camera_preset("Off")
	_reset_driven_num(_scale_amount_slider, 25.0)
	if scale_amount_spin:
		scale_amount_spin.set_value_no_signal(25.0)
	_reset_driven_num(_rotation_amount_slider, 1.0)
	if rotation_amount_spin:
		rotation_amount_spin.set_value_no_signal(1.0)
	_reset_driven_num(noise_amount, 2.0)
	_reset_driven_num(noise_scale, 2.0)
	_reset_driven_num(camera_rate, 8.0)
	_reset_driven_num(camera_depth, 75.0)
	for sched in [scale_schedule, light_schedule, emission_schedule, rotation_schedule, noise_schedule, camera_schedule, nonlinear_camera_schedule]:
		_set_check_no_signal(sched, false)
	_set_check_no_signal(play_all_toggle, false)
	_set_auto_mode_branch_presets(false)
	_clear_play_preset_selection()
	_set_check_no_signal(ascii_toggle, false)
	_set_check_no_signal(particles_toggle, false)
	_set_check_no_signal(feedback_toggle, false)
	_set_check_no_signal(glitch_toggle, false)
	_set_check_no_signal(chromatic_toggle, false)
	_set_check_no_signal(pixel_sort_toggle, false)
	_set_check_no_signal(wireframe_toggle, false)
	_set_check_no_signal(cloth_toggle, false)
	_set_check_no_signal(point_cloud_toggle, false)
	_set_check_no_signal(camera_fx_toggle, false)
	_set_check_no_signal(material_override_toggle, false)
	_set_check_no_signal(fog_toggle, false)
	_set_check_no_signal(nonlinear_camera_toggle, false)
	_reset_np_sliders_to_defaults()
	_apply_nonlinear_camera(false)
	for sched2 in [ascii_schedule, particles_schedule, feedback_schedule, glitch_schedule, chromatic_schedule, pixel_sort_schedule, wireframe_schedule, cloth_schedule, point_cloud_schedule, camera_fx_schedule, material_override_schedule, fog_schedule]:
		_set_check_no_signal(sched2, false)
	_set_check_no_signal(tone_toggle, false)
	_set_check_no_signal(tone_schedule, false)
	_reset_driven_num(tone_invert_slider, 0.0)
	_reset_driven_num(tone_brightness_slider, 100.0)
	_reset_driven_num(tone_contrast_slider, 100.0)
	_reset_driven_num(tone_saturation_slider, 100.0)
	_set_check_no_signal(hole_toggle, false)
	_set_check_no_signal(hole_schedule, false)
	_set_check_no_signal(material_override_toggle, false)
	_set_check_no_signal(material_override_schedule, false)
	_set_check_no_signal(fog_toggle, false)
	_set_check_no_signal(fog_schedule, false)
	_reset_driven_num(fog_density_slider, 32.0)
	_reset_driven_num(fog_begin_slider, 5.0)
	_reset_driven_num(fog_end_slider, 32.0)
	_reset_driven_num(fog_tint_slider, 0.0)
	if np_auto_center:
		_set_check_no_signal(np_auto_center, true)
	_reset_driven_num(np_lift_slider, 0.0)
	if material_override_look and material_override_look.item_count > 0:
		SliderSpinLinkScr.reset_choice_to_index(material_override_look, 0)
	if hole_shape and hole_shape.item_count > 0:
		hole_shape.select(0)
	_reset_driven_num(hole_strength_slider, 75.0)
	_reset_driven_num(hole_size_slider, 20.0)
	_reset_driven_num(hole_twist_slider, 0.0)
	_reset_driven_num(hole_softness_slider, 30.0)
	_reset_driven_num(hole_flow_slider, 50.0)
	_reset_driven_num(hole_cx_slider, 50.0)
	_reset_driven_num(hole_cy_slider, 50.0)
	for slot_any in _shuffle_slots.values():
		if slot_any is Dictionary:
			CycleRandomScr.reset_slot(slot_any)
	for g_any in _random_groups.values():
		if g_any is Dictionary and g_any.get("slot") is Dictionary:
			CycleRandomScr.reset_slot(g_any["slot"])
	_set_check_no_signal(style_switch_toggle, false)
	_set_check_no_signal(ascii_density_random, false)
	_set_check_no_signal(play_audio_reactive, false)
	_restore_play_all_audio_drivers()
	_set_check_no_signal(ascii_invert, false)
	_set_check_no_signal(particles_target_main, false)
	_set_check_no_signal(particles_target_scatter, false)
	_set_check_no_signal(particles_target_environment, false)
	_set_check_no_signal(particles_target_lights, false)
	_set_check_no_signal(particles_target_media, false)
	for id in _pc_target_checks.keys():
		_set_check_no_signal(_live_check(_pc_target_checks.get(id)), true)
	if play_mode and play_mode.item_count > 0:
		play_mode.select(0)
	if ascii_preset and ascii_preset.item_count > 0:
		SliderSpinLinkScr.reset_choice_to_index(ascii_preset, 0)
	if _ascii_lfo_wave and _ascii_lfo_wave.item_count > 0:
		_ascii_lfo_wave.select(0)
	_reset_driven_num(intensity_slider, 2.0)
	_reset_driven_num(sensitivity_slider, 5.0)
	_reset_driven_num(noise_floor_slider, 0.018)
	_reset_driven_num(style_interval_slider, 5.0)
	_reset_driven_num(feedback_mix_slider, FEEDBACK_DEFAULT_OPACITY)
	_reset_driven_num(feedback_persist_slider, FEEDBACK_DEFAULT_PERSISTENCE)
	_reset_driven_num(feedback_blur_slider, FEEDBACK_DEFAULT_BLUR)
	if feedback_blend and feedback_blend.item_count > 0:
		feedback_blend.select(FEEDBACK_BLEND_NAMES.find(FEEDBACK_DEFAULT_BLEND))
	_reset_driven_num(glitch_vsize_slider, 24.0)
	_reset_driven_num(glitch_amount_slider, 85.0)
	_reset_driven_num(glitch_speed_slider, 6.0)
	_reset_driven_num(glitch_hsize_slider, 48.0)
	_reset_driven_num(glitch_rgb_slider, 90.0)
	_reset_driven_num(glitch_chaos_slider, 40.0)
	_reset_driven_num(chromatic_amount_slider, 85.0)
	_reset_driven_num(pixel_sort_amount_slider, 80.0)
	_reset_driven_num(pixel_sort_threshold_slider, 35.0)
	_reset_driven_num(pixel_sort_stretch_slider, 60.0)
	_reset_driven_num(cloth_amount_slider, 70.0)
	_reset_driven_num(cloth_stiffness_slider, 55.0)
	_reset_driven_num(cloth_damping_slider, 28.0)
	_reset_driven_num(cloth_wind_slider, 55.0)
	_reset_driven_num(_cloth_gravity_slider, 100.0)
	_reset_driven_num(point_cloud_size_slider, 6.0)
	_reset_driven_num(camera_fx_focal_slider, 28.0)
	_reset_driven_num(camera_fx_aperture_slider, 2.8)
	_reset_driven_num(camera_fx_focus_slider, SceneMeshFx.CAM_FOCUS_NEAR_DEFAULT)
	_reset_driven_num(camera_fx_focus_far_slider, SceneMeshFx.CAM_FOCUS_FAR_MAX)
	_reset_driven_num(camera_fx_falloff_slider, 70.0)
	_reset_driven_num(camera_fx_bokeh_slider, 55.0)
	_reset_driven_num(_camera_fx_lens_slider, 0.0)
	_user_density_min = 8.0
	_user_density_max = 80.0
	_reset_driven_num(_ascii_density_slider, 80.0)
	if _density_range and _density_range.has_method("reset_to_defaults"):
		_density_range.reset_to_defaults(8.0, 80.0)
	for rs_any in _schedule_ranges.values():
		if rs_any != null and is_instance_valid(rs_any) and rs_any.has_method("reset_to_defaults"):
			rs_any.reset_to_defaults(4.0, 4.0)
	if intensity_slider:
		AudioAnalyzer.master_intensity = 2.0
	if sensitivity_slider:
		AudioAnalyzer.band_sensitivity = 5.0 * 0.35
	if noise_floor_slider:
		AudioAnalyzer.set_noise_floor(0.018)
	_syncing_ui = false
	_sync_conditional_ui()
	_push_driven_reactivity()


func _sync_reactivity_widgets_from_rh() -> void:
	## Alias used by stage_defaults_restored — full FX + reactivity sync.
	_sync_all_widgets_after_defaults_reset()


func _sync_conditional_ui() -> void:
	## Accordion: hide (not disable) anything that is switched off.
	## Analyzer lives on Drivers. Deform (scale/rotation/noise/camera) stays on Effects.
	if reactivity_toggle:
		reactivity_toggle.visible = false
	if reactivity_body:
		reactivity_body.visible = true

	var scale_on := affect_scale.button_pressed if affect_scale else false
	if _scale_body:
		_scale_body.visible = scale_on
	scale_schedule_host.visible = scale_on and scale_schedule.button_pressed

	var light_on := false
	if _light_body:
		_light_body.visible = light_on
	light_schedule_host.visible = false

	var emission_on := false
	if _emission_body:
		_emission_body.visible = emission_on
	emission_schedule_host.visible = false

	var rotation_on := affect_rotation.button_pressed if affect_rotation else false
	if _rotation_body:
		_rotation_body.visible = rotation_on
	rotation_schedule_host.visible = rotation_on and rotation_schedule.button_pressed

	var noise_on := affect_noise.button_pressed if affect_noise else false
	if _noise_body:
		_noise_body.visible = noise_on
	noise_schedule_host.visible = noise_on and noise_schedule.button_pressed

	var cam_on := camera_motion_toggle.button_pressed if camera_motion_toggle else false
	camera_body.visible = cam_on
	camera_schedule_host.visible = cam_on and camera_schedule.button_pressed

	ascii_body.visible = ascii_toggle.button_pressed
	style_switch_body.visible = ascii_toggle.button_pressed and style_switch_toggle.button_pressed
	feedback_body.visible = feedback_toggle.button_pressed
	glitch_body.visible = glitch_toggle.button_pressed
	chromatic_body.visible = chromatic_toggle.button_pressed
	if tone_toggle and tone_body:
		tone_body.visible = tone_toggle.button_pressed
	if hole_toggle and hole_body:
		hole_body.visible = hole_toggle.button_pressed
	wireframe_body.visible = wireframe_toggle.button_pressed
	point_cloud_body.visible = point_cloud_toggle.button_pressed
	camera_fx_body.visible = camera_fx_toggle.button_pressed
	if material_override_toggle and material_override_body:
		material_override_body.visible = material_override_toggle.button_pressed
	if fog_toggle and fog_body:
		fog_body.visible = fog_toggle.button_pressed
	if nonlinear_camera_toggle and nonlinear_camera_body:
		nonlinear_camera_body.visible = nonlinear_camera_toggle.button_pressed
	if nonlinear_camera_schedule_host and nonlinear_camera_toggle and nonlinear_camera_schedule:
		nonlinear_camera_schedule_host.visible = nonlinear_camera_toggle.button_pressed and nonlinear_camera_schedule.button_pressed
	# Keep Auto Mode's branch controls inside its expanded toggle; they are not
	# actionable until the master mode is enabled.
	play_all_body.visible = play_all_toggle.button_pressed
	_sync_auto_mode_panels()
	ascii_schedule_host.visible = ascii_toggle.button_pressed and ascii_schedule.button_pressed
	feedback_schedule_host.visible = feedback_toggle.button_pressed and feedback_schedule.button_pressed
	glitch_schedule_host.visible = glitch_toggle.button_pressed and glitch_schedule.button_pressed
	chromatic_schedule_host.visible = chromatic_toggle.button_pressed and chromatic_schedule.button_pressed
	if tone_schedule_host and tone_toggle and tone_schedule:
		tone_schedule_host.visible = tone_toggle.button_pressed and tone_schedule.button_pressed
	if hole_schedule_host and hole_toggle and hole_schedule:
		hole_schedule_host.visible = hole_toggle.button_pressed and hole_schedule.button_pressed
	wireframe_schedule_host.visible = wireframe_toggle.button_pressed and wireframe_schedule.button_pressed
	point_cloud_schedule_host.visible = point_cloud_toggle.button_pressed and point_cloud_schedule.button_pressed
	camera_fx_schedule_host.visible = camera_fx_toggle.button_pressed and camera_fx_schedule.button_pressed
	if material_override_schedule_host and material_override_toggle and material_override_schedule:
		material_override_schedule_host.visible = material_override_toggle.button_pressed and material_override_schedule.button_pressed
	if fog_schedule_host and fog_toggle and fog_schedule:
		fog_schedule_host.visible = fog_toggle.button_pressed and fog_schedule.button_pressed
	_sync_feedback_mode_ui()
	cue_container.get_parent().visible = cue_container.get_child_count() > 0
	_apply_search_filter()
	_apply_content_tab_visibility()
	_hide_deform_legacy()


func _sync_fx_lfo_ui() -> void:
	for eid in FX_IDS:
		var row_any: Variant = _fx_lfo.get(eid, null)
		if not (row_any is Dictionary):
			continue
		var row: Dictionary = row_any
		var drive := _live_option(_fx_drive_opts.get(eid))
		var on := false
		match str(eid):
			"ascii":
				on = ascii_toggle.button_pressed
			"feedback":
				on = feedback_toggle.button_pressed
			"glitch":
				on = glitch_toggle.button_pressed
			"chromatic":
				on = chromatic_toggle.button_pressed
			"tone":
				on = tone_toggle.button_pressed if tone_toggle else false
			"hole":
				on = hole_toggle.button_pressed if hole_toggle else false
			"wireframe":
				on = wireframe_toggle.button_pressed
			"point_cloud":
				on = point_cloud_toggle.button_pressed
			"camera_fx":
				on = camera_fx_toggle.button_pressed
			"material_override":
				on = material_override_toggle.button_pressed if material_override_toggle else false
			"fog":
				on = fog_toggle.button_pressed if fog_toggle else false
		var mode := ""
		if drive != null:
			mode = _fx_drive_mode(drive)
		var show_lfo := on and mode == "lfo"
		var show_audio := on and mode == "audio"
		var rate_lab := _live_canvas(row.get("rate_label"))
		if rate_lab:
			rate_lab.visible = show_lfo
		var depth_lab := _live_canvas(row.get("depth_label"))
		if depth_lab:
			depth_lab.visible = show_lfo
		var rate := _live_slider(row.get("rate"))
		if rate:
			SliderSpinLinkScr.set_row_visible(rate, show_lfo)
		var depth := _live_slider(row.get("depth"))
		if depth:
			SliderSpinLinkScr.set_row_visible(depth, show_lfo)
		var audio_lab := _live_canvas(row.get("audio_label"))
		if audio_lab:
			audio_lab.visible = show_audio
		var audio := _live_slider(row.get("audio"))
		if audio:
			SliderSpinLinkScr.set_row_visible(audio, show_audio)


func _lfo_into(effect_id: String, params: Dictionary) -> Dictionary:
	var row_any: Variant = _fx_lfo.get(effect_id, null)
	if row_any is Dictionary:
		var row: Dictionary = row_any
		var rate := _live_slider(row.get("rate"))
		if rate:
			params["lfo_rate"] = float(rate.value)
		var depth := _live_slider(row.get("depth"))
		if depth:
			params["lfo_depth"] = float(depth.value) / 100.0
		var audio := _live_slider(row.get("audio"))
		if audio:
			params["audio_sensitivity"] = clampf(
				SliderSpinLinkScr.value_of(audio) / 100.0, 0.0, 2.0
			)
	if effect_id == "ascii" and _ascii_lfo_wave:
		var wi := _ascii_lfo_wave.selected
		params["lfo_wave"] = ASCII_LFO_WAVE_IDS[wi] if wi >= 0 and wi < ASCII_LFO_WAVE_IDS.size() else "sine"
	return params


func _connect_target_checkboxes() -> void:
	target_main.toggled.connect(func(v: bool) -> void: RH.set_field("target_main", v))
	target_scatter.toggled.connect(func(v: bool) -> void: RH.set_field("target_scatter", v))
	target_environment.toggled.connect(func(v: bool) -> void: RH.set_field("target_environment", v))
	target_lights.toggled.connect(func(v: bool) -> void: RH.set_field("target_lights", v))
	rotation_target_main.toggled.connect(func(v: bool) -> void:
		RH.set_field("rotation_target_main", v)
		if not v:
			ShowDirector.restore_reactive_poses()
	)
	rotation_target_scatter.toggled.connect(func(v: bool) -> void:
		RH.set_field("rotation_target_scatter", v)
		if not v:
			ShowDirector.restore_reactive_poses()
	)
	rotation_target_environment.toggled.connect(func(v: bool) -> void:
		RH.set_field("rotation_target_environment", v)
		if not v:
			ShowDirector.restore_reactive_poses()
	)
	rotation_target_lights.toggled.connect(func(v: bool) -> void:
		RH.set_field("rotation_target_lights", v)
		if not v:
			ShowDirector.restore_reactive_poses()
	)
	rotation_target_camera.toggled.connect(func(v: bool) -> void:
		RH.set_field("rotation_target_camera", v)
		if not v:
			ShowDirector.restore_reactive_poses()
	)
	noise_target_main.toggled.connect(func(v: bool) -> void: RH.set_field("noise_target_main", v))
	noise_target_scatter.toggled.connect(func(v: bool) -> void: RH.set_field("noise_target_scatter", v))
	noise_target_environment.toggled.connect(func(v: bool) -> void: RH.set_field("noise_target_environment", v))
	noise_target_lights.toggled.connect(func(v: bool) -> void: RH.set_field("noise_target_lights", v))
	if particles_target_main:
		particles_target_main.toggled.connect(_on_particles_target_toggled)
	if particles_target_scatter:
		particles_target_scatter.toggled.connect(_on_particles_target_toggled)
	if particles_target_environment:
		particles_target_environment.toggled.connect(_on_particles_target_toggled)


func _sync_target_checkboxes_from_rh() -> void:
	_set_check_no_signal(target_main, bool(RH.get_field("target_main", false)))
	_set_check_no_signal(target_scatter, bool(RH.get_field("target_scatter", false)))
	_set_check_no_signal(target_environment, bool(RH.get_field("target_environment", false)))
	_set_check_no_signal(target_lights, bool(RH.get_field("target_lights", false)))
	_set_check_no_signal(rotation_target_main, bool(RH.get_field("rotation_target_main", false)))
	_set_check_no_signal(rotation_target_scatter, bool(RH.get_field("rotation_target_scatter", false)))
	_set_check_no_signal(rotation_target_environment, bool(RH.get_field("rotation_target_environment", false)))
	_set_check_no_signal(rotation_target_lights, bool(RH.get_field("rotation_target_lights", false)))
	_set_check_no_signal(rotation_target_camera, bool(RH.get_field("rotation_target_camera", false)))
	_set_check_no_signal(noise_target_main, bool(RH.get_field("noise_target_main", false)))
	_set_check_no_signal(noise_target_scatter, bool(RH.get_field("noise_target_scatter", false)))
	_set_check_no_signal(noise_target_environment, bool(RH.get_field("noise_target_environment", false)))
	_set_check_no_signal(noise_target_lights, bool(RH.get_field("noise_target_lights", false)))
	_set_check_no_signal(particles_target_main, bool(RH.get_field("particles_target_main", false)))
	_set_check_no_signal(particles_target_scatter, bool(RH.get_field("particles_target_scatter", false)))
	_set_check_no_signal(particles_target_environment, bool(RH.get_field("particles_target_environment", false)))
	_set_check_no_signal(particles_target_lights, bool(RH.get_field("particles_target_lights", false)))
	_set_check_no_signal(particles_target_media, bool(RH.get_field("particles_target_media", false)))


func _set_check_no_signal(btn: CheckButton, on: bool) -> void:
	if btn:
		btn.set_pressed_no_signal(on)


func _particles_target_params() -> Dictionary:
	return RH.particles_target_snapshot()


func _on_particles_target_toggled(_v: bool = false) -> void:
	pass


func _on_camera_motion_toggled(on: bool) -> void:
	if on:
		if camera_preset.selected <= 0:
			camera_preset.select(1)  # Walk
			RH.set_field("camera_preset", CAMERA_PRESETS[1])
	else:
		camera_preset.select(0)
		RH.set_field("camera_preset", "Off")
	_sync_conditional_ui()


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
	if not enabled:
		ShowDirector.restore_reactive_poses()
	_sync_conditional_ui()


func _on_affect_noise(enabled: bool) -> void:
	RH.set_field("affect_noise", enabled)
	# Noise clear happens on the next audio tick via _apply_noise_distort;
	# do not call full pose restore (that would snap active rotation).
	_sync_conditional_ui()


func _on_scale_amount(value: float) -> void:
	RH.set_scale_amount(value)


func _on_rotation_amount(value: float) -> void:
	RH.set_rotation_amount(value)


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
	if _ascii_density_slider:
		params["density"] = SliderSpinLinkScr.mapped_param(_ascii_density_slider, 1.0)
	else:
		params["density"] = lerpf(dmin, dmax, 0.5)
	if ascii_preset:
		params["style_index"] = SliderSpinLinkScr.choice_param(ascii_preset)
	return params


func _on_ascii_density_driven(_v: float = 0.0) -> void:
	if ascii_toggle.button_pressed:
		ShowDirector.set_effect("ascii", true, _ascii_params())


func _on_ascii_style_driven() -> void:
	if ascii_toggle.button_pressed:
		ShowDirector.set_effect("ascii", true, _ascii_params())


func _on_ascii_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("ascii", enabled, _ascii_params())
	_sync_conditional_ui()


func _on_ascii_preset(index: int) -> void:
	## Manual preset pick may update density; Style Switch must NOT (handled in _on_style_advanced_ui).
	if _syncing_ui:
		return
	var preset_name := ascii_preset.get_item_text(index)
	var params: Dictionary = AsciiEffect.PRESETS[preset_name].duplicate()
	var dens := float(params.get("density", 80.0))
	_user_density_min = maxf(1.0, dens * 0.65)
	_user_density_max = dens
	if _ascii_density_slider and not _ascii_density_is_expr():
		SliderSpinLinkScr.set_mapped_param(_ascii_density_slider, dens, 1.0)
	if not SliderSpinLinkScr.choice_is_expr(ascii_preset):
		SliderSpinLinkScr.set_choice_expr(ascii_preset, str(index), false)
	if _ascii_density_slider:
		params["density"] = SliderSpinLinkScr.mapped_param(_ascii_density_slider, 1.0)
	if ascii_preset:
		params["style_index"] = SliderSpinLinkScr.choice_param(ascii_preset)
	if ascii_toggle.button_pressed:
		ShowDirector.set_effect("ascii", true, _ascii_params())


func _on_density_range_changed(lo: float, hi: float) -> void:
	if ascii_density_random.button_pressed and not _syncing_ui:
		# User dragged while random on — treat as new baseline.
		pass
	if not ascii_density_random.button_pressed:
		_user_density_min = lo
		_user_density_max = hi
	ascii_density_min.value = lo
	ascii_density_max.value = hi
	if _ascii_density_slider and not _ascii_density_is_expr() and not _syncing_ui:
		SliderSpinLinkScr.set_mapped_param(_ascii_density_slider, lerpf(lo, hi, 0.5), 1.0, false)
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
	if _ascii_density_is_expr():
		return
	var a := float(randi_range(1, 160))
	var b := float(randi_range(int(a), 200))
	_syncing_ui = true
	_density_range.set_range_values(a, b)
	_syncing_ui = false
	ascii_density_min.value = a
	ascii_density_max.value = b
	if _ascii_density_slider:
		SliderSpinLinkScr.set_mapped_param(_ascii_density_slider, lerpf(a, b, 0.5), 1.0, false)
	if ascii_toggle.button_pressed:
		ShowDirector.set_effect("ascii", true, _ascii_params())


func _on_ascii_invert(enabled: bool) -> void:
	if ascii_toggle.button_pressed:
		var params := _ascii_params()
		params["invert"] = enabled
		ShowDirector.set_effect("ascii", true, params)


func _on_particles_toggled(_enabled: bool) -> void:
	pass


func _feedback_params() -> Dictionary:
	var op: Variant = SliderSpinLinkScr.mapped_param(feedback_mix_slider, 100.0)
	return {
		"intensity": 1.0,
		"mix_amount": op,
		"opacity": op,
		"persistence": SliderSpinLinkScr.mapped_param(feedback_persist_slider, 100.0),
		"blur": SliderSpinLinkScr.mapped_param(feedback_blur_slider, 100.0) if feedback_blur_slider else 0.20,
		"blend": _feedback_blend_name(),
	}


func _feedback_blend_name() -> String:
	var idx := feedback_blend.selected if feedback_blend else 0
	if idx < 0 or idx >= FEEDBACK_BLEND_NAMES.size():
		return FEEDBACK_DEFAULT_BLEND
	return str(FEEDBACK_BLEND_NAMES[idx])


func _on_feedback_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("feedback", enabled, _feedback_params())
	_sync_conditional_ui()


func _on_feedback_params(_v: float = 0.0) -> void:
	if feedback_toggle.button_pressed:
		ShowDirector.set_effect("feedback", true, _feedback_params())


func _on_feedback_drive_changed(_i: int = 0) -> void:
	_sync_feedback_mode_ui()
	_refresh_effect_if_on("feedback")


func _on_feedback_lfo_rate(_v: float) -> void:
	# Feedback-only rate — must not overwrite Camera motion Speed.
	_refresh_effect_if_on("feedback")


func _sync_feedback_mode_ui() -> void:
	if feedback_sens_slider == null:
		return
	## Shared Audio amount replaces the old Feedback-only sensitivity slider.
	SliderSpinLinkScr.set_row_visible(feedback_sens_slider, false)
	SliderSpinLinkScr.set_row_visible(feedback_lfo_rate, false)
	# Looked up by name: FeedbackBody is reparented into its nesting panel at startup.
	for lbl_name in ["FeedbackSensLabel", "FeedbackLfoRateLabel"]:
		var lbl := _live_canvas(feedback_body.get_node_or_null(lbl_name))
		if lbl:
			lbl.visible = false
	# Opacity (was Mix) + persistence always editable — Static applies them directly.
	SliderSpinLinkScr.set_row_visible(feedback_mix_slider, true)
	SliderSpinLinkScr.set_row_visible(feedback_persist_slider, true)


func _glitch_params() -> Dictionary:
	return {
		"intensity": SliderSpinLinkScr.mapped_param(glitch_amount_slider, 28.0),
		"rate": SliderSpinLinkScr.mapped_param(glitch_speed_slider, 3.0),
		"v_size": SliderSpinLinkScr.mapped_param(glitch_vsize_slider, 1.0),
		"h_size": SliderSpinLinkScr.mapped_param(glitch_hsize_slider, 1.0),
		"rgb_split": SliderSpinLinkScr.mapped_param(glitch_rgb_slider, 100.0),
		"slice_chaos": SliderSpinLinkScr.mapped_param(glitch_chaos_slider, 100.0),
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
		"amount": SliderSpinLinkScr.mapped_param(chromatic_amount_slider, 28.0),
	}


func _on_chromatic_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("chromatic", enabled, _chromatic_params())
	_sync_conditional_ui()


func _on_chromatic_params(_v: float = 0.0) -> void:
	if chromatic_toggle.button_pressed:
		ShowDirector.set_effect("chromatic", true, _chromatic_params())


func _pixel_sort_params() -> Dictionary:
	return {
		"intensity": SliderSpinLinkScr.mapped_param(pixel_sort_amount_slider, 35.0),
		"threshold": SliderSpinLinkScr.mapped_param(pixel_sort_threshold_slider, 100.0),
		"stretch": SliderSpinLinkScr.mapped_param(pixel_sort_stretch_slider, 100.0),
	}


func _on_pixel_sort_toggled(_enabled: bool) -> void:
	pass


func _on_pixel_sort_params(_v: float = 0.0) -> void:
	pass


func _wireframe_params() -> Dictionary:
	if not _play_all_audio_wireframe_expr.is_empty():
		return {"intensity": _play_all_audio_wireframe_expr}
	return {
		"intensity": 1.0,
	}


func _on_wireframe_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("wireframe", enabled, _wireframe_params())
	_sync_conditional_ui()


func _cloth_params() -> Dictionary:
	return {
		"amount": SliderSpinLinkScr.mapped_param(cloth_amount_slider, 100.0),
		"stiffness": SliderSpinLinkScr.mapped_param(cloth_stiffness_slider, 100.0),
		"damping": SliderSpinLinkScr.mapped_param(cloth_damping_slider, 100.0),
		"wind": SliderSpinLinkScr.mapped_param(cloth_wind_slider, 100.0),
		"gravity": SliderSpinLinkScr.mapped_param(_cloth_gravity_slider, 100.0) if _cloth_gravity_slider else 1.0,
	}


func _on_cloth_toggled(_enabled: bool) -> void:
	pass


func _on_cloth_params(_v: float = 0.0) -> void:
	pass


func _point_cloud_params() -> Dictionary:
	return {
		"point_size": SliderSpinLinkScr.mapped_param(point_cloud_size_slider, 1.0),
		"target_environment": _pc_target_on("environment"),
		"target_main": _pc_target_on("main"),
		"target_scatter": _pc_target_on("scatter"),
	}


func _on_point_cloud_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("point_cloud", enabled, _point_cloud_params())
	_sync_conditional_ui()


func _on_point_cloud_params(_v: float = 0.0) -> void:
	if point_cloud_toggle.button_pressed:
		ShowDirector.set_effect("point_cloud", true, _point_cloud_params())


func _camera_fx_params() -> Dictionary:
	var near_m: Variant = SliderSpinLinkScr.mapped_param(camera_fx_focus_slider, 1.0)
	var far_m: Variant = SliderSpinLinkScr.mapped_param(camera_fx_focus_far_slider, 1.0)
	return {
		"focal_length": SliderSpinLinkScr.mapped_param(camera_fx_focal_slider, 1.0),
		"aperture": SliderSpinLinkScr.mapped_param(camera_fx_aperture_slider, 1.0),
		"focus_near": near_m,
		"focus_far": far_m,
		"focus_distance": near_m,
		"focus_softness": SliderSpinLinkScr.mapped_param(camera_fx_falloff_slider, 100.0),
		"bokeh": SliderSpinLinkScr.mapped_param(camera_fx_bokeh_slider, 100.0),
		"lens_distortion": SliderSpinLinkScr.mapped_param(_camera_fx_lens_slider, 100.0) if _camera_fx_lens_slider else 0.0,
		"near_enabled": true,
		"far_enabled": not SceneMeshFx.camera_far_is_infinity(float(far_m)),
	}


func _on_camera_fx_toggled(enabled: bool) -> void:
	ShowDirector.set_effect("camera_fx", enabled, _camera_fx_params())
	_sync_conditional_ui()


func _on_camera_fx_params(_v: float = 0.0) -> void:
	if camera_fx_toggle.button_pressed:
		ShowDirector.set_effect("camera_fx", true, _camera_fx_params())


func _on_effect_schedule(effect_id: String, on: bool) -> void:
	if _syncing_ui:
		return
	var active := 6.0
	var inactive := 6.0
	if _schedule_ranges.has(effect_id):
		var rs = _schedule_ranges[effect_id]
		active = float(rs.get_active())
		inactive = float(rs.get_inactive())
	ShowDirector.fx_automation.set_gate_active_inactive(effect_id, active, inactive)
	ShowDirector.fx_automation.set_gate_enabled(effect_id, on)
	ShowDirector.refresh_effect(effect_id)
	_sync_conditional_ui()


func _on_react_schedule(property: String, on: bool) -> void:
	## Reactivity drives use react_<property> gate ids (same Active/Inactive model as post FX).
	if _syncing_ui:
		return
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
	if _syncing_ui:
		return
	ShowDirector.fx_automation.set_gate_active_inactive(effect_id, active, inactive)
	if ShowDirector.fx_automation.is_gate_enabled(effect_id):
		# Post FX refresh; reactivity gates are read live via RH.property_active.
		if not str(effect_id).begins_with("react_"):
			ShowDirector.refresh_effect(effect_id)


func _apply_play_all_schedule_state() -> void:
	## Auto Mode owns post-FX schedules. Cycle gets one sparse, phase-staggered schedule
	## per effect; Random/Evolution retain their subset scheduling but keep the rows enabled.
	ShowDirector.fx_automation.set_gate_enabled("play_all", false)
	if not _play_mode_uses_subset():
		ShowDirector.fx_automation.apply_play_all_staggered_schedules(
			PLAY_ALL_INTERNAL_ACTIVE_SEC,
			PLAY_ALL_INTERNAL_INACTIVE_SEC
		)
	_syncing_ui = true
	for sid in _play_all_fx_pairs():
		var schedule: CheckButton = sid[1]
		var effect_id := str(sid[2])
		if schedule:
			_set_check_no_signal(schedule, true)
		var range = _schedule_ranges.get(effect_id)
		if range != null and is_instance_valid(range) and range.has_method("reset_to_defaults"):
			range.reset_to_defaults(
				ShowDirector.fx_automation.get_gate_active(effect_id),
				ShowDirector.fx_automation.get_gate_inactive(effect_id)
			)
	_syncing_ui = false
	for effect_id in _play_all_schedule_eids():
		ShowDirector.refresh_effect(str(effect_id))


func _apply_fx_schedules(schedules: Dictionary) -> void:
	_syncing_ui = true
	for sid in _play_all_fx_pairs():
		var eid := str(sid[2])
		if not schedules.has(eid):
			continue
		var sched: CheckButton = sid[1]
		var on := bool(schedules[eid])
		if sched:
			_set_check_no_signal(sched, on)
		ShowDirector.fx_automation.set_gate_enabled(eid, on)
	if fog_schedule and schedules.has("fog"):
		_set_check_no_signal(fog_schedule, bool(schedules["fog"]))
		ShowDirector.fx_automation.set_gate_enabled("fog", bool(schedules["fog"]))
	if style_switch_toggle and schedules.has("style_switch"):
		var want_style := bool(schedules["style_switch"])
		_set_check_no_signal(style_switch_toggle, want_style)
		ShowDirector.fx_automation.set_style_active(want_style)
	_syncing_ui = false


func _bind_play_all_to_enabled_fx(enabled: Dictionary) -> void:
	## Play All machinery on the saved-on FX only — do not force deform / extra post-FX.
	var mode := _play_mode_id()
	var audio_on := play_audio_reactive.button_pressed if play_audio_reactive else false
	var ids: Array = _enabled_play_all_fx_ids(enabled)
	ShowDirector.fx_automation.configure_play_all(mode, 1.0, audio_on, PLAY_ALL_INTERNAL_ACTIVE_SEC, PLAY_ALL_INTERNAL_INACTIVE_SEC)
	ShowDirector.set_play_all_effects(true, PLAY_ALL_INTERNAL_ACTIVE_SEC + PLAY_ALL_INTERNAL_INACTIVE_SEC, PLAY_ALL_INTERNAL_ACTIVE_SEC, ids)
	_apply_play_all_schedule_state()
	if audio_on:
		_set_check_no_signal(play_audio_reactive, true)
		ShowDirector.fx_automation.set_play_all_audio_reactive(true)
		_apply_play_all_audio_drivers(_play_mode_shuffle_on())


func _play_all_schedule_eids() -> Array:
	var ids: Array = ShowDirector.fx_automation.get_play_all_ids()
	if not ids.is_empty():
		return ids
	var fallback: Array = []
	for eid in ShowDirector.PLAY_ALL_FX_IDS:
		fallback.append(eid)
	return fallback


func _on_play_all_toggled(on: bool) -> void:
	## Auto Mode master: Presets branch applies one snapshot; Play All enables the full stack.
	if on:
		if _auto_mode_is_presets():
			var key := _selected_play_preset_name()
			if key.is_empty():
				_sync_conditional_ui()
				return
			var data: Dictionary = FxPresetStoreScr.get_preset(key)
			if data.is_empty():
				_sync_conditional_ui()
				return
			_stop_play_all_keep_look()
			_apply_fx_preset(data)
		else:
			_clear_play_preset_selection()
			_enable_default_play_all_stack()
	else:
		_stop_play_all_keep_look()
	_sync_conditional_ui()


func _stop_play_all_keep_look() -> void:
	## Tear down Play All machinery without forcing a preset. Master FX toggles stay as-is
	## until the next Play All / Play preset / Reset.
	_restore_play_all_audio_drivers()
	ShowDirector.set_play_all_effects(false)
	ShowDirector.fx_automation.configure_play_all("cycle", 1.0, false, 4.0, 4.0)
	ShowDirector.fx_automation.set_gate_enabled("play_all", false)
	_syncing_ui = true
	ascii_schedule.button_pressed = false
	feedback_schedule.button_pressed = false
	glitch_schedule.button_pressed = false
	chromatic_schedule.button_pressed = false
	if tone_schedule:
		tone_schedule.button_pressed = false
	if hole_schedule:
		hole_schedule.button_pressed = false
	wireframe_schedule.button_pressed = false
	point_cloud_schedule.button_pressed = false
	camera_fx_schedule.button_pressed = false
	if material_override_schedule:
		material_override_schedule.button_pressed = false
	if fog_schedule:
		fog_schedule.button_pressed = false
	style_switch_toggle.button_pressed = false
	_syncing_ui = false
	ShowDirector.fx_automation.set_style_active(false)
	for eid3 in FX_IDS:
		ShowDirector.fx_automation.set_gate_enabled(eid3, false)
		ShowDirector.refresh_effect(eid3)


func _enable_default_play_all_stack() -> void:
	## Play All always means the full visual stack + deform. Never a named preset.
	var mode := _play_mode_id()
	var audio_on := play_audio_reactive.button_pressed
	_syncing_ui = true
	for sid in _play_all_fx_pairs():
		var master: CheckButton = sid[0]
		var sched: CheckButton = sid[1]
		if master:
			master.button_pressed = true
		if sched:
			sched.button_pressed = true
	style_switch_toggle.button_pressed = true
	_syncing_ui = false
	_enable_deform_for_play_all()
	ShowDirector.set_effect("ascii", true, _ascii_params())
	ShowDirector.set_effect("feedback", true, _feedback_params())
	ShowDirector.set_effect("glitch", true, _glitch_params())
	ShowDirector.set_effect("chromatic", true, _chromatic_params())
	ShowDirector.set_effect("tone", true, _tone_params())
	ShowDirector.set_effect("hole", true, _hole_params())
	ShowDirector.set_effect("wireframe", true, _wireframe_params())
	ShowDirector.set_effect("point_cloud", true, _point_cloud_params())
	ShowDirector.set_effect("camera_fx", true, _camera_fx_params())
	ShowDirector.set_effect("material_override", true, _material_override_params())
	ShowDirector.fx_automation.set_style_interval(_eval_slider_num(style_interval_slider))
	ShowDirector.fx_automation.set_style_active(true)
	ShowDirector.fx_automation.configure_play_all(mode, 1.0, audio_on, PLAY_ALL_INTERNAL_ACTIVE_SEC, PLAY_ALL_INTERNAL_INACTIVE_SEC)
	ShowDirector.set_play_all_effects(true, PLAY_ALL_INTERNAL_ACTIVE_SEC + PLAY_ALL_INTERNAL_INACTIVE_SEC, PLAY_ALL_INTERNAL_ACTIVE_SEC)
	_apply_play_all_schedule_state()
	if audio_on:
		_set_check_no_signal(play_audio_reactive, true)
		ShowDirector.fx_automation.set_play_all_audio_reactive(true)
		_apply_play_all_audio_drivers(_play_mode_shuffle_on())
	_sync_conditional_ui()


func _enable_deform_for_play_all() -> void:
	## Play All means every effect, and Deform is an effect now. Turn the rows on, give them
	## layers to act on, and enable their react_* schedules so they cycle like the post FX.
	for key in ["target_main", "target_scatter", "target_environment",
			"rotation_target_main", "rotation_target_scatter", "rotation_target_environment",
			"noise_target_main", "noise_target_scatter", "noise_target_environment"]:
		RH.set_field(key, true)
	_syncing_ui = true
	_sync_target_checkboxes_from_rh()
	_syncing_ui = false
	for pair in [[affect_scale, scale_schedule], [affect_rotation, rotation_schedule], [affect_noise, noise_schedule], [camera_motion_toggle, camera_schedule], [nonlinear_camera_toggle, nonlinear_camera_schedule]]:
		var master := _live_check(pair[0])
		var sched := _live_check(pair[1])
		if master and not master.button_pressed:
			master.button_pressed = true
		if sched and not sched.button_pressed:
			sched.button_pressed = true


func _play_mode_id() -> String:
	var i := play_mode.selected
	if i < 0 or i >= PLAY_MODE_IDS.size():
		return "cycle"
	return PLAY_MODE_IDS[i]


func _play_mode_uses_subset(mode: String = "") -> bool:
	var m := mode if mode != "" else _play_mode_id()
	return m == "random" or m == "evolution"


func _on_play_mode_selected(index: int) -> void:
	if not _play_all_driving():
		return
	var mode: String = "cycle"
	if index >= 0 and index < PLAY_MODE_IDS.size():
		mode = str(PLAY_MODE_IDS[index])
	ShowDirector.fx_automation.configure_play_all(
		mode,
		1.0,
		play_audio_reactive.button_pressed,
		PLAY_ALL_INTERNAL_ACTIVE_SEC,
		PLAY_ALL_INTERNAL_INACTIVE_SEC
	)
	_apply_play_all_schedule_state()
	for eid in _play_all_schedule_eids():
		ShowDirector.refresh_effect(str(eid))


func _on_play_audio_reactive(on: bool) -> void:
	ShowDirector.fx_automation.set_play_all_audio_reactive(on)
	if not _play_all_driving():
		return
	# Audio reactivity is independent of mode; Shuffle still cycles Cycle/Random/Evolution.
	if on:
		_apply_play_all_audio_drivers(_play_mode_shuffle_on())
	else:
		_restore_play_all_audio_drivers()


func _play_mode_shuffle_on() -> bool:
	var slot: Dictionary = _shuffle_slots.get("play_mode", {})
	var toggle: Variant = slot.get("toggle")
	return toggle is CheckButton and (toggle as CheckButton).button_pressed


func _play_all_audio_wanted() -> bool:
	if not _play_all_driving():
		return false
	if play_audio_reactive != null and play_audio_reactive.button_pressed:
		return true
	return false


func _fmt_audio_drive_expr(driver: String, scale: float) -> String:
	## Whole-number gains only. Decimal scales (0.2, 0.25) made a weak mic even quieter.
	var s := maxf(1.0, roundf(scale))
	if is_equal_approx(s, 1.0):
		return driver
	return "%s * %d" % [driver, int(s)]


func _play_all_deform_audio_targets() -> Array:
	## Deform is part of the one effect list, so Play All drives it too. Gains stay whole
	## numbers via _fmt_audio_drive_expr; these sliders are pushed every frame from
	## _push_driven_reactivity, so no per-effect refresh is needed.
	var out: Array = []
	if _scale_amount_slider:
		out.append({"kind": "slider", "slider": _scale_amount_slider, "scale": 2.0, "key": "deform_scale", "mul_max": 3.0})
	if _rotation_amount_slider:
		out.append({"kind": "slider", "slider": _rotation_amount_slider, "scale": 3.0, "key": "deform_rotation"})
	if noise_amount:
		out.append({"kind": "slider", "slider": noise_amount, "scale": 3.0, "key": "deform_noise_amount"})
	if noise_scale:
		out.append({"kind": "slider", "slider": noise_scale, "scale": 2.0, "key": "deform_noise_scale"})
	if camera_rate:
		out.append({"kind": "slider", "slider": camera_rate, "scale": 3.0, "key": "deform_camera_rate", "mul_max": 3.0})
	if camera_depth:
		out.append({"kind": "slider", "slider": camera_depth, "scale": 1.0, "key": "deform_camera_depth", "mul_max": 1.0})
	return out


func _play_all_fx_audio_targets() -> Array:
	## Play All FX driver expressions. Scale is a whole-number gain (>= 1), never 0.x.
	var out: Array = _play_all_deform_audio_targets()
	if _ascii_density_slider:
		out.append({"kind": "slider", "slider": _ascii_density_slider, "scale": 80.0, "key": "ascii_density"})
	if ascii_preset:
		out.append({"kind": "choice", "opt": ascii_preset, "scale": 8.0, "key": "ascii_style"})
	if glitch_vsize_slider:
		out.append({"kind": "slider", "slider": glitch_vsize_slider, "scale": 2.0, "key": "glitch_vsize"})
	if glitch_amount_slider:
		out.append({"kind": "slider", "slider": glitch_amount_slider, "scale": 3.0, "key": "glitch_amount"})
	if glitch_speed_slider:
		out.append({"kind": "slider", "slider": glitch_speed_slider, "scale": 2.0, "key": "glitch_speed"})
	if glitch_hsize_slider:
		out.append({"kind": "slider", "slider": glitch_hsize_slider, "scale": 2.0, "key": "glitch_hsize"})
	if glitch_rgb_slider:
		out.append({"kind": "slider", "slider": glitch_rgb_slider, "scale": 2.0, "key": "glitch_rgb"})
	if glitch_chaos_slider:
		out.append({"kind": "slider", "slider": glitch_chaos_slider, "scale": 2.0, "key": "glitch_chaos"})
	if chromatic_amount_slider:
		out.append({"kind": "slider", "slider": chromatic_amount_slider, "scale": 3.0, "key": "chromatic"})
	if hole_strength_slider:
		out.append({"kind": "slider", "slider": hole_strength_slider, "scale": 3.0, "key": "hole_strength"})
	if hole_size_slider:
		out.append({"kind": "slider", "slider": hole_size_slider, "scale": 2.0, "key": "hole_size"})
	if hole_twist_slider:
		out.append({"kind": "slider", "slider": hole_twist_slider, "scale": 25.0, "key": "hole_twist"})
	if hole_softness_slider:
		out.append({"kind": "slider", "slider": hole_softness_slider, "scale": 3.0, "key": "hole_softness"})
	if hole_flow_slider:
		out.append({"kind": "slider", "slider": hole_flow_slider, "scale": 5.0, "key": "hole_flow"})
	if hole_cx_slider:
		out.append({"kind": "slider", "slider": hole_cx_slider, "scale": 2.0, "key": "hole_cx", "mul_max": 2.0})
	if hole_cy_slider:
		out.append({"kind": "slider", "slider": hole_cy_slider, "scale": 2.0, "key": "hole_cy", "mul_max": 2.0})
	out.append({"kind": "wireframe", "scale": 2.0, "key": "wireframe"})
	if point_cloud_size_slider:
		out.append({"kind": "slider", "slider": point_cloud_size_slider, "scale": 6.0, "key": "pc_size"})
	if camera_fx_focal_slider:
		out.append({"kind": "slider", "slider": camera_fx_focal_slider, "scale": 28.0, "key": "cam_focal"})
	if camera_fx_aperture_slider:
		out.append({"kind": "slider", "slider": camera_fx_aperture_slider, "scale": 3.0, "key": "cam_aperture"})
	if camera_fx_focus_slider:
		out.append({"kind": "slider", "slider": camera_fx_focus_slider, "scale": 2.0, "key": "cam_focus_near"})
	if camera_fx_focus_far_slider:
		out.append({"kind": "slider", "slider": camera_fx_focus_far_slider, "scale": SceneMeshFx.CAM_FOCUS_FAR_MAX, "key": "cam_focus_far"})
	if camera_fx_falloff_slider:
		out.append({"kind": "slider", "slider": camera_fx_falloff_slider, "scale": 1.0, "key": "cam_focus_falloff"})
	if camera_fx_bokeh_slider:
		out.append({"kind": "slider", "slider": camera_fx_bokeh_slider, "scale": 2.0, "key": "cam_bokeh"})
	if _camera_fx_lens_slider:
		out.append({"kind": "slider", "slider": _camera_fx_lens_slider, "scale": 3.0, "key": "cam_lens"})
	if material_override_look:
		out.append({"kind": "choice", "opt": material_override_look, "scale": 4.0, "key": "mat_ov_look"})
	if np_strength_slider:
		out.append({"kind": "slider", "slider": np_strength_slider, "scale": 1.0, "key": "np_strength"})
	if np_start_slider:
		out.append({"kind": "slider", "slider": np_start_slider, "scale": 4.0, "key": "np_near"})
	if np_end_slider:
		out.append({"kind": "slider", "slider": np_end_slider, "scale": 35.0, "key": "np_far"})
	if np_bend_slider:
		out.append({"kind": "slider", "slider": np_bend_slider, "scale": 90.0, "key": "np_bend"})
	if fog_density_slider:
		out.append({"kind": "slider", "slider": fog_density_slider, "scale": 2.0, "key": "fog_density"})
	if fog_begin_slider:
		out.append({"kind": "slider", "slider": fog_begin_slider, "scale": 5.0, "key": "fog_begin"})
	if fog_end_slider:
		out.append({"kind": "slider", "slider": fog_end_slider, "scale": 32.0, "key": "fog_end"})
	if fog_tint_slider:
		out.append({"kind": "slider", "slider": fog_tint_slider, "scale": 360.0, "key": "fog_tint"})
	if np_lift_slider:
		out.append({"kind": "slider", "slider": np_lift_slider, "scale": 3.0, "key": "np_lift"})
	return out


func _snapshot_play_all_audio_drivers(targets: Array) -> void:
	_play_all_audio_snapshot.clear()
	for t_any in targets:
		if not (t_any is Dictionary):
			continue
		var t: Dictionary = t_any
		var key := str(t.get("key", ""))
		if key.is_empty():
			continue
		match str(t.get("kind", "")):
			"slider":
				var sl: HSlider = t.get("slider") as HSlider
				if sl:
					_play_all_audio_snapshot[key] = SliderSpinLinkScr.expr_of(sl)
			"choice":
				var opt: OptionButton = t.get("opt") as OptionButton
				if opt:
					_play_all_audio_snapshot[key] = SliderSpinLinkScr.choice_expr_of(opt)
			"wireframe":
				_play_all_audio_snapshot[key] = _play_all_audio_wireframe_expr


func _assign_audio_target(t: Dictionary, expr: String) -> void:
	match str(t.get("kind", "")):
		"slider":
			var sl: HSlider = t.get("slider") as HSlider
			if sl:
				SliderSpinLinkScr.set_expr(sl, expr, false)
		"choice":
			var opt: OptionButton = t.get("opt") as OptionButton
			if opt:
				SliderSpinLinkScr.set_choice_expr(opt, expr, false)
		"wireframe":
			_play_all_audio_wireframe_expr = expr


func _refresh_play_all_fx_after_audio_assign() -> void:
	if ascii_toggle and ascii_toggle.button_pressed:
		ShowDirector.set_effect("ascii", true, _ascii_params())
	if feedback_toggle and feedback_toggle.button_pressed:
		ShowDirector.set_effect("feedback", true, _feedback_params())
	if glitch_toggle and glitch_toggle.button_pressed:
		ShowDirector.set_effect("glitch", true, _glitch_params())
	if chromatic_toggle and chromatic_toggle.button_pressed:
		ShowDirector.set_effect("chromatic", true, _chromatic_params())
	if tone_toggle and tone_toggle.button_pressed:
		ShowDirector.set_effect("tone", true, _tone_params())
	if hole_toggle and hole_toggle.button_pressed:
		ShowDirector.set_effect("hole", true, _hole_params())
	if wireframe_toggle and wireframe_toggle.button_pressed:
		ShowDirector.set_effect("wireframe", true, _wireframe_params())
	if point_cloud_toggle and point_cloud_toggle.button_pressed:
		ShowDirector.set_effect("point_cloud", true, _point_cloud_params())
	if camera_fx_toggle and camera_fx_toggle.button_pressed:
		ShowDirector.set_effect("camera_fx", true, _camera_fx_params())
	if material_override_toggle and material_override_toggle.button_pressed:
		ShowDirector.set_effect("material_override", true, _material_override_params())
	if fog_toggle and fog_toggle.button_pressed:
		ShowDirector.set_effect("fog", true, _fog_params())
	if nonlinear_camera_toggle and nonlinear_camera_toggle.button_pressed:
		_apply_nonlinear_camera(true)


func _apply_play_all_audio_drivers(with_multipliers: bool) -> void:
	if not _play_all_audio_wanted():
		return
	var targets := _play_all_fx_audio_targets()
	if targets.is_empty():
		return
	if not _play_all_audio_drivers_active:
		_snapshot_play_all_audio_drivers(targets)
		_play_all_audio_drivers_active = true
	var n := PLAY_ALL_AUDIO_DRIVERS.size()
	if n <= 0:
		return
	var order: Array = []
	for i in n:
		order.append(i)
	order.shuffle()
	var di := 0
	for t_any in targets:
		if not (t_any is Dictionary):
			continue
		var t: Dictionary = t_any
		var drv := str(PLAY_ALL_AUDIO_DRIVERS[int(order[di % n])])
		di += 1
		var scale := float(t.get("scale", 1.0))
		if with_multipliers:
			var mul := float(PLAY_ALL_AUDIO_SHUFFLE_MULS[randi() % PLAY_ALL_AUDIO_SHUFFLE_MULS.size()])
			var mul_max := float(t.get("mul_max", 10.0))
			scale *= minf(mul, mul_max)
		_assign_audio_target(t, _fmt_audio_drive_expr(drv, scale))
	_refresh_play_all_fx_after_audio_assign()


func _restore_play_all_audio_drivers() -> void:
	if not _play_all_audio_drivers_active:
		_play_all_audio_wireframe_expr = ""
		return
	var targets := _play_all_fx_audio_targets()
	for t_any in targets:
		if not (t_any is Dictionary):
			continue
		var t: Dictionary = t_any
		var key := str(t.get("key", ""))
		var prev := str(_play_all_audio_snapshot.get(key, ""))
		match str(t.get("kind", "")):
			"slider":
				var sl: HSlider = t.get("slider") as HSlider
				if sl and not prev.is_empty():
					SliderSpinLinkScr.set_expr(sl, prev, false)
			"choice":
				var opt: OptionButton = t.get("opt") as OptionButton
				if opt and not prev.is_empty():
					SliderSpinLinkScr.set_choice_expr(opt, prev, false)
			"wireframe":
				_play_all_audio_wireframe_expr = prev
	_play_all_audio_snapshot.clear()
	_play_all_audio_drivers_active = false
	_refresh_play_all_fx_after_audio_assign()


func _on_play_mode_shuffle_toggled(on: bool) -> void:
	if on and _play_all_audio_wanted():
		_apply_play_all_audio_drivers(true)


func _on_style_switch_toggled(on: bool) -> void:
	if _syncing_ui:
		_sync_conditional_ui()
		return
	ShowDirector.fx_automation.set_style_interval(_eval_slider_num(style_interval_slider))
	ShowDirector.fx_automation.set_style_active(on)
	_sync_conditional_ui()


func _on_style_interval(_v: float = 0.0) -> void:
	ShowDirector.fx_automation.set_style_interval(_eval_slider_num(style_interval_slider))


func _on_style_advanced_ui(preset_name: String) -> void:
	## Cycle charset/style only — never touch user density min/max.
	## If Style is driver-driven, leave the expression (it wins every frame).
	if SliderSpinLinkScr.choice_is_expr(ascii_preset):
		if ascii_toggle.button_pressed:
			ShowDirector.set_effect("ascii", true, _ascii_params())
		return
	_syncing_ui = true
	for i in ascii_preset.item_count:
		if ascii_preset.get_item_text(i) == preset_name:
			ascii_preset.select(i)
			SliderSpinLinkScr.set_choice_expr(ascii_preset, str(i), false)
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


func _process(delta: float) -> void:
	SliderSpinLinkScr.refresh_all_previews()
	_push_driven_reactivity()
	_tick_shuffle_and_random(delta)
	_sync_nonlinear_camera_from_autoload()


func _setup_hole() -> void:
	# Anchor on a direct FxSection sibling. Anchoring on chromatic_schedule_host used an index
	# from inside ChromaticBody, which dropped Hole between FeedbackToggle and FeedbackBody.
	var after: Node = chromatic_body
	if after == null or fx_section == null or after.get_parent() != fx_section:
		return
	hole_toggle = CheckButton.new()
	hole_toggle.name = "HoleToggle"
	hole_toggle.text = "Hole"
	hole_toggle.tooltip_text = "Stretch the frame into a hole, then breathe back out. Distorts the 3D view; ASCII can still overlay."
	fx_section.add_child(hole_toggle)
	fx_section.move_child(hole_toggle, after.get_index() + 1)
	hole_body = VBoxContainer.new()
	hole_body.name = "HoleBody"
	hole_body.visible = false
	hole_body.add_theme_constant_override("separation", 4)
	fx_section.add_child(hole_body)
	fx_section.move_child(hole_body, hole_toggle.get_index() + 1)
	var shape_lbl := Label.new()
	shape_lbl.text = "Shape"
	hole_body.add_child(shape_lbl)
	hole_shape = OptionButton.new()
	for n in HOLE_SHAPE_NAMES:
		hole_shape.add_item(n)
	hole_shape.select(0)
	hole_shape.item_selected.connect(_on_hole_shape)
	hole_body.add_child(hole_shape)
	hole_strength_slider = _fx_labeled_slider(hole_body, "Strength", 0.0, 100.0, 75.0)
	hole_size_slider = _fx_labeled_slider(hole_body, "Size", 5.0, 80.0, 20.0)
	hole_twist_slider = _fx_labeled_slider(hole_body, "Twist", 0.0, 100.0, 0.0)
	hole_softness_slider = _fx_labeled_slider(hole_body, "Softness", 2.0, 80.0, 30.0)
	hole_flow_slider = _fx_labeled_slider(hole_body, "Flow", 0.0, 100.0, 50.0)
	hole_cx_slider = _fx_labeled_slider(hole_body, "Offset X", 0.0, 100.0, 50.0)
	hole_cy_slider = _fx_labeled_slider(hole_body, "Offset Y", 0.0, 100.0, 50.0)
	hole_strength_slider.tooltip_text = "How far the frame falls in at peak. 0 = no warp. Type a number or pick Driver."
	hole_size_slider.tooltip_text = "Hole radius (circle) or rectangular aperture size."
	hole_twist_slider.tooltip_text = "Optional spiral on top of the stretch. Default 0 = fall-in only."
	hole_softness_slider.tooltip_text = "How wide the falloff is. Higher = softer suck at the edges."
	hole_flow_slider.tooltip_text = "How fast the collapse/emerge cycle breathes."
	hole_cx_slider.tooltip_text = "Hole center X. 50 = middle."
	hole_cy_slider.tooltip_text = "Hole center Y. 50 = middle."
	SliderSpinLinkScr.attach_driven(hole_strength_slider, _on_hole_params, 100.0)
	SliderSpinLinkScr.attach_driven(hole_size_slider, _on_hole_params, 100.0)
	SliderSpinLinkScr.attach_driven(hole_twist_slider, _on_hole_params, 25.0)
	SliderSpinLinkScr.attach_driven(hole_softness_slider, _on_hole_params, 100.0)
	SliderSpinLinkScr.attach_driven(hole_flow_slider, _on_hole_params, 100.0)
	SliderSpinLinkScr.attach_driven(hole_cx_slider, _on_hole_params, 100.0)
	SliderSpinLinkScr.attach_driven(hole_cy_slider, _on_hole_params, 100.0)
	hole_schedule = CheckButton.new()
	hole_schedule.text = "Hole schedule"
	hole_body.add_child(hole_schedule)
	hole_schedule_host = VBoxContainer.new()
	hole_schedule_host.visible = false
	hole_body.add_child(hole_schedule_host)
	hole_toggle.toggled.connect(_on_hole_toggled)
	hole_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("hole", v))


func _fx_labeled_slider(parent: VBoxContainer, title: String, lo: float, hi: float, val: float) -> HSlider:
	var lbl := Label.new()
	lbl.text = title
	parent.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 0.1
	sl.value = val
	parent.add_child(sl)
	return sl


func _style_rainbow_tint_slider(sl: HSlider) -> void:
	## Spectrum track: gray at the left (Tint 0 = no extra hue), then red→violet.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.03, 0.18, 0.34, 0.50, 0.66, 0.82, 1.0])
	grad.colors = PackedColorArray([
		FogEffect.BASE_COLOR,
		Color(0.95, 0.35, 0.32),
		Color(0.95, 0.85, 0.25),
		Color(0.35, 0.88, 0.38),
		Color(0.28, 0.85, 0.88),
		Color(0.32, 0.42, 0.92),
		Color(0.78, 0.35, 0.90),
		Color(0.92, 0.32, 0.42),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 12
	tex.fill_from = Vector2(0.0, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	sl.add_theme_stylebox_override("slider", sb)
	sl.custom_minimum_size = Vector2(0, 18)


func _np() -> Node:
	return get_node_or_null("/root/NonlinearProjection")


func _setup_nonlinear_camera() -> void:
	if fx_section == null:
		return
	nonlinear_camera_toggle = CheckButton.new()
	nonlinear_camera_toggle.name = "NonlinearCameraToggle"
	nonlinear_camera_toggle.text = "Bend space"
	nonlinear_camera_toggle.button_pressed = false
	nonlinear_camera_toggle.tooltip_text = "Near geometry stays perspective; far geometry lifts toward a top-down view. Textures stay on. Optional shortcut: F4."
	fx_section.add_child(nonlinear_camera_toggle)
	nonlinear_camera_body = VBoxContainer.new()
	nonlinear_camera_body.name = "NonlinearCameraBody"
	nonlinear_camera_body.visible = false
	nonlinear_camera_body.add_theme_constant_override("separation", 4)
	fx_section.add_child(nonlinear_camera_body)
	np_strength_slider = _fx_labeled_slider(nonlinear_camera_body, "Strength", 0.0, 2.0, 1.0)
	np_start_slider = _fx_labeled_slider(nonlinear_camera_body, "Near (m)", 0.0, 80.0, 4.0)
	np_end_slider = _fx_labeled_slider(nonlinear_camera_body, "Far (m)", 5.0, 200.0, 35.0)
	np_bend_slider = _fx_labeled_slider(nonlinear_camera_body, "Bend (°)", 0.0, 120.0, 90.0)
	np_strength_slider.step = 0.05
	np_start_slider.step = 0.5
	np_end_slider.step = 0.5
	np_bend_slider.step = 1.0
	np_strength_slider.tooltip_text = "How strong the far-field lift is. Type a number or pick Driver."
	np_start_slider.tooltip_text = "Distance where the bend starts. Nearer than this stays perspective."
	np_end_slider.tooltip_text = "Distance where the bend reaches full angle."
	np_bend_slider.tooltip_text = "Maximum pitch toward top-down at Far, in degrees."
	np_auto_center = CheckButton.new()
	np_auto_center.name = "NpAutoCenter"
	np_auto_center.text = "Auto-center main"
	np_auto_center.button_pressed = true
	np_auto_center.tooltip_text = "Keep the main item on-screen while Bend space is on, without changing its size."
	nonlinear_camera_body.add_child(np_auto_center)
	np_lift_slider = _fx_labeled_slider(nonlinear_camera_body, "Main lift (m)", 0.0, 20.0, 0.0)
	np_lift_slider.step = 0.1
	np_lift_slider.tooltip_text = "Extra camera-up offset while Bend space is on. Does not change size. Clamped so the item stays in view."
	nonlinear_camera_toggle.toggled.connect(_on_nonlinear_camera_toggled)
	np_auto_center.toggled.connect(_on_nonlinear_camera_params)
	SliderSpinLinkScr.attach_driven(np_strength_slider, _on_nonlinear_camera_params, 1.0)
	SliderSpinLinkScr.attach_driven(np_start_slider, _on_nonlinear_camera_params, 1.0)
	SliderSpinLinkScr.attach_driven(np_end_slider, _on_nonlinear_camera_params, 1.0)
	SliderSpinLinkScr.attach_driven(np_bend_slider, _on_nonlinear_camera_params, 1.0)
	SliderSpinLinkScr.attach_driven(np_lift_slider, _on_nonlinear_camera_params, 1.0)
	nonlinear_camera_schedule = CheckButton.new()
	nonlinear_camera_schedule.name = "NonlinearCameraSchedule"
	nonlinear_camera_schedule.text = "Bend space schedule"
	nonlinear_camera_schedule.tooltip_text = "When on, Bend space only applies during Active seconds. Inactive returns to the default look. Type seconds or pick Driver."
	nonlinear_camera_body.add_child(nonlinear_camera_schedule)
	nonlinear_camera_schedule_host = VBoxContainer.new()
	nonlinear_camera_schedule_host.name = "NonlinearCameraScheduleHost"
	nonlinear_camera_schedule_host.visible = false
	nonlinear_camera_body.add_child(nonlinear_camera_schedule_host)
	nonlinear_camera_schedule.toggled.connect(func(v: bool) -> void: _on_react_schedule("bend", v))


func _on_nonlinear_camera_toggled(on: bool) -> void:
	_apply_nonlinear_camera(on)
	_sync_conditional_ui()


func _on_nonlinear_camera_params(_v: float = 0.0) -> void:
	if nonlinear_camera_toggle and nonlinear_camera_toggle.button_pressed:
		_apply_nonlinear_camera(true)


func _apply_nonlinear_camera(on: bool) -> void:
	var np := _np()
	if np == null:
		return
	np.set("enabled", on)
	if np_strength_slider:
		np.set("distortion_strength", SliderSpinLinkScr.eval_of(np_strength_slider, 1.0))
	if np_start_slider:
		np.set("transition_start", SliderSpinLinkScr.eval_of(np_start_slider, 4.0))
	if np_end_slider:
		np.set("transition_end", SliderSpinLinkScr.eval_of(np_end_slider, 35.0))
	if np_bend_slider:
		np.set("max_bend_angle_deg", SliderSpinLinkScr.eval_of(np_bend_slider, 90.0))
	if np_auto_center:
		np.set("auto_center_main", np_auto_center.button_pressed)
	if np_lift_slider:
		np.set("extra_lift", SliderSpinLinkScr.eval_of(np_lift_slider, 0.0))


func _reset_np_sliders_to_defaults() -> void:
	_reset_driven_num(np_strength_slider, 1.0)
	_reset_driven_num(np_start_slider, 4.0)
	_reset_driven_num(np_end_slider, 35.0)
	_reset_driven_num(np_bend_slider, 90.0)
	if np_auto_center:
		_set_check_no_signal(np_auto_center, true)
	_reset_driven_num(np_lift_slider, 0.0)


func _sync_nonlinear_camera_from_autoload() -> void:
	var np := _np()
	if np == null or nonlinear_camera_toggle == null:
		return
	var on := bool(np.get("enabled"))
	if nonlinear_camera_toggle.button_pressed != on:
		_set_check_no_signal(nonlinear_camera_toggle, on)
		if nonlinear_camera_body:
			nonlinear_camera_body.visible = on


func _setup_material_override() -> void:
	var after: Node = camera_fx_body
	if after == null or fx_section == null or after.get_parent() != fx_section:
		return
	material_override_toggle = CheckButton.new()
	material_override_toggle.name = "MaterialOverrideToggle"
	material_override_toggle.text = "Material Override"
	material_override_toggle.tooltip_text = "Replace scene materials with cladding, metal, or normal-map look. Off restores originals."
	fx_section.add_child(material_override_toggle)
	fx_section.move_child(material_override_toggle, after.get_index() + 1)
	material_override_body = VBoxContainer.new()
	material_override_body.name = "MaterialOverrideBody"
	material_override_body.visible = false
	material_override_body.add_theme_constant_override("separation", 4)
	fx_section.add_child(material_override_body)
	fx_section.move_child(material_override_body, material_override_toggle.get_index() + 1)
	var look_lbl := Label.new()
	look_lbl.text = "Look"
	material_override_body.add_child(look_lbl)
	material_override_look = OptionButton.new()
	material_override_look.name = "MaterialOverrideLook"
	for n in MAT_OVERRIDE_LOOK_NAMES:
		material_override_look.add_item(str(n))
	material_override_look.select(0)
	material_override_look.tooltip_text = "White cladding, Chrome, Gold, Normal (normal map), Shiny black. Off restores originals. Driver maps a signal to look index (wraps)."
	material_override_look.item_selected.connect(_on_material_override_look)
	material_override_body.add_child(material_override_look)
	SliderSpinLinkScr.attach_driven_choice(material_override_look, _on_material_override_look_driven)
	material_override_schedule = CheckButton.new()
	material_override_schedule.text = "Material schedule"
	material_override_body.add_child(material_override_schedule)
	material_override_schedule_host = VBoxContainer.new()
	material_override_schedule_host.visible = false
	material_override_body.add_child(material_override_schedule_host)
	material_override_toggle.toggled.connect(_on_material_override_toggled)
	material_override_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("material_override", v))


func _material_override_look_name() -> String:
	var idx := material_override_look.selected if material_override_look else 0
	if idx < 0 or idx >= MAT_OVERRIDE_LOOK_NAMES.size():
		return "White cladding"
	return str(MAT_OVERRIDE_LOOK_NAMES[idx])


func _material_override_params() -> Dictionary:
	return {
		"look": _material_override_look_name(),
		"target_environment": true,
		"target_main": true,
		"target_scatter": true,
	}


func _on_material_override_toggled(on: bool) -> void:
	ShowDirector.set_effect("material_override", on, _material_override_params())
	_sync_conditional_ui()


func _on_material_override_look(_index: int) -> void:
	if material_override_toggle and material_override_toggle.button_pressed:
		ShowDirector.set_effect("material_override", true, _material_override_params())


func _on_material_override_look_driven() -> void:
	_on_material_override_look(material_override_look.selected if material_override_look else 0)


func _setup_fog() -> void:
	var after: Node = material_override_body
	if after == null or fx_section == null or after.get_parent() != fx_section:
		after = camera_fx_body
	if after == null or fx_section == null or after.get_parent() != fx_section:
		return
	fog_toggle = CheckButton.new()
	fog_toggle.name = "FogToggle"
	fog_toggle.text = "Fog"
	fog_toggle.tooltip_text = "Distance mist using Godot Environment fog. Off by default. Density, tint, start/end."
	fx_section.add_child(fog_toggle)
	fx_section.move_child(fog_toggle, after.get_index() + 1)
	fog_body = VBoxContainer.new()
	fog_body.name = "FogBody"
	fog_body.visible = false
	fog_body.add_theme_constant_override("separation", 4)
	fx_section.add_child(fog_body)
	fx_section.move_child(fog_body, fog_toggle.get_index() + 1)
	fog_density_slider = _fx_labeled_slider(fog_body, "Density", 0.0, 100.0, 32.0)
	fog_tint_slider = _fx_labeled_slider(fog_body, "Tint", 0.0, 360.0, 0.0)
	fog_begin_slider = _fx_labeled_slider(fog_body, "Start (m)", 0.0, 200.0, 5.0)
	fog_end_slider = _fx_labeled_slider(fog_body, "End (m)", 1.0, 400.0, 32.0)
	fog_density_slider.step = 1.0
	fog_tint_slider.step = 1.0
	fog_begin_slider.step = 0.5
	fog_end_slider.step = 0.5
	_style_rainbow_tint_slider(fog_tint_slider)
	fog_density_slider.tooltip_text = "How thick the mist is. 100 = strong visible haze (scene still readable). Type a number or pick Driver."
	fog_tint_slider.tooltip_text = "Hue of the mist. 0 = gray-white. Moving right picks a saturated color without making fog thicker."
	fog_begin_slider.tooltip_text = "Distance where fog starts. Keep this near the main item (a few meters) so mist shows in the environment."
	fog_end_slider.tooltip_text = "Distance where fog reaches full thickness. Typical rooms are tens of meters, not hundreds."
	fog_schedule = CheckButton.new()
	fog_schedule.text = "Fog schedule"
	fog_body.add_child(fog_schedule)
	fog_schedule_host = VBoxContainer.new()
	fog_schedule_host.visible = false
	fog_body.add_child(fog_schedule_host)
	fog_toggle.toggled.connect(_on_fog_toggled)
	fog_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("fog", v))
	SliderSpinLinkScr.attach_driven(fog_density_slider, _on_fog_params, 100.0)
	SliderSpinLinkScr.attach_driven(fog_tint_slider, _on_fog_params, 1.0)
	SliderSpinLinkScr.attach_driven(fog_begin_slider, _on_fog_params, 1.0)
	SliderSpinLinkScr.attach_driven(fog_end_slider, _on_fog_params, 1.0)


func _fog_params() -> Dictionary:
	return {
		"density": SliderSpinLinkScr.mapped_param(fog_density_slider, 100.0) if fog_density_slider else 0.32,
		"begin": SliderSpinLinkScr.eval_of(fog_begin_slider, 5.0) if fog_begin_slider else 5.0,
		"end": SliderSpinLinkScr.eval_of(fog_end_slider, 32.0) if fog_end_slider else 32.0,
		"tint": SliderSpinLinkScr.eval_of(fog_tint_slider, 0.0) if fog_tint_slider else 0.0,
	}


func _on_fog_toggled(on: bool) -> void:
	ShowDirector.set_effect("fog", on, _fog_params())
	_sync_conditional_ui()


func _on_fog_params(_v: float = 0.0) -> void:
	if fog_toggle and fog_toggle.button_pressed:
		ShowDirector.set_effect("fog", true, _fog_params())


func _setup_tone() -> void:
	## Image tone — Invert / Brightness / Contrast / Saturation. All four are driven sliders so every one
	## of them is audio-mappable and can join Play All.
	var after: Node = chromatic_body
	if after == null or fx_section == null or after.get_parent() != fx_section:
		return
	tone_toggle = CheckButton.new()
	tone_toggle.name = "ToneToggle"
	tone_toggle.text = "Tone"
	tone_toggle.tooltip_text = "Invert, brighten / darken, crush contrast, and shift saturation. Invert 100 = fully negative."
	fx_section.add_child(tone_toggle)
	fx_section.move_child(tone_toggle, after.get_index() + 1)
	tone_body = VBoxContainer.new()
	tone_body.name = "ToneBody"
	tone_body.visible = false
	tone_body.add_theme_constant_override("separation", 4)
	fx_section.add_child(tone_body)
	fx_section.move_child(tone_body, tone_toggle.get_index() + 1)
	tone_invert_slider = _fx_labeled_slider(tone_body, "Invert", 0.0, 100.0, 0.0)
	tone_brightness_slider = _fx_labeled_slider(tone_body, "Brightness", 0.0, 200.0, 100.0)
	tone_contrast_slider = _fx_labeled_slider(tone_body, "Contrast", 0.0, 200.0, 100.0)
	tone_saturation_slider = _fx_labeled_slider(tone_body, "Saturation", 0.0, 200.0, 100.0)
	tone_invert_slider.name = "ToneInvertSlider"
	tone_brightness_slider.name = "ToneBrightnessSlider"
	tone_contrast_slider.name = "ToneContrastSlider"
	tone_saturation_slider.name = "ToneSaturationSlider"
	tone_invert_slider.tooltip_text = "0 = untouched, 100 = fully inverted (negative). Type a number or paste bass * 2."
	tone_brightness_slider.tooltip_text = "Lightness. 100 = unchanged, below darkens, above lifts."
	tone_contrast_slider.tooltip_text = "100 = unchanged. 0 flattens to grey, higher crushes blacks and whites."
	tone_saturation_slider.tooltip_text = "Colour intensity. 0 = grayscale, 100 = unchanged, above 100 is punchier. Type a number or paste bass * 2."
	SliderSpinLinkScr.attach_driven(tone_invert_slider, _on_tone_params, 100.0)
	SliderSpinLinkScr.attach_driven(tone_brightness_slider, _on_tone_params, 100.0)
	SliderSpinLinkScr.attach_driven(tone_contrast_slider, _on_tone_params, 100.0)
	SliderSpinLinkScr.attach_driven(tone_saturation_slider, _on_tone_params, 100.0)
	tone_schedule = CheckButton.new()
	tone_schedule.text = "Tone schedule"
	tone_body.add_child(tone_schedule)
	tone_schedule_host = VBoxContainer.new()
	tone_schedule_host.visible = false
	tone_body.add_child(tone_schedule_host)
	tone_toggle.toggled.connect(_on_tone_toggled)
	tone_schedule.toggled.connect(func(v: bool) -> void: _on_effect_schedule("tone", v))


func _tone_params() -> Dictionary:
	return {
		"invert": SliderSpinLinkScr.mapped_param(tone_invert_slider, 100.0) if tone_invert_slider else 0.0,
		"brightness": SliderSpinLinkScr.mapped_param(tone_brightness_slider, 100.0) if tone_brightness_slider else 1.0,
		"contrast": SliderSpinLinkScr.mapped_param(tone_contrast_slider, 100.0) if tone_contrast_slider else 1.0,
		"saturation": SliderSpinLinkScr.mapped_param(tone_saturation_slider, 100.0) if tone_saturation_slider else 1.0,
	}


func _on_tone_toggled(on: bool) -> void:
	ShowDirector.set_effect("tone", on, _tone_params())
	_sync_conditional_ui()


func _on_tone_params(_v: float = 0.0) -> void:
	if tone_toggle and tone_toggle.button_pressed:
		ShowDirector.set_effect("tone", true, _tone_params())


func _setup_feedback_blur() -> void:
	## Blur 0 = sharp Windows-style trail. The default 20 is a light smear.
	if feedback_body == null or feedback_persist_slider == null:
		return
	var after: Node = feedback_persist_slider.get_parent()
	if after == null or after == feedback_body:
		after = feedback_persist_slider
	after = _fb_add_label(after, "FeedbackBlurLabel", "Blur amount")
	feedback_blur_slider = _fb_make_slider("FeedbackBlurSlider", 0.0, 100.0, 1.0, FEEDBACK_DEFAULT_BLUR, "0 = sharp trail (no blur or downsample): moving things stamp copies on a frozen buffer. Higher smears the trail.")
	after = _fb_add_node(after, feedback_blur_slider)
	SliderSpinLinkScr.attach_driven(feedback_blur_slider, _on_feedback_params, 100.0)
	_setup_feedback_blend(after)


func _fb_add_label(after: Node, node_name: String, text: String) -> Node:
	var lbl := Label.new()
	lbl.name = node_name
	lbl.text = text
	return _fb_add_node(after, lbl)


func _fb_make_slider(node_name: String, lo: float, hi: float, step: float, val: float, tip: String) -> HSlider:
	var sl := HSlider.new()
	sl.name = node_name
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = val
	sl.tooltip_text = tip
	return sl


func _fb_add_node(after: Node, child: Node) -> Node:
	var anchor := after
	if after != null and after.get_parent() != null and after.get_parent() != feedback_body:
		anchor = after.get_parent()
	feedback_body.add_child(child)
	if anchor != null and anchor.get_parent() == feedback_body:
		feedback_body.move_child(child, anchor.get_index() + 1)
	return child


func _setup_feedback_blend(after: Node) -> void:
	## Discrete choice, so it gets a dropdown (+ the shuffle slot every other dropdown has)
	## rather than a driven slider. Normal keeps the previous look.
	if feedback_body == null or after == null:
		return
	var lbl := _fb_add_label(after, "FeedbackBlendLabel", "Blend mode") as Label
	feedback_blend = OptionButton.new()
	feedback_blend.name = "FeedbackBlend"
	for n in FEEDBACK_BLEND_NAMES:
		feedback_blend.add_item(str(n))
	feedback_blend.select(FEEDBACK_BLEND_NAMES.find(FEEDBACK_DEFAULT_BLEND))
	feedback_blend.tooltip_text = "How the previous frame is laid over the live one. The default is Edges with Opacity 100, Persistence 100, and Blur 20. Brightest / Darkest keep whichever frame is lighter / darker. Edges = only what moved stays. Contrast = trails push lights and darks apart."
	_fb_add_node(lbl, feedback_blend)
	feedback_blend.item_selected.connect(_on_feedback_blend)


func _on_feedback_blend(_index: int) -> void:
	_refresh_effect_if_on("feedback")


func _hole_params() -> Dictionary:
	var idx := hole_shape.selected if hole_shape else 0
	var shape_name: String = "Circular"
	if idx >= 0 and idx < HOLE_SHAPE_NAMES.size():
		shape_name = str(HOLE_SHAPE_NAMES[idx])
	return {
		"shape": shape_name,
		"strength": SliderSpinLinkScr.mapped_param(hole_strength_slider, 100.0) if hole_strength_slider else 0.75,
		"hole_size": SliderSpinLinkScr.mapped_param(hole_size_slider, 100.0) if hole_size_slider else 0.20,
		"twist": SliderSpinLinkScr.mapped_param(hole_twist_slider, 25.0) if hole_twist_slider else 0.0,
		"softness": SliderSpinLinkScr.mapped_param(hole_softness_slider, 100.0) if hole_softness_slider else 0.30,
		"flow": SliderSpinLinkScr.mapped_param(hole_flow_slider, 100.0) if hole_flow_slider else 0.50,
		"center_x": SliderSpinLinkScr.mapped_param(hole_cx_slider, 100.0) if hole_cx_slider else 0.5,
		"center_y": SliderSpinLinkScr.mapped_param(hole_cy_slider, 100.0) if hole_cy_slider else 0.5,
	}


func _on_hole_toggled(on: bool) -> void:
	ShowDirector.set_effect("hole", on, _hole_params())
	_sync_conditional_ui()


func _on_hole_params(_v: float = 0.0) -> void:
	if hole_toggle and hole_toggle.button_pressed:
		ShowDirector.set_effect("hole", true, _hole_params())


func _on_hole_shape(index: int) -> void:
	if index < 0 or index >= HOLE_SHAPE_NAMES.size():
		return
	if hole_toggle and hole_toggle.button_pressed:
		ShowDirector.set_effect("hole", true, _hole_params())


func _setup_shuffle_and_random() -> void:
	if camera_body and camera_preset:
		_shuffle_slots["camera"] = CycleRandomScr.attach_shuffle(camera_body, camera_preset, "Shuffle presets")
		var cam_iv: HSlider = _shuffle_slots["camera"].get("interval")
		if cam_iv:
			SliderSpinLinkScr.attach_driven(cam_iv, Callable(), 1.0)
	if play_all_settings and play_mode:
		_shuffle_slots["play_mode"] = CycleRandomScr.attach_shuffle(play_all_settings, play_mode, "Shuffle mode")
		var pm_iv: HSlider = _shuffle_slots["play_mode"].get("interval")
		if pm_iv:
			SliderSpinLinkScr.attach_driven(pm_iv, Callable(), 1.0)
		var pm_tog: Variant = _shuffle_slots["play_mode"].get("toggle")
		if pm_tog is CheckButton:
			(pm_tog as CheckButton).tooltip_text = "Cycle Play All Mode (Cycle / Random / Evolution). With Audio reactive, also shuffles each effect's audio driver and multiplies amounts (2x-10x)."
			(pm_tog as CheckButton).toggled.connect(_on_play_mode_shuffle_toggled)
	elif play_all_body and play_mode:
		_shuffle_slots["play_mode"] = CycleRandomScr.attach_shuffle(play_all_body, play_mode, "Shuffle mode")
		var pm_iv_fallback: HSlider = _shuffle_slots["play_mode"].get("interval")
		if pm_iv_fallback:
			SliderSpinLinkScr.attach_driven(pm_iv_fallback, Callable(), 1.0)
		var pm_tog_fallback: Variant = _shuffle_slots["play_mode"].get("toggle")
		if pm_tog_fallback is CheckButton:
			(pm_tog_fallback as CheckButton).tooltip_text = "Cycle Play All Mode (Cycle / Random / Evolution). With Audio reactive, also shuffles each effect's audio driver and multiplies amounts (2x-10x)."
			(pm_tog_fallback as CheckButton).toggled.connect(_on_play_mode_shuffle_toggled)
	if hole_body and hole_shape:
		_shuffle_slots["hole"] = CycleRandomScr.attach_shuffle(hole_body, hole_shape, "Shuffle shape")
		var hole_iv: HSlider = _shuffle_slots["hole"].get("interval")
		if hole_iv:
			SliderSpinLinkScr.attach_driven(hole_iv, Callable(), 1.0)
	if material_override_body and material_override_look:
		var after_look: Node = material_override_look
		if material_override_look.get_parent() != material_override_body:
			after_look = material_override_look.get_parent()
		_shuffle_slots["material_override"] = CycleRandomScr.attach_shuffle(material_override_body, after_look, "Shuffle look")
		var mo_iv: HSlider = _shuffle_slots["material_override"].get("interval")
		if mo_iv:
			SliderSpinLinkScr.attach_driven(mo_iv, Callable(), 1.0)
	if feedback_body and feedback_blend:
		# Blend mode is an enum, so Play All varies it by shuffling the choice instead of
		# writing a driver expression onto it.
		_shuffle_slots["feedback_blend"] = CycleRandomScr.attach_shuffle(feedback_body, feedback_blend, "Shuffle blend")
		var fb_iv: HSlider = _shuffle_slots["feedback_blend"].get("interval")
		if fb_iv:
			SliderSpinLinkScr.attach_driven(fb_iv, Callable(), 1.0)
	_add_random_group("scale_affects", _scale_body, target_row, [target_main, target_scatter, target_environment], true)
	_add_random_group("scale_axes", _scale_body, scale_z.get_parent() if scale_z else null, [scale_x, scale_y, scale_z], true)
	_add_random_group("rot_affects", _rotation_body, rotation_target_row, [rotation_target_main, rotation_target_scatter, rotation_target_environment, rotation_target_camera], true)
	_add_random_group("rot_axes", _rotation_body, rotation_z.get_parent() if rotation_z else null, [rotation_x, rotation_y, rotation_z], true)
	_add_random_group("noise_affects", _noise_body, noise_target_row, [noise_target_main, noise_target_scatter, noise_target_environment], true)
	_add_random_group("noise_axes", _noise_body, noise_z.get_parent() if noise_z else null, [noise_x, noise_y, noise_z], true)
	_add_random_group("pc_affects", point_cloud_body, _pc_target_row, [
		_live_check(_pc_target_checks.get("main")),
		_live_check(_pc_target_checks.get("scatter")),
		_live_check(_pc_target_checks.get("environment")),
	], true)


func _add_random_group(id: String, parent: Control, after: Node, buttons: Array, keep_one: bool) -> void:
	if parent == null:
		return
	var slot: Dictionary = CycleRandomScr.attach_random(parent, after)
	var iv: HSlider = slot.get("interval")
	if iv:
		SliderSpinLinkScr.attach_driven(iv, Callable(), 1.0)
	_random_groups[id] = {"slot": slot, "buttons": buttons, "keep_one": keep_one}


func _tick_shuffle_and_random(delta: float) -> void:
	if CycleRandomScr.tick_slot(_shuffle_slots.get("camera", {}), delta):
		CycleRandomScr.advance_option(camera_preset, PackedInt32Array([0]))
	if CycleRandomScr.tick_slot(_shuffle_slots.get("play_mode", {}), delta):
		CycleRandomScr.advance_option(play_mode)
		if _play_all_audio_wanted():
			_apply_play_all_audio_drivers(true)
	if CycleRandomScr.tick_slot(_shuffle_slots.get("hole", {}), delta):
		if hole_shape:
			CycleRandomScr.advance_option(hole_shape)
	if CycleRandomScr.tick_slot(_shuffle_slots.get("material_override", {}), delta):
		if material_override_look:
			CycleRandomScr.advance_option(material_override_look)
	if CycleRandomScr.tick_slot(_shuffle_slots.get("feedback_blend", {}), delta):
		if feedback_blend:
			CycleRandomScr.advance_option(feedback_blend)
	for gid in _random_groups.keys():
		var g: Dictionary = _random_groups[gid]
		if CycleRandomScr.tick_slot(g.get("slot", {}), delta):
			CycleRandomScr.randomize_checks(g.get("buttons", []), bool(g.get("keep_one", true)))


func _setup_content_tabs() -> void:
	var column: VBoxContainer = $Margin/Scroll/Column
	var title: Label = $Margin/Scroll/Column/Title
	# "Effects" is already the first content tab; do not repeat it as a heading.
	title.visible = false
	_tab_bar = TabBar.new()
	_tab_bar.add_tab("Effects")
	_tab_bar.add_tab("Drivers")
	_tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_bar.custom_minimum_size = Vector2(0, 28)
	_tab_bar.add_theme_font_size_override("font_size", FX_CONTROL_FONT_SIZE)
	column.add_child(_tab_bar)
	column.move_child(_tab_bar, title.get_index() + 1)
	_tab_bar.tab_changed.connect(_on_content_tab)
	_drivers_section = VBoxContainer.new()
	_drivers_section.name = "DriversSection"
	_drivers_section.visible = false
	_drivers_section.add_theme_constant_override("separation", 8)
	column.add_child(_drivers_section)
	column.move_child(_drivers_section, fx_section.get_index() + 1)
	var hint := Label.new()
	hint.text = "Click a name (or Copy) to use it in an FX value. Audio Reactive uses only the named audio sources below; raw EQ bins are never assigned automatically."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", FX_SETTING_FONT_SIZE)
	hint.add_theme_color_override("font_color", FX_SETTING_LABEL_COLOR)
	_drivers_section.add_child(hint)
	var add_btn := Button.new()
	add_btn.text = "Add driver…"
	add_btn.add_theme_font_size_override("font_size", FX_SETTING_FONT_SIZE + 1)
	add_btn.pressed.connect(func() -> void: _open_driver_modal_for(null))
	_drivers_section.add_child(add_btn)
	var built_lbl := Label.new()
	built_lbl.text = "Sources"
	built_lbl.add_theme_font_size_override("font_size", FX_HEADER_FONT_SIZE)
	built_lbl.add_theme_color_override("font_color", FX_HEADER_COLOR)
	_drivers_section.add_child(built_lbl)
	_drivers_builtin_list = VBoxContainer.new()
	_drivers_builtin_list.add_theme_constant_override("separation", 4)
	_drivers_section.add_child(_drivers_builtin_list)
	var sig_lbl := Label.new()
	sig_lbl.text = "Modulators"
	sig_lbl.add_theme_font_size_override("font_size", FX_HEADER_FONT_SIZE)
	sig_lbl.add_theme_color_override("font_color", FX_HEADER_COLOR)
	_drivers_section.add_child(sig_lbl)
	var modulators_hint := Label.new()
	modulators_hint.text = "Editable built-ins plus any LFO, noise, or random drivers you add. Includes slow movement for gradual changes."
	modulators_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modulators_hint.add_theme_font_size_override("font_size", FX_SETTING_FONT_SIZE)
	modulators_hint.add_theme_color_override("font_color", FX_SETTING_LABEL_COLOR)
	_drivers_section.add_child(modulators_hint)
	_drivers_signal_list = VBoxContainer.new()
	_drivers_signal_list.add_theme_constant_override("separation", 8)
	_drivers_section.add_child(_drivers_signal_list)
	_rebuild_driver_cards()
	_relocate_analyzer_to_drivers()


func _move_stage_camera_controls_here() -> void:
	if fx_section == null or _stage_camera_section != null:
		return
	var playlist := get_node_or_null("../PlaylistSidebar")
	if playlist == null or not playlist.has_method("move_stage_camera_controls_to"):
		return
	_stage_camera_toggle = CheckButton.new()
	_stage_camera_toggle.name = "StageCameraToggle"
	_stage_camera_toggle.text = "Camera"
	_stage_camera_toggle.tooltip_text = "Enable or pause the fly-through camera."
	_stage_camera_toggle.add_theme_font_size_override("font_size", FX_HEADER_FONT_SIZE)
	_stage_camera_toggle.add_theme_color_override("font_color", FX_HEADER_COLOR)
	_stage_camera_toggle.add_theme_color_override("font_hover_color", FX_HEADER_COLOR)
	_stage_camera_section = VBoxContainer.new()
	_stage_camera_section.name = "StageCameraSection"
	_stage_camera_section.add_theme_constant_override("separation", 6)
	var enabled := true
	if playlist.has_method("is_stage_camera_enabled"):
		enabled = bool(playlist.call("is_stage_camera_enabled"))
	_stage_camera_toggle.button_pressed = enabled
	_stage_camera_section.visible = enabled
	fx_section.add_child(_stage_camera_toggle)
	fx_section.add_child(_stage_camera_section)
	# Keep Auto Mode at the absolute top; Camera follows its expanded body.
	fx_section.move_child(_stage_camera_toggle, 2)
	fx_section.move_child(_stage_camera_section, 3)
	playlist.call("move_stage_camera_controls_to", _stage_camera_section)
	_nest_setting_body(_stage_camera_section)
	_quiet_setting_labels(_stage_camera_section)
	_stage_camera_toggle.toggled.connect(_on_stage_camera_toggled)


func _on_stage_camera_toggled(enabled: bool) -> void:
	if _stage_camera_section:
		_stage_camera_section.visible = enabled
	var playlist := get_node_or_null("../PlaylistSidebar")
	if playlist != null and playlist.has_method("set_stage_camera_enabled"):
		playlist.call("set_stage_camera_enabled", enabled)


func _sync_stage_camera_card() -> void:
	if _stage_camera_toggle == null or not is_instance_valid(_stage_camera_toggle):
		return
	var playlist := get_node_or_null("../PlaylistSidebar")
	if playlist == null or not playlist.has_method("is_stage_camera_enabled"):
		return
	var enabled := bool(playlist.call("is_stage_camera_enabled"))
	_stage_camera_toggle.set_pressed_no_signal(enabled)
	if _stage_camera_section:
		_stage_camera_section.visible = enabled


func _relocate_analyzer_to_drivers() -> void:
	## Input + EQ live on Drivers. Deform stays on Effects.
	if reactivity_toggle:
		reactivity_toggle.visible = false
	if reactivity_body:
		for child in reactivity_body.get_children():
			var n := str(child.name)
			if n in ["ScaleAmountLabel", "ScaleAmountSpin", "EnergyBar", "BassBar", "MidsBar", "HighsBar"]:
				(child as CanvasItem).visible = false
		reactivity_body.visible = true
	if audio_section and _drivers_section:
		audio_section.reparent(_drivers_section)
		_drivers_section.move_child(audio_section, mini(1, _drivers_section.get_child_count() - 1))


func _on_content_tab(idx: int) -> void:
	_content_tab = idx
	_apply_content_tab_visibility()
	if _content_tab == 1:
		_on_driver_values()


func _apply_content_tab_visibility() -> void:
	var drivers_on := _content_tab == 1
	if _drivers_section:
		_drivers_section.visible = drivers_on
	if search_row:
		search_row.visible = not drivers_on
	if _preset_actions:
		_preset_actions.visible = not drivers_on
	elif reset_defaults_btn:
		reset_defaults_btn.visible = not drivers_on
	if audio_section:
		audio_section.visible = drivers_on
	if reactivity_toggle:
		reactivity_toggle.visible = false
	if reactivity_body:
		reactivity_body.visible = drivers_on
	if targets:
		targets.visible = false
	if fx_section:
		fx_section.visible = not drivers_on
	if fx_label:
		fx_label.visible = false
	if cue_section and drivers_on:
		cue_section.visible = false


func _live_obj(raw: Variant) -> bool:
	return raw != null and is_instance_valid(raw)


func _live_slider(raw: Variant) -> HSlider:
	if not _live_obj(raw):
		return null
	return raw as HSlider


func _live_label(raw: Variant) -> Label:
	if not _live_obj(raw):
		return null
	return raw as Label


func _live_canvas(raw: Variant) -> CanvasItem:
	if not _live_obj(raw):
		return null
	return raw as CanvasItem


func _live_option(raw: Variant) -> OptionButton:
	if not _live_obj(raw):
		return null
	return raw as OptionButton


func _live_check(raw: Variant) -> CheckButton:
	if not _live_obj(raw):
		return null
	return raw as CheckButton


func _on_driver_values() -> void:
	if _content_tab != 1:
		return
	if _drv() == null:
		return
	var dead: Array = []
	for name_any in _driver_live_labels.keys():
		var id := str(name_any)
		var v := float(_drv().get_value(id))
		var txt := _fmt_driver_live(id, v)
		var raw: Variant = _driver_live_labels[name_any]
		var any_live := false
		if raw is Array:
			var kept: Array = []
			for lab_any in raw:
				var lab := _live_label(lab_any)
				if lab == null:
					continue
				lab.text = txt
				kept.append(lab)
				any_live = true
			if any_live:
				_driver_live_labels[name_any] = kept
			else:
				dead.append(name_any)
		else:
			var lab2 := _live_label(raw)
			if lab2 == null:
				dead.append(name_any)
				continue
			lab2.text = txt
	for d in dead:
		_driver_live_labels.erase(d)


func _fmt_driver_live(name: String, v: float) -> String:
	if name == "time":
		return "%.2f" % v
	return "%.3f" % v


func _rebuild_driver_cards() -> void:
	if _drivers_builtin_list == null or _drivers_signal_list == null:
		return
	for c in _drivers_builtin_list.get_children():
		c.queue_free()
	for c2 in _drivers_signal_list.get_children():
		c2.queue_free()
	_driver_live_labels.clear()
	_driver_card_writes.clear()
	if _drv() == null:
		return
	var hints: Dictionary = {}
	for row_any in DriverHubScr.BUILTIN_HINTS:
		var row: Array = row_any as Array
		if row.size() >= 2:
			hints[str(row[0])] = str(row[1])
	for group_any in DriverHubScr.BUILTIN_GROUPS:
		var group: Array = group_any as Array
		if group.size() < 2:
			continue
		var group_label := Label.new()
		group_label.text = str(group[0])
		group_label.add_theme_font_size_override("font_size", FX_SETTING_FONT_SIZE + 1)
		group_label.add_theme_color_override("font_color", FX_SETTING_LABEL_COLOR)
		_drivers_builtin_list.add_child(group_label)
		var ids: Array = group[1] as Array
		for id_any in ids:
			var id := str(id_any)
			_drivers_builtin_list.add_child(_make_builtin_row(id, str(hints.get(id, ""))))
	for def_any in _drv().list_defs():
		if not (def_any is Dictionary):
			continue
		_drivers_signal_list.add_child(_make_signal_card(def_any as Dictionary))
	_on_driver_values()


func _copy_driver_id(id: String) -> void:
	DisplayServer.clipboard_set(id)


func _make_copy_btn(id: String) -> Button:
	var copy_btn := Button.new()
	copy_btn.text = "Copy"
	copy_btn.focus_mode = Control.FOCUS_NONE
	copy_btn.add_theme_font_size_override("font_size", FX_SETTING_FONT_SIZE)
	copy_btn.tooltip_text = "Copy '%s' to clipboard" % id
	copy_btn.pressed.connect(func() -> void: _copy_driver_id(id))
	return copy_btn


func _make_builtin_row(id: String, hint: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _setting_panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	panel.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var name_btn := Button.new()
	name_btn.text = id
	name_btn.flat = true
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.add_theme_font_size_override("font_size", FX_SETTING_FONT_SIZE + 1)
	name_btn.add_theme_color_override("font_color", FX_HEADER_COLOR)
	name_btn.add_theme_color_override("font_hover_color", FX_HEADER_COLOR)
	name_btn.tooltip_text = "Click to copy '%s'" % id
	name_btn.pressed.connect(func() -> void: _copy_driver_id(id))
	top.add_child(name_btn)
	var val := Label.new()
	val.text = "—"
	val.add_theme_font_size_override("font_size", FX_SETTING_FONT_SIZE)
	_register_live_label(id, val)
	top.add_child(val)
	top.add_child(_make_copy_btn(id))
	box.add_child(top)
	var h := Label.new()
	h.text = hint
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_theme_font_size_override("font_size", FX_SETTING_FONT_SIZE)
	h.add_theme_color_override("font_color", FX_SETTING_LABEL_COLOR)
	box.add_child(h)
	return panel


func _make_signal_card(def: Dictionary) -> Control:
	var id := str(def.get("id", ""))
	var typ := str(def.get("type", "lfo"))
	var builtin := bool(def.get("builtin", false))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _setting_panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var head := HBoxContainer.new()
	var title := Button.new()
	title.text = "%s  ·  %s" % [id, typ]
	title.flat = true
	title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", FX_SETTING_FONT_SIZE + 1)
	title.add_theme_color_override("font_color", FX_HEADER_COLOR)
	title.add_theme_color_override("font_hover_color", FX_HEADER_COLOR)
	title.tooltip_text = "Click to copy '%s'" % id
	title.pressed.connect(func() -> void: _copy_driver_id(id))
	head.add_child(title)
	var live := Label.new()
	live.text = "—"
	live.add_theme_font_size_override("font_size", FX_SETTING_FONT_SIZE)
	_register_live_label(id, live)
	head.add_child(live)
	head.add_child(_make_copy_btn(id))
	if not builtin:
		var del := Button.new()
		del.text = "×"
		del.tooltip_text = "Remove this driver"
		del.pressed.connect(func() -> void: _drv().remove_driver(id))
		head.add_child(del)
	box.add_child(head)
	match typ:
		"lfo":
			box.add_child(_driver_slider_row("Rate Hz", 0.005, 16.0, float(def.get("rate", 0.45)), func(v: float) -> void:
				_drv().update_driver(id, {"rate": v})
			))
			box.add_child(_driver_slider_row("Depth", 0.0, 1.0, float(def.get("depth", 1.0)), func(v: float) -> void:
				_drv().update_driver(id, {"depth": v})
			))
			var wave := OptionButton.new()
			for i in DriverHubScr.WAVE_LABELS.size():
				wave.add_item(DriverHubScr.WAVE_LABELS[i])
			var wi := DriverHubScr.WAVE_IDS.find(str(def.get("wave", "sine")))
			wave.select(wi if wi >= 0 else 0)
			wave.item_selected.connect(func(i: int) -> void:
				var w := "sine"
				if i >= 0 and i < DriverHubScr.WAVE_IDS.size():
					w = DriverHubScr.WAVE_IDS[i]
				_drv().update_driver(id, {"wave": w})
			)
			box.add_child(wave)
		"noise":
			box.add_child(_driver_slider_row("Speed", 0.05, 16.0, float(def.get("speed", 1.0)), func(v: float) -> void:
				_drv().update_driver(id, {"speed": v})
			))
			box.add_child(_driver_slider_row("Smooth", 0.0, 1.0, float(def.get("smoothness", 0.6)), func(v: float) -> void:
				_drv().update_driver(id, {"smoothness": v})
			))
		"random":
			box.add_child(_driver_slider_row("Rate Hz", 0.005, 16.0, float(def.get("rate", 2.0)), func(v: float) -> void:
				_drv().update_driver(id, {"rate": v})
			))
			box.add_child(_driver_slider_row("Min", 0.0, 100.0, float(def.get("min", 0.0)), func(v: float) -> void:
				_drv().update_driver(id, {"min": v})
			))
			box.add_child(_driver_slider_row("Max", 0.0, 100.0, float(def.get("max", 100.0)), func(v: float) -> void:
				_drv().update_driver(id, {"max": v})
			))
	return panel


func _driver_slider_row(label: String, lo: float, hi: float, value: float, on_change: Callable) -> Control:
	var box := VBoxContainer.new()
	var lab := Label.new()
	lab.text = label
	lab.add_theme_font_size_override("font_size", FX_SETTING_FONT_SIZE)
	lab.add_theme_color_override("font_color", FX_SETTING_LABEL_COLOR)
	box.add_child(lab)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 100.0
	sl.step = 0.1
	sl.value = _driver_to_percent(value, lo, hi)
	sl.tooltip_text = "0–100 control range (%s to %s)" % [str(snappedf(lo, 0.001)), str(snappedf(hi, 0.001))]
	box.add_child(sl)
	SliderSpinLinkScr.attach_driven(sl, func(_v: float = 0.0) -> void:
		on_change.call(_driver_from_percent(SliderSpinLinkScr.eval_of(sl), lo, hi))
	, 1.0)
	_driver_card_writes.append({"slider": sl, "cb": on_change, "lo": lo, "hi": hi})
	var sid := sl.get_instance_id()
	if not sl.has_meta("card_write_hook"):
		sl.tree_exiting.connect(_on_driver_card_slider_exiting.bind(sid))
		sl.set_meta("card_write_hook", true)
	return box


func _driver_to_percent(value: float, lo: float, hi: float) -> float:
	if is_equal_approx(lo, hi):
		return 0.0
	return clampf(inverse_lerp(lo, hi, value) * 100.0, 0.0, 100.0)


func _driver_from_percent(percent: float, lo: float, hi: float) -> float:
	return lerpf(lo, hi, clampf(percent, 0.0, 100.0) / 100.0)


func _register_live_label(id: String, lab: Label) -> void:
	if lab == null or not is_instance_valid(lab):
		return
	var key := id.strip_edges().to_lower()
	var raw: Variant = _driver_live_labels.get(key, [])
	var arr: Array = raw if raw is Array else []
	if raw != null and not (raw is Array) and _live_label(raw) != null:
		arr.append(raw)
	arr.append(lab)
	_driver_live_labels[key] = arr
	_hook_live_label(key, lab)


func _hook_live_label(id: String, lab: Label) -> void:
	if lab == null or not is_instance_valid(lab) or lab.has_meta("live_label_hook"):
		return
	lab.tree_exiting.connect(_on_driver_live_label_exiting.bind(id, lab.get_instance_id()))
	lab.set_meta("live_label_hook", true)


func _on_driver_live_label_exiting(id: String, lid: int) -> void:
	var raw: Variant = _driver_live_labels.get(id, null)
	if raw == null:
		return
	if raw is Array:
		var kept: Array = []
		for lab_any in raw:
			var lab := _live_label(lab_any)
			if lab == null or lab.get_instance_id() == lid:
				continue
			kept.append(lab)
		if kept.is_empty():
			_driver_live_labels.erase(id)
		else:
			_driver_live_labels[id] = kept
		return
	var cur := _live_label(raw)
	if cur == null or cur.get_instance_id() == lid:
		_driver_live_labels.erase(id)


func _on_driver_card_slider_exiting(sid: int) -> void:
	var kept: Array = []
	for w_any in _driver_card_writes:
		if not (w_any is Dictionary):
			continue
		var w: Dictionary = w_any
		var sl := _live_slider(w.get("slider"))
		if sl == null or sl.get_instance_id() == sid:
			continue
		kept.append(w)
	_driver_card_writes = kept


func _setup_driver_modal() -> void:
	_driver_modal = AcceptDialog.new()
	_driver_modal.title = "Create driver"
	_driver_modal.ok_button_text = "Create"
	_driver_modal.min_size = Vector2(320, 280)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	var nlab := Label.new()
	nlab.text = "Name"
	body.add_child(nlab)
	_modal_name = LineEdit.new()
	_modal_name.placeholder_text = "my_lfo"
	body.add_child(_modal_name)
	var tlab := Label.new()
	tlab.text = "Type"
	body.add_child(tlab)
	_modal_type = OptionButton.new()
	_modal_type.add_item("LFO")
	_modal_type.add_item("Noise")
	_modal_type.add_item("Random")
	_modal_type.item_selected.connect(func(_i: int) -> void: _sync_modal_type())
	body.add_child(_modal_type)
	_modal_params = VBoxContainer.new()
	_modal_params.add_theme_constant_override("separation", 4)
	body.add_child(_modal_params)
	_modal_rate = _modal_percent_spin(0.005, 16.0, 0.5)
	_modal_depth = _modal_percent_spin(0.0, 1.0, 1.0)
	_modal_wave = OptionButton.new()
	for labt in DriverHubScr.WAVE_LABELS:
		_modal_wave.add_item(labt)
	_modal_speed = _modal_percent_spin(0.05, 16.0, 1.0)
	_modal_smooth = _modal_percent_spin(0.0, 1.0, 0.65)
	_modal_rmin = _modal_percent_spin(0.0, 100.0, 0.0)
	_modal_rmax = _modal_percent_spin(0.0, 100.0, 100.0)
	_driver_modal.add_child(body)
	_driver_modal.confirmed.connect(_on_driver_modal_create)
	add_child(_driver_modal)
	_sync_modal_type()


func _modal_percent_spin(lo: float, hi: float, val: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 0.0
	s.max_value = 100.0
	s.step = 0.1
	s.value = _driver_to_percent(val, lo, hi)
	s.tooltip_text = "0–100 control range (%s to %s)" % [str(snappedf(lo, 0.001)), str(snappedf(hi, 0.001))]
	s.set_meta("vis_min", 0.0)
	s.set_meta("vis_max", 100.0)
	s.set_meta("native_min", lo)
	s.set_meta("native_max", hi)
	return s


func _modal_native_value(spin: SpinBox) -> float:
	if spin == null:
		return 0.0
	var lo := float(spin.get_meta("native_min")) if spin.has_meta("native_min") else 0.0
	var hi := float(spin.get_meta("native_max")) if spin.has_meta("native_max") else 100.0
	return _driver_from_percent(SliderSpinLinkScr.eval_spin(spin), lo, hi)


func _add_modal_driven(spin: SpinBox) -> void:
	if spin == null or _modal_params == null:
		return
	if spin.has_meta("driven_slider"):
		var sl: HSlider = spin.get_meta("driven_slider")
		if sl and sl.has_meta("driven_wrap"):
			var wrap: Node = sl.get_meta("driven_wrap")
			if wrap.get_parent() != _modal_params:
				_modal_params.add_child(wrap)
			return
	_modal_params.add_child(spin)
	var lo := float(spin.get_meta("vis_min")) if spin.has_meta("vis_min") else spin.min_value
	var hi := float(spin.get_meta("vis_max")) if spin.has_meta("vis_max") else spin.max_value
	SliderSpinLinkScr.replace_spin_with_driven(spin, Callable(), 1.0, lo, hi)


func _sync_modal_type() -> void:
	if _modal_params == null:
		return
	for c in _modal_params.get_children():
		_modal_params.remove_child(c)
	var t := _modal_type.selected if _modal_type else 0
	if t == 0:
		_modal_params.add_child(_lbl("Rate Hz"))
		_add_modal_driven(_modal_rate)
		_modal_params.add_child(_lbl("Depth"))
		_add_modal_driven(_modal_depth)
		_modal_params.add_child(_lbl("Waveform"))
		_modal_params.add_child(_modal_wave)
	elif t == 1:
		_modal_params.add_child(_lbl("Speed"))
		_add_modal_driven(_modal_speed)
		_modal_params.add_child(_lbl("Smoothness"))
		_add_modal_driven(_modal_smooth)
	else:
		_modal_params.add_child(_lbl("Rate Hz"))
		_add_modal_driven(_modal_rate)
		_modal_params.add_child(_lbl("Min"))
		_add_modal_driven(_modal_rmin)
		_modal_params.add_child(_lbl("Max"))
		_add_modal_driven(_modal_rmax)


func _drv() -> Variant:
	## Autoload singleton name is not always in script scope (new autoload / --script / class cache).
	var n := get_node_or_null("/root/DriverHub")
	if n != null:
		return n
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("DriverHub")
	return null


func _eval_slider_num(slider: HSlider) -> float:
	return SliderSpinLinkScr.eval_of(slider)


func _reset_driven_num(slider: HSlider, v: float) -> void:
	if slider == null or not is_instance_valid(slider):
		return
	SliderSpinLinkScr.reset_to_number(slider, v, false)


func _deform_num(slider: HSlider, ui_div: float = 1.0) -> float:
	## Slider range is drag-only. Expressions and typed literals keep evaluated magnitude.
	if slider == null or not is_instance_valid(slider):
		return 0.0
	var v := _eval_slider_num(slider)
	var expr := SliderSpinLinkScr.expr_of(slider)
	if DriverExprScr.looks_like_expr(expr):
		return clampf(v, -1.0e6, 1.0e6)
	if ui_div > 0.0001:
		var in_drag := v >= slider.min_value - 0.001 and v <= slider.max_value + 0.001
		if in_drag:
			v = v / ui_div
	return clampf(v, -1.0e6, 1.0e6)


func _camera_motion_rate() -> float:
	## Camera controls are percentages whether dragged, typed, or driven.
	return clampf(_eval_slider_num(camera_rate) / 20.0, 0.0, 1.0e6)


func _camera_motion_depth() -> float:
	## Do not use _deform_num here: it treated a typed 120 as a raw 120,
	## which was the source of the runaway walking motion.
	return clampf(_eval_slider_num(camera_depth) / 100.0, -1.0e6, 1.0e6)


func _lbl(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _open_driver_modal_for(control: Object) -> void:
	_driver_assign_slider = control as HSlider if control is HSlider else null
	_driver_assign_choice = control as OptionButton if control is OptionButton else null
	if _modal_name:
		_modal_name.text = ""
	if _driver_modal:
		_driver_modal.popup_centered()


func _on_driver_modal_create() -> void:
	if _drv() == null:
		return
	var t := _modal_type.selected if _modal_type else 0
	var def: Dictionary = {"id": _modal_name.text if _modal_name else "drv"}
	if t == 1:
		def["type"] = "noise"
		def["speed"] = _modal_native_value(_modal_speed)
		def["smoothness"] = _modal_native_value(_modal_smooth)
	elif t == 2:
		def["type"] = "random"
		def["rate"] = _modal_native_value(_modal_rate)
		def["min"] = _modal_native_value(_modal_rmin)
		def["max"] = _modal_native_value(_modal_rmax)
	else:
		def["type"] = "lfo"
		def["rate"] = _modal_native_value(_modal_rate)
		def["depth"] = _modal_native_value(_modal_depth)
		var wi := _modal_wave.selected if _modal_wave else 0
		def["wave"] = DriverHubScr.WAVE_IDS[wi] if wi >= 0 and wi < DriverHubScr.WAVE_IDS.size() else "sine"
	var id := str(_drv().add_driver(def))
	if _driver_assign_slider != null and is_instance_valid(_driver_assign_slider):
		SliderSpinLinkScr.set_expr(_driver_assign_slider, id, true)
	elif _driver_assign_choice != null and is_instance_valid(_driver_assign_choice):
		SliderSpinLinkScr.set_choice_expr(_driver_assign_choice, id, true)
	_driver_assign_slider = null
	_driver_assign_choice = null


func _push_driven_reactivity() -> void:
	if _drv() == null:
		return
	if is_instance_valid(_scale_amount_slider):
		RH.set_scale_amount(_deform_num(_scale_amount_slider))
	if is_instance_valid(_rotation_amount_slider):
		RH.set_rotation_amount(_deform_num(_rotation_amount_slider))
	if is_instance_valid(noise_amount):
		RH.set_field("noise_amount", _deform_num(noise_amount))
	if is_instance_valid(noise_scale):
		RH.set_field("noise_scale", _deform_num(noise_scale))
	if is_instance_valid(camera_rate):
		RH.set_field("camera_rate", _camera_motion_rate())
	if is_instance_valid(camera_depth):
		RH.set_field("camera_depth", _camera_motion_depth())
	if is_instance_valid(style_interval_slider):
		_on_style_interval()
	_push_driven_schedules()
	_push_driven_analyzer()
	if nonlinear_camera_toggle and nonlinear_camera_toggle.button_pressed:
		_on_nonlinear_camera_params()
	var kept_writes: Array = []
	for w_any in _driver_card_writes:
		if not (w_any is Dictionary):
			continue
		var w: Dictionary = w_any
		var sl := _live_slider(w.get("slider"))
		var cb: Variant = w.get("cb")
		if sl == null or not (cb is Callable):
			continue
		kept_writes.append(w)
		if SliderSpinLinkScr.looks_driven_expr(sl):
			var lo := float(w.get("lo", 0.0))
			var hi := float(w.get("hi", 100.0))
			(cb as Callable).call(_driver_from_percent(SliderSpinLinkScr.eval_of(sl), lo, hi))
	_driver_card_writes = kept_writes


func _push_driven_analyzer() -> void:
	if is_instance_valid(intensity_slider):
		AudioAnalyzer.master_intensity = SliderSpinLinkScr.eval_of(intensity_slider)
	if is_instance_valid(sensitivity_slider):
		AudioAnalyzer.band_sensitivity = SliderSpinLinkScr.eval_of(sensitivity_slider) * 0.35
	if is_instance_valid(noise_floor_slider):
		AudioAnalyzer.set_noise_floor(SliderSpinLinkScr.eval_of(noise_floor_slider))


func _push_driven_schedules() -> void:
	## Live-eval individual effect schedules without re-rolling Auto Mode.
	var dead: Array = []
	for eid_any in _schedule_ranges.keys():
		var eid := str(eid_any)
		var rs = _schedule_ranges[eid]
		if rs == null or not is_instance_valid(rs):
			dead.append(eid)
			continue
		ShowDirector.fx_automation.set_gate_active_inactive(
			eid,
			float(rs.eval_active()),
			float(rs.eval_inactive())
		)
	for d in dead:
		_schedule_ranges.erase(d)


func apply_session_fx(data: Dictionary) -> void:
	## Restore driver defs + FX expressions after session load.
	var drv: Variant = data.get("drivers", {})
	if drv is Dictionary and _drv():
		_drv().deserialize(drv as Dictionary)
	var fx: Variant = data.get("fx", {})
	if fx is Dictionary:
		ShowDirector.import_fx_state(fx as Dictionary)
		_restore_fx_sliders_from_director()
	_rebuild_driver_cards()


func _restore_fx_sliders_from_director() -> void:
	var st: Dictionary = ShowDirector.export_fx_state()
	var enabled: Dictionary = st.get("enabled", {}) as Dictionary
	var params: Dictionary = st.get("params", {}) as Dictionary
	_syncing_ui = true
	_set_check_no_signal(ascii_toggle, bool(enabled.get("ascii", false)))
	_set_check_no_signal(feedback_toggle, bool(enabled.get("feedback", false)))
	_set_check_no_signal(glitch_toggle, bool(enabled.get("glitch", false)))
	_set_check_no_signal(chromatic_toggle, bool(enabled.get("chromatic", false)))
	_set_check_no_signal(tone_toggle, bool(enabled.get("tone", false)))
	_set_check_no_signal(hole_toggle, bool(enabled.get("hole", false)))
	_set_check_no_signal(wireframe_toggle, bool(enabled.get("wireframe", false)))
	_set_check_no_signal(point_cloud_toggle, bool(enabled.get("point_cloud", false)))
	_set_check_no_signal(camera_fx_toggle, bool(enabled.get("camera_fx", false)))
	_set_check_no_signal(material_override_toggle, bool(enabled.get("material_override", false)))
	_set_check_no_signal(fog_toggle, bool(enabled.get("fog", false)))
	var g: Dictionary = params.get("glitch", {}) as Dictionary if params.get("glitch", {}) is Dictionary else {}
	var g_sizes: Vector2 = GlitchEffect.resolve_slice_pixels(g)
	if g.has("v_size"):
		SliderSpinLinkScr.set_mapped_param(glitch_vsize_slider, g.get("v_size", 24.0), 1.0)
		SliderSpinLinkScr.set_mapped_param(glitch_hsize_slider, g.get("h_size", 48.0), 1.0)
	else:
		SliderSpinLinkScr.set_mapped_param(glitch_vsize_slider, g_sizes.x, 1.0)
		SliderSpinLinkScr.set_mapped_param(glitch_hsize_slider, g_sizes.y, 1.0)
	SliderSpinLinkScr.set_mapped_param(glitch_amount_slider, g.get("intensity", glitch_amount_slider.value / 28.0), 28.0)
	SliderSpinLinkScr.set_mapped_param(glitch_speed_slider, g.get("rate", glitch_speed_slider.value / 3.0), 3.0)
	SliderSpinLinkScr.set_mapped_param(glitch_rgb_slider, g.get("rgb_split", glitch_rgb_slider.value / 100.0), 100.0)
	SliderSpinLinkScr.set_mapped_param(glitch_chaos_slider, g.get("slice_chaos", glitch_chaos_slider.value / 100.0), 100.0)
	var fb: Dictionary = params.get("feedback", {}) as Dictionary if params.get("feedback", {}) is Dictionary else {}
	var fb_op: Variant = fb.get("opacity", fb.get("mix_amount", feedback_mix_slider.value / 100.0))
	SliderSpinLinkScr.set_mapped_param(feedback_mix_slider, fb_op, 100.0)
	SliderSpinLinkScr.set_mapped_param(feedback_persist_slider, fb.get("persistence", feedback_persist_slider.value / 100.0), 100.0)
	if feedback_blur_slider:
		SliderSpinLinkScr.set_mapped_param(feedback_blur_slider, fb.get("blur", 0.20), 100.0)
	if feedback_blend:
		feedback_blend.select(FeedbackEffect.blend_index_from_param(fb.get("blend", FEEDBACK_DEFAULT_BLEND)))
	var ch: Dictionary = params.get("chromatic", {}) as Dictionary if params.get("chromatic", {}) is Dictionary else {}
	SliderSpinLinkScr.set_mapped_param(chromatic_amount_slider, ch.get("amount", chromatic_amount_slider.value / 28.0), 28.0)
	var tn: Dictionary = params.get("tone", {}) as Dictionary if params.get("tone", {}) is Dictionary else {}
	if tone_invert_slider:
		SliderSpinLinkScr.set_mapped_param(tone_invert_slider, tn.get("invert", 0.0), 100.0)
	if tone_brightness_slider:
		SliderSpinLinkScr.set_mapped_param(tone_brightness_slider, tn.get("brightness", 1.0), 100.0)
	if tone_contrast_slider:
		SliderSpinLinkScr.set_mapped_param(tone_contrast_slider, tn.get("contrast", 1.0), 100.0)
	if tone_saturation_slider:
		SliderSpinLinkScr.set_mapped_param(tone_saturation_slider, tn.get("saturation", 1.0), 100.0)
	var hole: Dictionary = params.get("hole", {}) as Dictionary if params.get("hole", {}) is Dictionary else {}
	if hole_strength_slider:
		SliderSpinLinkScr.set_mapped_param(hole_strength_slider, hole.get("strength", 0.75), 100.0)
	if hole_size_slider:
		SliderSpinLinkScr.set_mapped_param(hole_size_slider, hole.get("hole_size", 0.20), 100.0)
	if hole_twist_slider:
		SliderSpinLinkScr.set_mapped_param(hole_twist_slider, hole.get("twist", 0.0), 25.0)
	if hole_softness_slider:
		SliderSpinLinkScr.set_mapped_param(hole_softness_slider, hole.get("softness", 0.30), 100.0)
	if hole_flow_slider:
		SliderSpinLinkScr.set_mapped_param(hole_flow_slider, hole.get("flow", 0.50), 100.0)
	if hole_cx_slider:
		SliderSpinLinkScr.set_mapped_param(hole_cx_slider, hole.get("center_x", 0.5), 100.0)
	if hole_cy_slider:
		SliderSpinLinkScr.set_mapped_param(hole_cy_slider, hole.get("center_y", 0.5), 100.0)
	if hole_shape and hole.has("shape"):
		var sidx := HOLE_SHAPE_NAMES.find(str(hole["shape"]))
		if sidx >= 0:
			hole_shape.select(sidx)
	var pc: Dictionary = params.get("point_cloud", {}) as Dictionary if params.get("point_cloud", {}) is Dictionary else {}
	SliderSpinLinkScr.set_mapped_param(point_cloud_size_slider, pc.get("point_size", point_cloud_size_slider.value), 1.0)
	var cam: Dictionary = params.get("camera_fx", {}) as Dictionary if params.get("camera_fx", {}) is Dictionary else {}
	SliderSpinLinkScr.set_mapped_param(camera_fx_focal_slider, cam.get("focal_length", camera_fx_focal_slider.value), 1.0)
	SliderSpinLinkScr.set_mapped_param(camera_fx_aperture_slider, cam.get("aperture", camera_fx_aperture_slider.value), 1.0)
	var loaded := SceneMeshFx.camera_focus_range(cam)
	SliderSpinLinkScr.set_mapped_param(camera_fx_focus_slider, loaded.x, 1.0)
	SliderSpinLinkScr.set_mapped_param(camera_fx_focus_far_slider, loaded.y, 1.0)
	SliderSpinLinkScr.set_mapped_param(camera_fx_falloff_slider, cam.get("focus_softness", 0.7), 100.0)
	SliderSpinLinkScr.set_mapped_param(camera_fx_bokeh_slider, cam.get("bokeh", camera_fx_bokeh_slider.value / 100.0), 100.0)
	if _camera_fx_lens_slider:
		SliderSpinLinkScr.set_mapped_param(_camera_fx_lens_slider, cam.get("lens_distortion", 0.0), 100.0)
	var mo: Dictionary = params.get("material_override", {}) as Dictionary if params.get("material_override", {}) is Dictionary else {}
	if material_override_look and mo.has("look"):
		var look_name := MaterialOverrideEffect.normalize_look(mo["look"])
		var midx := MAT_OVERRIDE_LOOK_NAMES.find(look_name)
		if midx >= 0:
			SliderSpinLinkScr.reset_choice_to_index(material_override_look, midx, false)
	var fogp: Dictionary = FogEffect.sanitize_params(params.get("fog", {}) as Dictionary if params.get("fog", {}) is Dictionary else {})
	if fog_density_slider:
		SliderSpinLinkScr.set_mapped_param(fog_density_slider, fogp.get("density", 0.32), 100.0)
	if fog_begin_slider:
		SliderSpinLinkScr.set_expr(fog_begin_slider, str(float(fogp.get("begin", 5.0))), false)
	if fog_end_slider:
		SliderSpinLinkScr.set_expr(fog_end_slider, str(float(fogp.get("end", 32.0))), false)
	if fog_tint_slider:
		SliderSpinLinkScr.set_expr(fog_tint_slider, str(FogEffect.tint_from_params(fogp)), false)
	var asc: Dictionary = params.get("ascii", {}) as Dictionary if params.get("ascii", {}) is Dictionary else {}
	if _ascii_density_slider and asc.has("density"):
		SliderSpinLinkScr.set_mapped_param(_ascii_density_slider, asc.get("density"), 1.0)
	if ascii_preset and asc.has("style_index"):
		var si: Variant = asc.get("style_index")
		if si is String:
			SliderSpinLinkScr.set_choice_expr(ascii_preset, str(si), false)
		else:
			SliderSpinLinkScr.reset_choice_to_index(ascii_preset, int(si), false)
	_syncing_ui = false
	_sync_conditional_ui()
