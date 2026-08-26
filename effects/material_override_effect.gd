extends EffectLayer
class_name MaterialOverrideEffect

## Replace visible scene materials with cladding / metal / viz looks.
## Originals stay on the mesh; GeometryInstance3D.material_override is swapped.
## Toggle off restores originals — Original is not a look.

const LOOK_NAMES := [
	"White cladding",
	"Chrome",
	"Gold",
	"Normal",
	"Shiny black",
]

var _look: String = "White cladding"
var _targets: Dictionary = {
	"target_environment": true,
	"target_main": true,
	"target_scatter": true,
	"target_media": false,
}


func _ready() -> void:
	effect_id = "material_override"
	layer = 1
	visible = false
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var director: Node = tree.root.get_node_or_null("ShowDirector")
		if director != null and director.has_signal("item_changed"):
			if not director.is_connected("item_changed", Callable(self, "_on_item_changed")):
				director.connect("item_changed", Callable(self, "_on_item_changed"))


func _on_item_changed(_item_id: String = "", _index: int = -1) -> void:
	if not enabled:
		return
	_push_to_scene(true)


func set_active(is_on: bool) -> void:
	enabled = is_on
	visible = false
	if is_on:
		_push_to_scene(true)
	else:
		_push_to_scene(false)


func apply_params(params: Dictionary) -> void:
	super.apply_params(params)
	_read_params(params)
	if enabled:
		_push_to_scene(true)


func apply_audio_state(_state: AudioState) -> void:
	# Do not restamp every audio tick — restore+assign strobes white lights
	# (unwraps Bend wrap, flashes originals, emission pops). Look / enable
	# changes go through apply_params / set_active / item_changed.
	pass


func apply_modulator(_mod01: float) -> void:
	pass


func _on_params_changed(params: Dictionary) -> void:
	_read_params(params)


func _read_params(params: Dictionary) -> void:
	if has_raw_param("look"):
		_look = normalize_look(raw_param("look", _look))
	if params.has("target_environment") or params.has("target_main") \
			or params.has("target_scatter") or params.has("target_media"):
		_targets = SceneMeshFx.pc_targets_from(params)


static func normalize_look(raw: Variant) -> String:
	## Map session / driver / legacy values onto the current 5 looks.
	if raw is float or raw is int:
		var idx := int(round(float(raw)))
		# Old 7-look list: 5 = AO, 6 = Original.
		if idx == 5 or idx == 6:
			return "White cladding"
		if LOOK_NAMES.is_empty():
			return "White cladding"
		idx = idx % LOOK_NAMES.size()
		if idx < 0:
			idx += LOOK_NAMES.size()
		return str(LOOK_NAMES[idx])
	var n := str(raw).strip_edges()
	match n:
		"AO", "Ambient occlusion", "Occlusion", "Original", "Off":
			return "White cladding"
		_:
			if LOOK_NAMES.has(n):
				return n
			return "White cladding"


func _push_to_scene(on: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var director: Node = tree.root.get_node_or_null("ShowDirector")
	if director == null:
		return
	var node: Variant = director.get("current_item_node")
	if node != null and node is Node and (node as Node).has_method("set_material_override"):
		var payload: Dictionary = _targets.duplicate()
		payload["look"] = _look
		(node as Node).call("set_material_override", on, payload)
