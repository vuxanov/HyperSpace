class_name Transition
extends RefCounted

enum Mode { CUT, CROSSFADE, FADE_OUT_IN }

var mode: Mode = Mode.CUT
var duration: float = 1.0
var elapsed: float = 0.0
var active: bool = false
var from_node: Node = null
var to_node: Node = null


func start(from: Node, to: Node, transition_mode: Mode, transition_duration: float) -> void:
	from_node = from
	to_node = to
	mode = transition_mode
	duration = maxf(transition_duration, 0.001)
	elapsed = 0.0
	active = true
	if mode == Mode.CUT:
		_apply_alpha(from_node, 0.0)
		_apply_alpha(to_node, 1.0)
		active = false
	else:
		# Prevent both layers sitting at full opacity on the first frame.
		_apply_alpha(from_node, 1.0)
		_apply_alpha(to_node, 0.0)


func update(delta: float) -> bool:
	if not active:
		return false
	elapsed += delta
	var t := clampf(elapsed / duration, 0.0, 1.0)
	match mode:
		Mode.CROSSFADE:
			_apply_alpha(from_node, 1.0 - t)
			_apply_alpha(to_node, t)
		Mode.FADE_OUT_IN:
			if t < 0.5:
				_apply_alpha(from_node, 1.0 - t * 2.0)
				_apply_alpha(to_node, 0.0)
			else:
				_apply_alpha(from_node, 0.0)
				_apply_alpha(to_node, (t - 0.5) * 2.0)
	if elapsed >= duration:
		_apply_alpha(from_node, 0.0)
		_apply_alpha(to_node, 1.0)
		active = false
		return false
	return true


func _apply_alpha(node: Node, alpha: float) -> void:
	if node == null:
		return
	if node.has_method("set_layer_alpha"):
		node.call("set_layer_alpha", alpha)
	elif "modulate" in node:
		node.modulate.a = alpha
