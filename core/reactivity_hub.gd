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
	## True when any deform/FX-react toggle is on. The old master Audio Reactivity
	## flag still counts, but Scale/Noise/Rotation/Camera no longer need it.
	var n := node()
	if n == null:
		return false
	if bool(n.get("enabled")):
		return true
	if bool(n.get("affect_scale")) or bool(n.get("affect_rotation")) or bool(n.get("affect_noise")):
		return true
	if bool(n.get("affect_light")) or bool(n.get("affect_emission")):
		return true
	if bool(n.get("affect_camera_rotation")):
		return true
	var raw: Variant = n.get("camera_preset")
	var preset := "Off" if raw == null else str(raw)
	return not preset.is_empty() and preset != "Off"


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


static func _normalize_layer(layer_id: String) -> String:
	match layer_id:
		"centerpiece", "foreground", "main":
			return "main"
		"light", "lights":
			return "lights"
		"cam", "camera":
			return "camera"
		"outer", "env", "environment":
			return "environment"
		_:
			return layer_id


## True when the global "What reacts" multi-select includes this layer.
static func targets_include(layer_id: String) -> bool:
	return _bool_targets_include("", layer_id, ["main", "scatter", "environment"])


static func noise_targets_include(layer_id: String) -> bool:
	return _bool_targets_include("noise_", layer_id, ["main", "scatter", "environment"])


static func rotation_targets_include(layer_id: String) -> bool:
	return _bool_targets_include("rotation_", layer_id, ["main", "scatter", "environment", "camera"])


static func particles_targets_include(layer_id: String) -> bool:
	return _bool_targets_include("particles_", layer_id, ["main", "scatter", "environment"])


static func _bool_targets_include(prefix: String, layer_id: String, layers: Array) -> bool:
	var key := _normalize_layer(layer_id)
	## Lights and media are not Affects targets (scale/noise/rotation/particles/cloth).
	if key == "lights" or key == "media":
		return false
	var n := node()
	if n == null:
		return false
	if not layers.has(key):
		return false
	return bool(n.get("%starget_%s" % [prefix, key]))


## Apply a legacy single-string target ("all" | layer id) onto multi-bool fields.
static func apply_legacy_target_string(prefix: String, legacy: String, layers: Array) -> void:
	var n := node()
	if n == null:
		return
	var t := legacy.strip_edges().to_lower()
	var all_on := t.is_empty() or t == "all" or t == "everything"
	for layer in layers:
		var on := all_on
		if not all_on:
			on = _normalize_layer(t) == str(layer) or t == str(layer)
			# Legacy aliases for main.
			if str(layer) == "main" and t in ["centerpiece", "foreground", "main"]:
				on = true
		n.set("%starget_%s" % [prefix, layer], on)
	notify_changed()


static func set_target_bool(prefix: String, layer: String, value: bool) -> void:
	var n := node()
	if n == null:
		return
	n.set("%starget_%s" % [prefix, _normalize_layer(layer)], value)
	notify_changed()


static func get_target_bool(prefix: String, layer: String, fallback: bool = false) -> bool:
	var n := node()
	if n == null:
		return fallback
	return bool(n.get("%starget_%s" % [prefix, _normalize_layer(layer)]))


static func particles_target_snapshot() -> Dictionary:
	return {
		"target_main": get_target_bool("particles_", "main"),
		"target_scatter": get_target_bool("particles_", "scatter"),
		"target_environment": get_target_bool("particles_", "environment"),
	}


static func apply_particles_targets_from_params(params: Dictionary) -> void:
	## Prefer multi-bool keys; fall back to legacy string "target".
	if params.has("target_main") or params.has("target_scatter") or params.has("target_environment") \
			or params.has("target_lights") or params.has("target_media"):
		var n := node()
		if n == null:
			return
		n.set("particles_target_main", bool(params.get("target_main", false)))
		n.set("particles_target_scatter", bool(params.get("target_scatter", false)))
		n.set("particles_target_environment", bool(params.get("target_environment", false)))
		n.set("particles_target_lights", false)
		n.set("particles_target_media", false)
		notify_changed()
	elif params.has("target"):
		apply_legacy_target_string("particles_", str(params["target"]), [
			"main", "scatter", "environment",
		])


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
		n.set("rotation_amount", clampf(value, -1.0e6, 1.0e6))
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
	if n == null:
		return fallback
	var v: Variant = n.get(field)
	if v == null:
		return fallback
	return v


static func applies_to(object_id: String) -> bool:
	return targets_include(object_id)


static func particles_applies_to(layer_id: String) -> bool:
	var director := _director()
	if director == null or not bool(director.call("get_effect_enabled", "particles")):
		return false
	return particles_targets_include(layer_id)


static func noise_applies_to(layer_id: String) -> bool:
	if not affect_noise():
		return false
	return noise_targets_include(layer_id)


static func rotation_applies_to(layer_id: String) -> bool:
	# Camera can be driven from Camera motion nested toggle and/or Rotation target.
	if layer_id == "camera":
		var cam_rot := bool(get_field("affect_camera_rotation", false))
		if cam_rot:
			return true
		if not affect_rotation():
			return false
		return rotation_targets_include("camera")
	if not affect_rotation():
		return false
	return rotation_targets_include(layer_id)


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
	# Analyzer already maps to 0..1. Extra pow made every band look the same.
	if src == "kick":
		return 1.0 if raw > 0.5 else 0.0
	return clampf(raw, 0.0, 1.0)


## Amount is the live field (number or evaluated expression). drive01 is ignored.
static func scale_multiplier(_drive01: float = 1.0, amount: float = -1.0e30) -> float:
	var amt := scale_amount() if amount < -1.0e20 else amount
	return clampf(1.0 + amt, -1.0e6, 1.0e6)


## Radians per frame from the live amount field (expression can be bass * 1000).
static func rotation_rate(_drive01: float = 1.0, amount: float = -1.0e30) -> float:
	var amt := rotation_amount() if amount < -1.0e20 else amount
	return clampf((amt / 20.0) * 0.07, -1.0e6, 1.0e6)


static func property_active(property: String) -> bool:
	if not schedule_open(property):
		return false
	match property:
		"scale":
			return affect_scale()
		"emission":
			return affect_emission()
		"rotation":
			return affect_rotation() or bool(get_field("affect_camera_rotation", false))
		"light":
			return affect_light()
		"noise":
			return affect_noise()
		_:
			return false
