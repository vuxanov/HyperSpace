extends Object

## Typed access to the ReactivitySettings autoload + driver resolution.

static var _cached_node: Node = null
static var _cached_director: Node = null


static func node() -> Node:
	if is_instance_valid(_cached_node):
		return _cached_node
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		_cached_node = null
		return null
	_cached_node = tree.root.get_node_or_null("ReactivitySettings")
	return _cached_node


static func _director() -> Node:
	if is_instance_valid(_cached_director):
		return _cached_director
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		_cached_director = null
		return null
	_cached_director = tree.root.get_node_or_null("ShowDirector")
	return _cached_director


static func enabled() -> bool:
	var n := node()
	return bool(n.get("enabled")) if n else false


static func affect_scale() -> bool:
	var n := node()
	return bool(n.get("affect_scale")) if n else false


static func affect_light() -> bool:
	var n := node()
	return bool(n.get("affect_light")) if n else false


static func affect_emission() -> bool:
	var n := node()
	return bool(n.get("affect_emission")) if n else false


static func affect_rotation() -> bool:
	var n := node()
	return bool(n.get("affect_rotation")) if n else false


static func affect_noise() -> bool:
	var n := node()
	return bool(n.get("affect_noise")) if n else false


static func scale_amount() -> float:
	var n := node()
	return float(n.get("scale_amount")) if n else 25.0


static func rotation_amount() -> float:
	var n := node()
	return float(n.get("rotation_amount")) if n else 1.0


static func noise_amount() -> float:
	var n := node()
	return float(n.get("noise_amount")) if n else 28.0


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


static func rotation_target() -> String:
	var n := node()
	return str(n.get("rotation_target")) if n else "all"


static func scale_x() -> bool:
	var n := node()
	return bool(n.get("scale_x")) if n else true


static func scale_y() -> bool:
	var n := node()
	return bool(n.get("scale_y")) if n else true


static func scale_z() -> bool:
	var n := node()
	return bool(n.get("scale_z")) if n else true


static func rotation_x() -> bool:
	var n := node()
	return bool(n.get("rotation_x")) if n else true


static func rotation_y() -> bool:
	var n := node()
	return bool(n.get("rotation_y")) if n else true


static func rotation_z() -> bool:
	var n := node()
	return bool(n.get("rotation_z")) if n else true


static func rotation_axis_mask() -> Vector3:
	return Vector3(
		1.0 if rotation_x() else 0.0,
		1.0 if rotation_y() else 0.0,
		1.0 if rotation_z() else 0.0
	)


static func noise_x() -> bool:
	var n := node()
	return bool(n.get("noise_x")) if n else true


static func noise_y() -> bool:
	var n := node()
	return bool(n.get("noise_y")) if n else true


static func noise_z() -> bool:
	var n := node()
	return bool(n.get("noise_z")) if n else true


static func noise_axis_mask() -> Vector3:
	return Vector3(
		1.0 if noise_x() else 0.0,
		1.0 if noise_y() else 0.0,
		1.0 if noise_z() else 0.0
	)


static func set_enabled(value: bool) -> void:
	var n := node()
	if n and n.has_method("set_enabled"):
		n.call("set_enabled", value)


static func set_scale_amount(value: float) -> void:
	var n := node()
	if n and n.has_method("set_scale_amount"):
		n.call("set_scale_amount", value)


static func set_rotation_amount(value: float) -> void:
	var n := node()
	if n and n.has_method("set_rotation_amount"):
		n.call("set_rotation_amount", value)
	elif n:
		n.set("rotation_amount", maxf(value, 0.0))
		notify_changed()


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
	var director := _director()
	if director == null or not bool(director.call("get_effect_enabled", "particles")):
		return false
	return _layer_matches_target(particles_target(), layer_id)


static func noise_applies_to(layer_id: String) -> bool:
	if not enabled() or not affect_noise():
		return false
	if source_for("noise") == "off":
		return false
	return _layer_matches_target(noise_target(), layer_id)


static func rotation_applies_to(layer_id: String) -> bool:
	if not enabled():
		return false
	if source_for("rotation") == "off":
		return false
	# Camera can be driven from Camera motion nested toggle and/or Rotation target.
	if layer_id == "camera":
		var cam_rot := bool(get_field("affect_camera_rotation", false))
		if cam_rot:
			return true
		if not affect_rotation():
			return false
		return _layer_matches_target(rotation_target(), "camera")
	if not affect_rotation():
		return false
	return _layer_matches_target(rotation_target(), layer_id)


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
	if (t == "camera" or t == "cam") and (layer_id == "camera" or layer_id == "cam"):
		return true
	return false


static func scale_vector(base: float) -> Vector3:
	var amount := base - 1.0
	return Vector3(
		1.0 + amount if scale_x() else 1.0,
		1.0 + amount if scale_y() else 1.0,
		1.0 + amount if scale_z() else 1.0
	)


## Gate id used by FxAutomation for reactivity Active/Inactive schedules.
static func schedule_gate_id(property: String) -> String:
	return "react_" + property


## True when schedule is off (always active) or currently in the Active window.
## Active/Inactive seconds come from ScheduleSecondsPair → FxAutomation gates
## (open for exactly active_sec, closed for inactive_sec, then repeat).
static func schedule_open(property: String) -> bool:
	var director := _director()
	if director == null:
		return true
	var fx = director.get("fx_automation")
	if fx == null or not fx.has_method("is_gate_open"):
		return true
	var gate_id := schedule_gate_id(property)
	# Disabled gate ⇒ always open. Enabled + phase ≥ active_sec ⇒ muted.
	return bool(fx.call("is_gate_open", gate_id))


static func schedule_enabled(property: String) -> bool:
	var director := _director()
	if director == null:
		return false
	var fx = director.get("fx_automation")
	if fx == null or not fx.has_method("is_gate_enabled"):
		return false
	return bool(fx.call("is_gate_enabled", schedule_gate_id(property)))


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
	var raw := 0.0
	match src:
		"bass":
			raw = state.bass
		"mids":
			raw = state.mids
		"highs":
			raw = state.highs
		"kick":
			raw = state.kick
		"energy":
			raw = state.energy
		_:
			return 0.0
	# Mid Sensitivity should leave headroom — avoid slamming to 1.0 on quiet mics.
	return clampf(pow(clampf(raw, 0.0, 1.0), 0.55) * 1.15, 0.0, 1.0)


## Lift quiet mic levels so Scale Amount feels usable; amount = peak multiplier above 1.
static func scale_multiplier(drive01: float, amount: float = -1.0) -> float:
	var amt := amount if amount >= 0.0 else scale_amount()
	# Map tiny analyzer values into a punchier 0..1 curve.
	var d := clampf(drive01, 0.0, 1.0)
	d = clampf(pow(d, 0.35) * 1.35, 0.0, 1.0)
	return clampf(1.0 + d * amt, 0.15, 60.0)


## Peak rad/step at amount=20, drive=1 ≈ 0.07; amount scales linearly.
static func rotation_rate(drive01: float, amount: float = -1.0) -> float:
	var amt := amount if amount >= 0.0 else rotation_amount()
	var d := clampf(drive01, 0.0, 1.0)
	d = clampf(pow(d, 0.4) * 1.2, 0.0, 1.0)
	return d * (amt / 20.0) * 0.07


static func property_active(property: String) -> bool:
	if not schedule_open(property):
		return false
	match property:
		"scale":
			return affect_scale() and source_for("scale") != "off"
		"emission":
			return affect_emission() and source_for("emission") != "off"
		"rotation":
			if source_for("rotation") == "off":
				return false
			return affect_rotation() or bool(get_field("affect_camera_rotation", false))
		"light":
			return affect_light() and source_for("light") != "off"
		"noise":
			return affect_noise() and source_for("noise") != "off"
		_:
			return false
