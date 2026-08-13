extends EffectLayer
class_name PointCloudEffect

## Fake point cloud — mesh vertices drawn as colored dots (not a lidar scan).

var _point_size: float = 6.0
var _targets: Dictionary = {
	"target_environment": true,
	"target_main": true,
	"target_scatter": true,
	"target_media": false,
}


func _ready() -> void:
	effect_id = "point_cloud"
	layer = 1
	visible = false


func set_active(is_on: bool) -> void:
	enabled = is_on
	visible = false
	if is_on:
		_push_to_scene(true, _point_size)
	else:
		_push_to_scene(false, _point_size)


func apply_params(params: Dictionary) -> void:
	super.apply_params(params)
	_point_size = eval_num("point_size", _point_size, 1.0, 64.0)
	_targets = SceneMeshFx.pc_targets_from(params)
	if enabled:
		_push_to_scene(true, _point_size)


func apply_audio_state(_state: AudioState) -> void:
	if not enabled:
		_push_to_scene(false, _point_size)
		return
	_point_size = eval_num("point_size", _point_size, 1.0, 64.0)
	_push_to_scene(true, _point_size)


func apply_modulator(_mod01: float) -> void:
	pass


func _on_params_changed(params: Dictionary) -> void:
	if params.has("point_size"):
		_point_size = eval_num("point_size", _point_size, 1.0, 64.0)
	if params.has("target_environment") or params.has("target_main") \
			or params.has("target_scatter") or params.has("target_media"):
		_targets = SceneMeshFx.pc_targets_from(params)


func _push_to_scene(on: bool, point_size: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var director: Node = tree.root.get_node_or_null("ShowDirector")
	if director == null:
		return
	var node: Variant = director.get("current_item_node")
	if node != null and node is Node and (node as Node).has_method("set_point_cloud"):
		var payload: Dictionary = _targets.duplicate()
		payload["point_size"] = point_size
		(node as Node).call("set_point_cloud", on, payload)
