extends Node

## Central show runtime — playlist, cues, transitions, and effect orchestration.

signal show_loaded(name: String)
signal item_changed(item_id: String, index: int)
signal cue_triggered(cue_id: String)
signal playback_error(message: String)
signal playlist_changed()
signal autoplay_changed(playing: bool)
signal element_step_changed(step_index: int, step_count: int)
signal effect_style_advanced(preset_name: String)
signal effect_gate_changed(effect_id: String, open: bool)
signal stage_defaults_restored()

## Post-FX Play All can drive. Fog stays opt-in (washes the scene gray).
const PLAY_ALL_FX_IDS := ["ascii", "feedback", "glitch", "chromatic", "tone", "hole", "wireframe", "point_cloud", "camera_fx", "material_override"]

var show_data: Dictionary = {}
var items: Array[PlaylistItem] = []
var cues: Array = []
var current_index: int = -1
var current_item_node: Control = null

var output_container: Control = null
var effect_stack: Node = null

var autoplay: bool = false
var default_item_duration: float = 8.0
var _item_elapsed: float = 0.0
var _element_step_index: int = 0
var _element_step_elapsed: float = 0.0

var _transition := Transition.new()
var _active_effects: Dictionary = {}  # effect_id -> EffectLayer
var _item_nodes: Dictionary = {}  # item_id -> Control
var _effect_user_enabled: Dictionary = {}  # effect_id -> bool
var _effect_user_params: Dictionary = {}  # effect_id -> Dictionary
var fx_automation := FxAutomation.new()
var _play_all_active: bool = false


func _ready() -> void:
	var preset_names: PackedStringArray = PackedStringArray()
	for k in AsciiEffect.PRESETS.keys():
		preset_names.append(str(k))
	fx_automation.configure_style_presets(preset_names)
	fx_automation.style_advanced.connect(_on_fx_style_advanced)
	fx_automation.gate_changed.connect(_on_fx_gate_changed)
	fx_automation.play_all_randomize_tick.connect(_on_play_all_randomize_tick)


func load_show(show_path: String) -> bool:
	var data := ShowLoader.load_show(show_path)
	var errors := ShowLoader.validate_show(data)
	if not errors.is_empty():
		for err in errors:
			playback_error.emit(err)
			push_warning("ShowDirector: %s" % err)
	show_data = data
	items.clear()
	_clear_item_nodes()
	for item in data.get("items", []):
		if item is PlaylistItem:
			items.append(item)
	cues = data.get("cues", [])
	current_index = -1
	current_item_node = null
	show_loaded.emit(str(data.get("name", "Show")))
	playlist_changed.emit()
	return not items.is_empty()


func add_item(item: PlaylistItem, play_now: bool = false) -> void:
	if item.id.is_empty():
		item.id = _unique_id(item.type)
	elif ShowLoader.find_item(items, item.id) != null:
		item.id = _unique_id(item.id)
	items.append(item)
	playlist_changed.emit()
	if play_now or current_index < 0:
		play_index(items.size() - 1, Transition.Mode.CROSSFADE, 1.0)


func add_item_from_dict(data: Dictionary, play_now: bool = true) -> void:
	add_item(PlaylistItem.new(data), play_now)


func remove_item_at(index: int) -> void:
	if index < 0 or index >= items.size():
		return
	var item: PlaylistItem = items[index]
	if _item_nodes.has(item.id):
		var node: Control = _item_nodes[item.id] as Control
		if node == current_item_node:
			current_item_node = null
		if node != null:
			node.queue_free()
		_item_nodes.erase(item.id)
	items.remove_at(index)
	playlist_changed.emit()
	if items.is_empty():
		current_index = -1
		return
	var next_index := mini(index, items.size() - 1)
	play_index(next_index, Transition.Mode.CUT)


func clear_playlist() -> void:
	_clear_item_nodes()
	items.clear()
	current_index = -1
	current_item_node = null
	playlist_changed.emit()


func items_to_dicts() -> Array:
	## Serialize playlist for session / export.
	var out: Array = []
	for item in items:
		if item is PlaylistItem:
			out.append((item as PlaylistItem).to_dict())
	return out


func move_item(from_index: int, to_index: int) -> void:
	if from_index < 0 or from_index >= items.size():
		return
	if to_index < 0 or to_index >= items.size():
		return
	if from_index == to_index:
		return
	var item: PlaylistItem = items[from_index]
	items.remove_at(from_index)
	items.insert(to_index, item)
	if current_index == from_index:
		current_index = to_index
	elif from_index < current_index and to_index >= current_index:
		current_index -= 1
	elif from_index > current_index and to_index <= current_index:
		current_index += 1
	playlist_changed.emit()


func replace_item_at(index: int, data: Dictionary, play_now: bool = true) -> void:
	if index < 0 or index >= items.size():
		return
	var old: PlaylistItem = items[index]
	var old_id := old.id
	var new_item := PlaylistItem.new(data)
	if new_item.duration <= 0.0:
		new_item.duration = old.duration if old.duration > 0.0 else default_item_duration
	if new_item.id.is_empty():
		new_item.id = _unique_id(new_item.type)
	elif new_item.id != old_id and ShowLoader.find_item(items, new_item.id) != null:
		new_item.id = _unique_id(new_item.id)
	if _item_nodes.has(old_id):
		var node: Control = _item_nodes[old_id] as Control
		if node == current_item_node:
			current_item_node = null
		if node != null:
			node.queue_free()
		_item_nodes.erase(old_id)
	items[index] = new_item
	playlist_changed.emit()
	if play_now or index == current_index:
		play_index(index, Transition.Mode.CUT, 0.0)


func get_effect_enabled(effect_id: String) -> bool:
	## User intent (ignores schedule gates).
	if _effect_user_enabled.has(effect_id):
		return bool(_effect_user_enabled[effect_id])
	if not _active_effects.has(effect_id):
		return false
	var effect: EffectLayer = _active_effects[effect_id] as EffectLayer
	return effect != null and effect.enabled


func is_effect_gate_open(effect_id: String) -> bool:
	return fx_automation.is_gate_open(effect_id)


func is_play_all_active() -> bool:
	return _play_all_active


func set_play_all_effects(on: bool, cycle_sec: float = 20.0, active_sec: float = 5.0, effect_ids: Variant = null) -> void:
	_play_all_active = on
	if on:
		# Play All drives visual FX. Fog stays opt-in so it cannot wash the scene gray.
		# effect_ids: omit/null = default full stack; Array = only those ids (empty = none).
		var ids: Array = []
		if effect_ids is Array:
			for eid in (effect_ids as Array):
				var s := str(eid)
				if not s.is_empty() and not ids.has(s):
					ids.append(s)
		else:
			ids = PLAY_ALL_FX_IDS.duplicate()
		for eid in PLAY_ALL_FX_IDS:
			_effect_user_enabled[eid] = ids.has(eid)
		for eid2 in ids:
			_effect_user_enabled[str(eid2)] = true
		fx_automation.enable_play_all(ids, cycle_sec, active_sec)
		for eid3 in PLAY_ALL_FX_IDS:
			_apply_effect_effective(str(eid3))
		for eid4 in ids:
			if not PLAY_ALL_FX_IDS.has(str(eid4)):
				_apply_effect_effective(str(eid4))
	else:
		fx_automation.disable_play_all()
		for eid in _effect_user_enabled.keys():
			_apply_effect_effective(str(eid))


func update_effect_params(effect_id: String, params: Dictionary) -> void:
	var merged: Dictionary = (_effect_user_params.get(effect_id, {}) as Dictionary).duplicate(true)
	for k in params.keys():
		merged[k] = params[k]
	_effect_user_params[effect_id] = merged
	if bool(_effect_user_enabled.get(effect_id, false)):
		_apply_effect_effective(effect_id)


func refresh_effect(effect_id: String) -> void:
	_apply_effect_effective(effect_id)


func _apply_effect_effective(effect_id: String) -> void:
	if effect_stack == null:
		return
	var user_on := bool(_effect_user_enabled.get(effect_id, false))
	var gate_open := fx_automation.is_gate_open(effect_id)
	var enabled := user_on and gate_open
	var params: Dictionary = (_effect_user_params.get(effect_id, {}) as Dictionary).duplicate(true)
	if enabled:
		if not _active_effects.has(effect_id):
			var layer: EffectLayer = null
			if effect_stack is EffectStack:
				layer = (effect_stack as EffectStack).create_effect(effect_id)
			if layer != null:
				_active_effects[effect_id] = layer
				effect_stack.add_child(layer)
		if _active_effects.has(effect_id):
			var effect: EffectLayer = _active_effects[effect_id] as EffectLayer
			effect.enabled = true
			effect.apply_params(params)
			if effect.has_method("set_active"):
				effect.call("set_active", true)
	else:
		if _active_effects.has(effect_id):
			var effect: EffectLayer = _active_effects[effect_id] as EffectLayer
			if effect == null:
				return
			effect.enabled = false
			if effect.has_method("set_active"):
				effect.call("set_active", false)
			else:
				effect.visible = false


func _on_fx_style_advanced(preset_name: String) -> void:
	effect_style_advanced.emit(preset_name)
	if bool(_effect_user_enabled.get("ascii", false)):
		var params: Dictionary = AsciiEffect.PRESETS.get(preset_name, {}).duplicate()
		var prev: Dictionary = _effect_user_params.get("ascii", {}) as Dictionary
		# Style cycle changes charset/tint only — never density min/max.
		params.erase("density")
		if prev.has("invert"):
			params["invert"] = prev["invert"]
		FxAutomation.copy_driven_params(prev, params)
		if not (params.get("style_index") is String):
			var names: Array = AsciiEffect.PRESETS.keys()
			var si := names.find(preset_name)
			if si >= 0:
				params["style_index"] = float(si)
		if prev.has("density_min"):
			params["density_min"] = prev["density_min"]
		if prev.has("density_max"):
			params["density_max"] = prev["density_max"]
		elif prev.has("density"):
			params["density_min"] = float(prev["density"]) * 0.65
			params["density_max"] = float(prev["density"])
		_effect_user_params["ascii"] = params
		_apply_effect_effective("ascii")


func _on_fx_gate_changed(effect_id: String, open: bool) -> void:
	effect_gate_changed.emit(effect_id, open)
	# Reactivity schedules (react_*) gate audio drives via ReactivityHub — not EffectStack layers.
	if str(effect_id).begins_with("react_"):
		return
	# Master Play All Active/Inactive — mute/unmute every Play-All FX (not a stack layer).
	if str(effect_id) == "play_all":
		for eid in fx_automation.get_play_all_ids():
			_apply_effect_effective(str(eid))
		return
	_apply_effect_effective(effect_id)


func _on_play_all_randomize_tick() -> void:
	## Random: reshuffle params for the current subset. Evolution: only newly added FX.
	if not _play_all_active:
		return
	var mode := fx_automation.play_all_mode
	if mode != "random" and mode != "evolution":
		return
	if not fx_automation.is_play_all_window_open():
		return
	var ids: Array = fx_automation.get_play_all_ids()
	if mode == "evolution":
		var focus: Array = fx_automation.take_evolution_randomize_ids()
		if focus.is_empty():
			return
		ids = focus
	for eid_any in ids:
		var eid := str(eid_any)
		if not fx_automation.is_gate_open(eid):
			# Still clear stale params apply path via refresh (stays off).
			_apply_effect_effective(eid)
			continue
		var prev_keep: Dictionary = (_effect_user_params.get(eid, {}) as Dictionary).duplicate(true)
		var rolled: Dictionary = _make_random_effect_params(eid)
		FxAutomation.copy_driven_params(prev_keep, rolled)
		_effect_user_params[eid] = rolled
		_apply_effect_effective(eid)


func _make_random_effect_params(effect_id: String) -> Dictionary:
	## Runtime random params for Play All Random (does not rewrite sidebar sliders).
	var prev: Dictionary = (_effect_user_params.get(effect_id, {}) as Dictionary).duplicate(true)
	match effect_id:
		"ascii":
			var keys: Array = AsciiEffect.PRESETS.keys()
			var preset_name := str(keys[randi() % keys.size()]) if not keys.is_empty() else "classic"
			var params: Dictionary = AsciiEffect.PRESETS.get(preset_name, {}).duplicate()
			params.erase("density")
			var dmin := float(prev.get("density_min", 40.0))
			var dmax := float(prev.get("density_max", 120.0))
			if dmax < dmin:
				var tmp := dmin
				dmin = dmax
				dmax = tmp
			params["density_min"] = dmin
			params["density_max"] = dmax
			params["density"] = lerpf(dmin, dmax, randf())
			params["invert"] = bool(prev.get("invert", false))
			var si := keys.find(preset_name)
			if si >= 0:
				params["style_index"] = float(si)
			return params
		"feedback":
			var fb_op := randf_range(0.15, 0.85)
			return {
				"intensity": 1.0,
				"mix_amount": fb_op,
				"opacity": fb_op,
				"persistence": randf_range(0.35, 1.0),
				"blur": 0.0 if randf() > 0.65 else randf_range(0.1, 0.8),
			}
		"glitch":
			return {
				"intensity": randf_range(0.4, 3.2),
				"rate": randf_range(2.0, 28.0),
				"v_size": randf_range(2.0, 64.0),
				"h_size": randf_range(4.0, 96.0),
				"rgb_split": randf_range(0.05, 0.9),
				"slice_chaos": randf_range(0.1, 1.0),
			}
		"chromatic":
			return {
				"intensity": 1.0,
				"amount": randf_range(0.2, 3.0),
			}
		"tone":
			return {
				"invert": 1.0 if randf() > 0.6 else randf_range(0.0, 0.35),
				"brightness": randf_range(0.7, 1.5),
				"contrast": randf_range(0.7, 1.8),
				"saturation": randf_range(0.4, 1.8),
			}
		"hole":
			return {
				"shape": "Rectangle" if randf() > 0.5 else "Circular",
				"strength": randf_range(0.45, 1.05),
				"hole_size": randf_range(0.12, 0.32),
				"twist": randf_range(0.0, 0.55),
				"softness": randf_range(0.16, 0.42),
				"flow": randf_range(0.28, 0.90),
				"center_x": randf_range(0.32, 0.68),
				"center_y": randf_range(0.32, 0.68),
			}
		"wireframe":
			return {
				"intensity": 1.0,
			}
		"point_cloud":
			return {
				"point_size": randf_range(3.0, 14.0),
				"target_environment": bool(prev.get("target_environment", true)),
				"target_main": bool(prev.get("target_main", true)),
				"target_scatter": bool(prev.get("target_scatter", true)),
			}
		"camera_fx":
			var near_m := randf_range(0.8, 3.2)
			var far_m := SceneMeshFx.CAM_FOCUS_FAR_MAX if randf() < 0.45 else randf_range(maxf(near_m + 2.0, 6.0), SceneMeshFx.CAM_FOCUS_FAR_MAX)
			return {
				"focal_length": randf_range(8.0, 160.0),
				"aperture": randf_range(1.4, 8.0),
				"focus_near": near_m,
				"focus_far": far_m,
				"focus_distance": near_m,
				"bokeh": randf_range(0.25, 1.0),
				"lens_distortion": randf_range(0.0, 0.8),
			}
		"material_override":
			var looks := MaterialOverrideEffect.LOOK_NAMES
			var look_name := "White cladding"
			if looks.size() > 0:
				look_name = str(looks[randi() % looks.size()])
			return {
				"look": look_name,
				"target_environment": bool(prev.get("target_environment", true)),
				"target_main": bool(prev.get("target_main", true)),
				"target_scatter": bool(prev.get("target_scatter", true)),
			}
		"fog":
			return {
				"density": randf_range(0.22, 0.42),
				"begin": randf_range(3.5, 8.0),
				"end": randf_range(22.0, 45.0),
				"tint": FogEffect.tint_from_params(prev),
			}
		_:
			return prev


func _unique_id(prefix: String) -> String:
	var base := prefix if not prefix.is_empty() else "item"
	var candidate := base
	var n := 1
	while ShowLoader.find_item(items, candidate) != null:
		n += 1
		candidate = "%s_%d" % [base, n]
	return candidate


func _clear_item_nodes() -> void:
	for item_id in _item_nodes:
		var node: Control = _item_nodes[item_id] as Control
		if node != null:
			node.queue_free()
	_item_nodes.clear()


func bind_output(container: Control, effects: Node) -> void:
	output_container = container
	effect_stack = effects


func play_item(item_id: String, transition_mode: Transition.Mode = Transition.Mode.CUT, duration: float = 1.0) -> void:
	var item := ShowLoader.find_item(items, item_id)
	if item == null:
		playback_error.emit("Unknown item: %s" % item_id)
		return
	var index := items.find(item)
	_play_item_at_index(index, transition_mode, duration)


func play_index(index: int, transition_mode: Transition.Mode = Transition.Mode.CUT, duration: float = 0.0) -> void:
	if index < 0 or index >= items.size():
		return
	_play_item_at_index(index, transition_mode, duration)


func next_item(transition_mode: Transition.Mode = Transition.Mode.CUT, duration: float = 0.0) -> void:
	if items.is_empty():
		return
	var next := (current_index + 1) % items.size()
	_play_item_at_index(next, transition_mode, duration)


func prev_item(transition_mode: Transition.Mode = Transition.Mode.CUT, duration: float = 0.0) -> void:
	if items.is_empty():
		return
	var prev := current_index - 1
	if prev < 0:
		prev = items.size() - 1
	_play_item_at_index(prev, transition_mode, duration)


func trigger_cue(cue_id: String) -> void:
	for cue in cues:
		if cue is Dictionary and str(cue.get("id", "")) == cue_id:
			cue_triggered.emit(cue_id)
			for action_data in cue.get("actions", []):
				if action_data is Dictionary:
					_execute_action(CueAction.from_dict(action_data))
			return
	playback_error.emit("Unknown cue: %s" % cue_id)


func set_effect(effect_id: String, enabled: bool, params: Dictionary = {}) -> void:
	_effect_user_enabled[effect_id] = enabled
	if not params.is_empty():
		var merged: Dictionary = (_effect_user_params.get(effect_id, {}) as Dictionary).duplicate(true)
		for k in params.keys():
			merged[k] = params[k]
		_effect_user_params[effect_id] = merged
	elif not _effect_user_params.has(effect_id):
		_effect_user_params[effect_id] = {}
	_apply_effect_effective(effect_id)


func export_fx_state() -> Dictionary:
	return {
		"enabled": _effect_user_enabled.duplicate(true),
		"params": _effect_user_params.duplicate(true),
	}


func import_fx_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	var en: Variant = data.get("enabled", {})
	var pr: Variant = data.get("params", {})
	if en is Dictionary:
		_effect_user_enabled = (en as Dictionary).duplicate(true)
	if pr is Dictionary:
		_effect_user_params = (pr as Dictionary).duplicate(true)
	var seen: Dictionary = {}
	for eid in _effect_user_enabled.keys():
		seen[str(eid)] = true
	for eid2 in _active_effects.keys():
		seen[str(eid2)] = true
	for eid3 in PLAY_ALL_FX_IDS:
		seen[str(eid3)] = true
	seen["fog"] = true
	for eid4 in seen.keys():
		_apply_effect_effective(str(eid4))


func _execute_action(action: CueAction) -> void:
	match action.op:
		"play":
			play_item(action.item_id, Transition.Mode.CUT)
		"crossfade":
			play_item(action.item_id, Transition.Mode.CROSSFADE, action.duration)
		"set_effect":
			set_effect(action.effect, action.enabled, action.params)
		"set_param":
			if action.params.has("target") and action.params.has("key"):
				_set_item_param(str(action.params["target"]), str(action.params["key"]), action.params.get("value"))
		_:
			push_warning("ShowDirector: unknown action op '%s'" % action.op)


func _set_item_param(item_id: String, key: String, value: Variant) -> void:
	if _item_nodes.has(item_id):
		var node: Control = _item_nodes[item_id] as Control
		if node != null and node.has_method("set_cue_param"):
			node.call("set_cue_param", key, value)


func set_active_cue_param(key: String, value: Variant) -> void:
	## Persist on the current playlist item and push to the live node.
	if current_index < 0 or current_index >= items.size():
		return
	var item: PlaylistItem = items[current_index]
	item.params[key] = value
	_set_item_param(item.id, key, value)


func set_item_duration(index: int, seconds: float) -> void:
	if index < 0 or index >= items.size():
		return
	items[index].duration = maxf(seconds, 0.5)


func set_flythrough_layer(layer_id: String, config: Dictionary, index: int = -1) -> void:
	var idx := index if index >= 0 else current_index
	if idx < 0 or idx >= items.size():
		return
	if layer_id not in ["environment", "scatter", "centerpiece", "lighting"]:
		return
	var item: PlaylistItem = items[idx]
	if item.type != "scene3d":
		return
	item.params["style"] = "flythrough"
	item.params[layer_id] = config.duplicate(true)
	var node: Control = _item_nodes.get(item.id) as Control
	if node != null and node.has_method("set_flythrough_layer"):
		node.call("set_flythrough_layer", layer_id, config)
	else:
		# Node missing or old env type — rebuild so FlythroughEnvironment is used.
		if node != null:
			if node == current_item_node:
				current_item_node = null
			node.queue_free()
			_item_nodes.erase(item.id)
		if idx == current_index:
			play_index(idx, Transition.Mode.CUT, 0.0)
	playlist_changed.emit()


func restore_reactive_poses() -> void:
	## Snap env/hero/scatter/camera back after rotation / reactivity toggles off.
	if current_item_node != null and current_item_node.has_method("restore_reactive_poses"):
		current_item_node.call("restore_reactive_poses")


func reset_stage_to_defaults() -> void:
	## Full reset: poses + every playlist customization + all visual FX off (keeps playlist assets).
	const FX_IDS := ["ascii", "feedback", "glitch", "chromatic", "tone", "hole", "wireframe", "point_cloud", "camera_fx", "material_override", "fog"]
	# Clear user-enabled FX first so gate/play-all teardown cannot re-open layers.
	set_play_all_effects(false)
	for eid in FX_IDS:
		set_effect(str(eid), false)
	fx_automation.clear_all_automation()
	_effect_user_params.clear()
	var rs := get_node_or_null("/root/ReactivitySettings")
	if rs:
		if rs.has_method("reset_to_defaults"):
			rs.call("reset_to_defaults")
		else:
			if rs.has_method("set_enabled"):
				rs.call("set_enabled", false)
			else:
				rs.set("enabled", false)
			rs.set("affect_rotation", false)
			rs.set("affect_noise", false)
			rs.set("affect_scale", false)
			rs.set("affect_emission", false)
			rs.set("affect_light", false)
			rs.set("camera_preset", "Off")
			if rs.has_method("notify_changed"):
				rs.call("notify_changed")
	for item in items:
		if item is PlaylistItem:
			(item as PlaylistItem).params = FlythroughAssetCatalog.strip_playlist_item_params((item as PlaylistItem).params)
	if current_item_node != null and current_item_node.has_method("reset_stage_to_defaults"):
		current_item_node.call("reset_stage_to_defaults")
	elif current_item_node != null and current_item_node.has_method("restore_reactive_poses"):
		current_item_node.call("restore_reactive_poses")
	if current_index >= 0 and current_index < items.size():
		var live: PlaylistItem = items[current_index]
		if current_item_node != null and current_item_node.has_method("get_pending_flythrough_params"):
			var pending: Variant = current_item_node.call("get_pending_flythrough_params")
			if pending is Dictionary:
				live.params = FlythroughAssetCatalog.strip_playlist_item_params(pending as Dictionary)
		else:
			live.params = FlythroughAssetCatalog.strip_playlist_item_params(live.params)
	set_active_cue_param("fly_speed", 2.0)
	set_active_cue_param("path_style", "auto")
	stage_defaults_restored.emit()


func get_element_sequence(index: int = -1) -> Array:
	var idx := index if index >= 0 else current_index
	if idx < 0 or idx >= items.size():
		return []
	var item: PlaylistItem = items[idx]
	var seq: Variant = item.params.get("element_sequence", [])
	return seq if seq is Array else []


func set_element_sequence(sequence: Array, index: int = -1, apply_now: bool = true) -> void:
	var idx := index if index >= 0 else current_index
	if idx < 0 or idx >= items.size():
		return
	var item: PlaylistItem = items[idx]
	if item.type != "scene3d":
		return
	item.params["style"] = "flythrough"
	var copied: Array = []
	for step in sequence:
		if step is Dictionary:
			copied.append((step as Dictionary).duplicate(true))
	item.params["element_sequence"] = copied
	var total := FlythroughAssetCatalog.sequence_total_duration(copied)
	if total > 0.0:
		item.duration = total
	elif copied.is_empty() and item.duration < 0.0:
		item.duration = default_item_duration
	if apply_now and idx == current_index:
		if copied.is_empty():
			_element_step_index = 0
			_element_step_elapsed = 0.0
			element_step_changed.emit(-1, 0)
		else:
			var keep := clampi(_element_step_index, 0, copied.size() - 1)
			_element_step_elapsed = 0.0
			_apply_element_step(keep)
	playlist_changed.emit()
	if not apply_now:
		element_step_changed.emit(_element_step_index, copied.size())


func get_element_step_index() -> int:
	return _element_step_index


func apply_element_step(step_index: int, index: int = -1) -> void:
	var idx := index if index >= 0 else current_index
	if idx < 0 or idx >= items.size():
		return
	if idx == current_index:
		_element_step_index = step_index
		_element_step_elapsed = 0.0
	_apply_element_step(step_index, idx)


func _apply_element_step(step_index: int, index: int = -1) -> void:
	var idx := index if index >= 0 else current_index
	var sequence := get_element_sequence(idx)
	if sequence.is_empty():
		element_step_changed.emit(-1, 0)
		return
	var clamped := clampi(step_index, 0, sequence.size() - 1)
	var step: Dictionary = sequence[clamped] as Dictionary
	if step.has("centerpiece") and step["centerpiece"] is Dictionary:
		set_flythrough_layer("centerpiece", step["centerpiece"] as Dictionary, idx)
	if step.has("scatter") and step["scatter"] is Dictionary:
		set_flythrough_layer("scatter", step["scatter"] as Dictionary, idx)
	if idx == current_index:
		_element_step_index = clamped
		element_step_changed.emit(clamped, sequence.size())


func _current_element_step_duration() -> float:
	var sequence := get_element_sequence(current_index)
	if sequence.is_empty() or _element_step_index < 0 or _element_step_index >= sequence.size():
		return get_current_item_duration()
	var step: Dictionary = sequence[_element_step_index] as Dictionary
	return maxf(float(step.get("duration", default_item_duration)), 0.5)


func set_autoplay(playing: bool) -> void:
	autoplay = playing
	_item_elapsed = 0.0
	_element_step_elapsed = 0.0
	autoplay_changed.emit(autoplay)


func toggle_autoplay() -> void:
	set_autoplay(not autoplay)


func get_current_item_duration() -> float:
	if current_index < 0 or current_index >= items.size():
		return default_item_duration
	var item: PlaylistItem = items[current_index]
	var sequence := get_element_sequence(current_index)
	if not sequence.is_empty():
		var total := FlythroughAssetCatalog.sequence_total_duration(sequence)
		if total > 0.0:
			return total
	if item.duration > 0.0:
		return item.duration
	return default_item_duration


func _play_item_at_index(index: int, transition_mode: Transition.Mode, duration: float) -> void:
	if output_container == null:
		playback_error.emit("Output container not bound")
		return
	var item: PlaylistItem = items[index]
	var new_node: Control = _get_or_create_item_node(item)
	if new_node == null:
		return
	# Always replace: hide/stop every other playlist layer first.
	_hide_all_items_except(item.id)
	var old_node: Control = current_item_node
	if new_node.get_parent() != output_container:
		output_container.add_child(new_node)
	if new_node.has_method("set_layer_alpha"):
		new_node.call("set_layer_alpha", 1.0)
	if new_node.has_method("start_item"):
		new_node.call("start_item")
	new_node.visible = true
	if old_node != null and old_node != new_node:
		if transition_mode == Transition.Mode.CUT or duration <= 0.05:
			if old_node.has_method("stop_item"):
				old_node.call("stop_item")
			old_node.visible = false
			_transition.active = false
		else:
			_transition.start(old_node, new_node, transition_mode, duration)
	current_item_node = new_node
	current_index = index
	_item_elapsed = 0.0
	_element_step_index = 0
	_element_step_elapsed = 0.0
	# Apply first element-sequence step so main/scatter match the timeline start.
	if not get_element_sequence(index).is_empty():
		_apply_element_step(0, index)
	else:
		element_step_changed.emit(-1, 0)
	item_changed.emit(item.id, index)
	# Re-bind Camera FX / panoramic wrap onto the new item's gameplay Camera3D.
	if bool(_effect_user_enabled.get("camera_fx", false)):
		_apply_effect_effective("camera_fx")
	if bool(_effect_user_enabled.get("material_override", false)):
		_apply_effect_effective("material_override")
	if bool(_effect_user_enabled.get("fog", false)):
		_apply_effect_effective("fog")


func _hide_all_items_except(keep_id: String) -> void:
	for item_id in _item_nodes:
		if item_id == keep_id:
			continue
		var node: Control = _item_nodes[item_id] as Control
		if node == null:
			continue
		if node.has_method("stop_item"):
			node.call("stop_item")
		node.visible = false
		if node.has_method("set_layer_alpha"):
			node.call("set_layer_alpha", 0.0)


func _get_or_create_item_node(item: PlaylistItem) -> Control:
	if _item_nodes.has(item.id):
		return _item_nodes[item.id] as Control
	var node: Control = null
	match item.type:
		"scene3d":
			node = Scene3DItem.new()
		"video", "gif":
			node = VideoItem.new()
		"image":
			node = ImageItem.new()
		"composite":
			node = CompositeItem.new()
		_:
			playback_error.emit("Unsupported item type: %s" % item.type)
			return null
	node.name = "Item_%s" % item.id
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	if node.has_method("configure"):
		node.call("configure", item)
	node.visible = false
	_item_nodes[item.id] = node
	return node


func _process(delta: float) -> void:
	if _transition.active:
		var still_active: bool = _transition.update(delta)
		if not still_active and _transition.from_node != null:
			if _transition.from_node.has_method("stop_item"):
				_transition.from_node.call("stop_item")
			if _transition.from_node is CanvasItem:
				(_transition.from_node as CanvasItem).visible = false
	if autoplay and current_index >= 0 and not items.is_empty():
		var sequence := get_element_sequence(current_index)
		if not sequence.is_empty():
			_element_step_elapsed += delta
			_item_elapsed += delta
			if _element_step_elapsed >= _current_element_step_duration():
				_element_step_elapsed = 0.0
				if _element_step_index + 1 < sequence.size():
					_apply_element_step(_element_step_index + 1)
				else:
					# End of sequence: soft-loop on a lone stage item; otherwise advance playlist.
					_item_elapsed = 0.0
					_element_step_index = 0
					if items.size() <= 1:
						_apply_element_step(0)
					else:
						next_item(Transition.Mode.CUT, 0.0)
		else:
			_item_elapsed += delta
			if _item_elapsed >= get_current_item_duration():
				_item_elapsed = 0.0
				if items.size() <= 1:
					# Soft loop — avoid rebuild/restart of the only stage item.
					pass
				else:
					next_item(Transition.Mode.CUT, 0.0)
	fx_automation.tick(delta)
	var audio_state: AudioState = AudioAnalyzer.get_state()
	var kinect_state: KinectState = KinectManager.get_state()
	if current_item_node:
		if current_item_node.has_method("apply_audio_state"):
			current_item_node.call("apply_audio_state", audio_state)
		if current_item_node.has_method("apply_kinect_state"):
			current_item_node.call("apply_kinect_state", kinect_state)
	for effect_id in _active_effects:
		var effect: EffectLayer = _active_effects[effect_id] as EffectLayer
		if effect != null and effect.enabled:
			effect.apply_audio_state(audio_state)
	_check_kinect_gestures(kinect_state)



func _check_kinect_gestures(state: KinectState) -> void:
	if state.primary_body and state.primary_body.both_hands_raised():
		# Gesture hook — can be mapped to cues in future
		pass
