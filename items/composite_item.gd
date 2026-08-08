extends Control
class_name CompositeItem

## Layers multiple playlist items on top of each other.

var item_id: String = ""
var item_loop: bool = false
var _layers: Array[Control] = []
var _alpha: float = 1.0


func configure(item: PlaylistItem) -> void:
	item_id = item.id
	item_loop = item.loop
	for child in get_children():
		child.queue_free()
	_layers.clear()
	for layer_data in item.layers:
		if layer_data is Dictionary:
			var layer_item := PlaylistItem.new(layer_data)
			var node := _create_layer_node(layer_item)
			if node:
				add_child(node)
				node.configure(layer_item)
				_layers.append(node)


func _create_layer_node(item: PlaylistItem) -> Control:
	match item.type:
		"scene3d":
			var node := Scene3DItem.new()
			node.set_anchors_preset(PRESET_FULL_RECT)
			return node
		"video":
			var node := VideoItem.new()
			node.set_anchors_preset(PRESET_FULL_RECT)
			return node
		"image":
			var node := ImageItem.new()
			node.set_anchors_preset(PRESET_FULL_RECT)
			return node
	return null


func set_layer_alpha(alpha: float) -> void:
	_alpha = alpha
	modulate.a = alpha


func apply_audio_state(state: AudioState) -> void:
	for layer in _layers:
		if layer.has_method("apply_audio_state"):
			layer.call("apply_audio_state", state)


func apply_kinect_state(state: KinectState) -> void:
	for layer in _layers:
		if layer.has_method("apply_kinect_state"):
			layer.call("apply_kinect_state", state)


func start_item() -> void:
	visible = true
	modulate.a = _alpha
	for layer in _layers:
		if layer.has_method("start_item"):
			layer.call("start_item")


func stop_item() -> void:
	visible = false
	for layer in _layers:
		if layer.has_method("stop_item"):
			layer.call("stop_item")
