extends EffectLayer
class_name WireframeEffect

## Viewport wireframe overlay for the active 3D scene.


func _ready() -> void:
	effect_id = "wireframe"
	layer = 1
	visible = false


func set_active(is_on: bool) -> void:
	enabled = is_on
	visible = false  # no 2D overlay — drives SubViewport debug draw
	_push_to_scene()


func apply_params(params: Dictionary) -> void:
	super.apply_params(params)
	_push_to_scene()


func apply_audio_state(state: AudioState) -> void:
	if not enabled:
		_set_wireframe(false)
		return
	match normalize_drive_mode(drive_mode):
		"auto", "manual":
			_set_wireframe(true)
		"lfo":
			_set_wireframe(_last_lfo > 0.45)
		_:
			_set_wireframe(resolve_drive(state.energy) > 0.25)


func apply_modulator(mod01: float) -> void:
	super.apply_modulator(mod01)
	if enabled and normalize_drive_mode(drive_mode) == "lfo":
		_set_wireframe(mod01 > 0.45)


func _on_params_changed(_params: Dictionary) -> void:
	_push_to_scene()


func _push_to_scene() -> void:
	_set_wireframe(enabled)


func _set_wireframe(on: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var director := tree.root.get_node_or_null("ShowDirector")
	if director == null:
		return
	var node: Variant = director.get("current_item_node")
	if node != null and node is Node and (node as Node).has_method("set_wireframe"):
		(node as Node).call("set_wireframe", on)
