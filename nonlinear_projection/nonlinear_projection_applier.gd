extends Node
class_name NonlinearProjectionApplier

## Optional inspector proxy. Attach near a Camera3D; forwards to the
## NonlinearProjection autoload. Removable — does not own the gameplay camera.

const NPSettings := preload("res://nonlinear_projection/nonlinear_projection_settings.gd")

@export var enabled: bool = false:
	set(v):
		enabled = v
		_push()

@export_range(0.0, 2.0, 0.01) var distortion_strength: float = 1.0:
	set(v):
		distortion_strength = v
		_push()

@export_range(0.0, 400.0, 0.5) var transition_start: float = 4.0:
	set(v):
		transition_start = v
		_push()

@export_range(1.0, 800.0, 0.5) var transition_end: float = 35.0:
	set(v):
		transition_end = v
		_push()

@export_range(0.0, 120.0, 0.5) var max_bend_angle_deg: float = 90.0:
	set(v):
		max_bend_angle_deg = v
		_push()

@export var easing: int = 1:
	set(v):
		easing = v
		_push()

@export_range(0.0, 3.0, 0.01) var vertical_scale: float = 1.0:
	set(v):
		vertical_scale = v
		_push()

@export_range(0.0, 4.0, 0.01) var horizontal_scale: float = 1.0:
	set(v):
		horizontal_scale = v
		_push()

@export_range(0.0, 4.0, 0.01) var far_horizontal_scale: float = 1.0:
	set(v):
		far_horizontal_scale = v
		_push()

@export var debug_visualize: bool = false:
	set(v):
		debug_visualize = v
		_push()

@export var settings: Resource


func _ready() -> void:
	if settings:
		enabled = bool(settings.get("enabled"))
		distortion_strength = float(settings.get("distortion_strength"))
		transition_start = float(settings.get("transition_start"))
		transition_end = float(settings.get("transition_end"))
		max_bend_angle_deg = float(settings.get("max_bend_angle_deg"))
		easing = int(settings.get("easing"))
		vertical_scale = float(settings.get("vertical_scale"))
		horizontal_scale = float(settings.get("horizontal_scale"))
		far_horizontal_scale = float(settings.get("far_horizontal_scale"))
		debug_visualize = bool(settings.get("debug_visualize"))
	_push()


func _push() -> void:
	var np := _svc()
	if np == null:
		return
	if settings:
		np.call("apply_settings", settings)
		return
	np.set("enabled", enabled)
	np.set("distortion_strength", distortion_strength)
	np.set("transition_start", transition_start)
	np.set("transition_end", transition_end)
	np.set("max_bend_angle_deg", max_bend_angle_deg)
	np.set("easing", easing)
	np.set("vertical_scale", vertical_scale)
	np.set("horizontal_scale", horizontal_scale)
	np.set("far_horizontal_scale", far_horizontal_scale)
	np.set("debug_visualize", debug_visualize)


func _svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("NonlinearProjection")
