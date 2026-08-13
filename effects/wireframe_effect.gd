extends EffectLayer
class_name WireframeEffect

## Viewport wireframe overlay for the active 3D scene.


func _ready() -> void:
	effect_id = "wireframe"
	layer = 1
	visible = false


func set_active(is_on: bool) -> void:
	enabled = is_on
	visible = false
	_set_wireframe(is_on)


func apply_params(params: Dictionary) -> void:
	super.apply_params(params)
	_set_wireframe(enabled)


func apply_audio_state(_state: AudioState) -> void:
	_set_wireframe(enabled)


func apply_modulator(_mod01: float) -> void:
	pass


func _on_params_changed(_params: Dictionary) -> void:
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
