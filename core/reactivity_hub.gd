extends Object

## Typed access to the ReactivitySettings autoload + driver resolution.


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
	return bool(n.get("affect_emission")) if n else false


static func affect_rotation() -> bool:
	var n := node()
	return bool(n.get("affect_rotation")) if n else true


static func affect_noise() -> bool:
	var n := node()
	return bool(n.get("affect_noise")) if n else false


static func scale_amount() -> float:
	var n := node()
	return float(n.get("scale_amount")) if n else 25.0


static func noise_amount() -> float:
	var n := node()
	return float(n.get("noise_amount")) if n else 18.0


static func noise_scale() -> float:
	## Spatial feature size (larger = bigger deform features).
	var n := node()
	if n == null:
		return 4.0
	if n.get("noise_scale") != null:
		return float(n.get("noise_scale"))
	# Backward compat if an old session still has noise_speed.
	if n.get("noise_speed") != null:
		return float(n.get("noise_speed"))
	return 4.0


static func target() -> String:
	var n := node()
	return str(n.get("target")) if n else "all"


static func noise_target() -> String:
	var n := node()
	return str(n.get("noise_target")) if n else "all"


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


static func set_lfo_mod01(value: float) -> void:
	var n := node()
	if n and n.has_method("set_lfo_mod01"):
		n.call("set_lfo_mod01", value)
	elif n:
		n.set("lfo_mod01", clampf(value, 0.0, 1.0))


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
	if (t == "centerpiece" or t == "foreground" or t == "main") and (
		object_id == "centerpiece" or object_id == "foreground" or object_id == "main"
	):
		return true
	if (t == "lights" or t == "light") and (object_id == "lights" or object_id == "light"):
		return true
	return false


static func particles_target() -> String:
	var n := node()
	return str(n.get("particles_target")) if n else "all"


static func particles_applies_to(layer_id: String) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	var director := tree.root.get_node_or_null("ShowDirector")
	if director == null or not bool(director.call("get_effect_enabled", "particles")):
		return false
	return _layer_matches_target(particles_target(), layer_id)


static func noise_applies_to(layer_id: String) -> bool:
	if not enabled() or not affect_noise():
		return false
	if source_for("noise") == "off":
		return false
	return _layer_matches_target(noise_target(), layer_id)


static func _layer_matches_target(t: String, layer_id: String) -> bool:
	if t == "all":
		return true
	if t == layer_id:
		return true
	if t == "centerpiece" and (layer_id == "foreground" or layer_id == "centerpiece" or layer_id == "main"):
		return true
	if t == "scatter" and layer_id == "scatter":
		return true
	if t == "environment" and layer_id == "environment":
		return true
	if (t == "lights" or t == "light") and (layer_id == "lights" or layer_id == "light"):
		return true
	return false


static func scale_vector(base: float) -> Vector3:
	var amount := base - 1.0
	return Vector3(
		1.0 + amount if scale_x() else 1.0,
		1.0 + amount if scale_y() else 1.0,
		1.0 + amount if scale_z() else 1.0
	)


static func source_for(property: String) -> String:
	match property:
		"scale":
			return str(get_field("scale_source", "bass"))
		"emission":
			return str(get_field("emission_source", "mids"))
		"rotation":
			return str(get_field("rotation_source", "highs"))
		"light":
			return str(get_field("light_source", "energy"))
		"noise":
			return str(get_field("noise_source", "energy"))
		_:
			return "off"


## Resolve 0..1 drive amount for a property from audio and/or LFO.
static func drive_value(property: String, state: AudioState, lfo_mod01: float = -1.0) -> float:
	var src := source_for(property)
	if src == "off" or src.is_empty():
		return 0.0
	if src == "lfo":
		if lfo_mod01 >= 0.0:
			return clampf(lfo_mod01, 0.0, 1.0)
		return clampf(float(get_field("lfo_mod01", 0.0)), 0.0, 1.0)
	if state == null:
		return 0.0
	match src:
		"bass":
			return clampf(state.bass, 0.0, 1.0)
		"mids":
			return clampf(state.mids, 0.0, 1.0)
		"highs":
			return clampf(state.highs, 0.0, 1.0)
		"kick":
			return clampf(state.kick, 0.0, 1.0)
		"energy":
			return clampf(state.energy, 0.0, 1.0)
		_:
			return 0.0


## Lift quiet mic levels so Scale Amount feels usable; amount = peak multiplier above 1.
static func scale_multiplier(drive01: float, amount: float = -1.0) -> float:
	var amt := amount if amount >= 0.0 else scale_amount()
	# Map tiny analyzer values into a punchier 0..1 curve.
	var d := clampf(drive01, 0.0, 1.0)
	d = clampf(pow(d, 0.35) * 1.35, 0.0, 1.0)
	return clampf(1.0 + d * amt, 0.15, 60.0)


static func property_active(property: String) -> bool:
	match property:
		"scale":
			return affect_scale() and source_for("scale") != "off"
		"emission":
			return affect_emission() and source_for("emission") != "off"
		"rotation":
			return affect_rotation() and source_for("rotation") != "off"
		"light":
			return affect_light() and source_for("light") != "off"
		"noise":
			return affect_noise() and source_for("noise") != "off"
		_:
			return false
