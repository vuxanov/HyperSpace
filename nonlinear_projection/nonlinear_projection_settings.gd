extends Resource
class_name NonlinearProjectionSettings

## Tunable nonlinear camera-space projection. Distance source is camera depth;
## swap later for distance_along_road without coupling this resource to roads.

enum Easing {
	LINEAR,
	SMOOTHSTEP,
	EASE_IN,
	EASE_OUT,
	SMOOTHERSTEP,
}

@export var enabled: bool = false
@export_range(0.0, 2.0, 0.01) var distortion_strength: float = 1.0
@export_range(0.0, 400.0, 0.5) var transition_start: float = 4.0
@export_range(1.0, 800.0, 0.5) var transition_end: float = 35.0
@export_range(0.0, 120.0, 0.5) var max_bend_angle_deg: float = 90.0
@export var easing: Easing = Easing.SMOOTHSTEP
@export_range(0.0, 3.0, 0.01) var vertical_scale: float = 1.0
@export_range(0.0, 4.0, 0.01) var horizontal_scale: float = 1.0
@export_range(0.0, 4.0, 0.01) var far_horizontal_scale: float = 1.0
@export var debug_visualize: bool = false
@export_range(0.001, 1.0, 0.001) var near_z_epsilon: float = 0.08
@export_range(0.0, 400.0, 1.0) var extra_cull_margin: float = 80.0
@export var gameplay_camera_only: bool = false
