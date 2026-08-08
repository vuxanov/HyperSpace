extends Object

## Typed access to the ReactivitySettings autoload.
## Use in scripts: const ReactivityHub = preload("res://core/reactivity_hub.gd")


static func node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("ReactivitySettings")


static func enabled() -> bool:
	var n := node()
	return bool(n.get("enabled")) if n else true


static func affect_scale() -> bool:
	var n := node()
	return bool(n.get("affect_scale")) if n else true


static func affect_light() -> bool:
	var n := node()
	return bool(n.get("affect_light")) if n else true


static func affect_emission() -> bool:
	var n := node()
	return bool(n.get("affect_emission")) if n else true


static func affect_rotation() -> bool:
	var n := node()
	return bool(n.get("affect_rotation")) if n else true


static func scale_amount() -> float:
	var n := node()
	return float(n.get("scale_amount")) if n else 5.0


static func target() -> String:
	var n := node()
	return str(n.get("target")) if n else "foreground"


static func scale_x() -> bool:
	var n := node()
	return bool(n.get("scale_x")) if n else true


static func scale_y() -> bool:
	var n := node()
	return bool(n.get("scale_y")) if n else true


static func scale_z() -> bool:
	var n := node()
	return bool(n.get("scale_z")) if n else true


static func set_enabled(value: bool) -> void:
	var n := node()
	if n and n.has_method("set_enabled"):
		n.call("set_enabled", value)


static func set_scale_amount(value: float) -> void:
	var n := node()
	if n and n.has_method("set_scale_amount"):
		n.call("set_scale_amount", value)


static func notify_changed() -> void:
	var n := node()
	if n and n.has_method("notify_changed"):
		n.call("notify_changed")


static func set_field(field: String, value: Variant) -> void:
	var n := node()
	if n:
		n.set(field, value)
		notify_changed()


static func get_field(field: String, fallback: Variant = null) -> Variant:
	var n := node()
	if n:
		return n.get(field)
	return fallback


static func applies_to(object_id: String) -> bool:
	if not enabled():
		return false
	var t := target()
	if t == "all":
		return true
	if t == object_id:
		return true
	# centerpiece ↔ foreground alias (fly-through naming)
	if (t == "centerpiece" or t == "foreground" or t == "main") and (
		object_id == "centerpiece" or object_id == "foreground" or object_id == "main"
	):
		return true
	return false


static func scale_vector(base: float) -> Vector3:
	var amount := base - 1.0
	return Vector3(
		1.0 + amount if scale_x() else 1.0,
		1.0 + amount if scale_y() else 1.0,
		1.0 + amount if scale_z() else 1.0
	)
