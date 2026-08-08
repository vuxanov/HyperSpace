extends ReactiveEnvironment
class_name FlythroughEnvironment

## Shared fly-through: path + camera + three uploadable layers (environment, scatter, centerpiece).

const RH = preload("res://core/reactivity_hub.gd")

var fly_speed: float = 2.0

var _camera: Camera3D
var _light: OmniLight3D
var _env_root: Node3D
var _scatter_root: Node3D
var _center_root: Node3D
var _rig: FlythroughCameraRig
var _curve: Curve3D
var _layer_configs: Dictionary = {
	"environment": {"source": "primitive:box_corridor"},
	"scatter": {"source": "primitive:cubes", "count": 36},
	"centerpiece": {"source": "primitive:torus"},
}
var _centerpiece_mesh: MeshInstance3D
var _scatter_meshes: Array[MeshInstance3D] = []
var _center_base_scale := Vector3.ONE
var _scatter_base_scales: Array[Vector3] = []
var _follow_centerpiece: bool = true


func _ready() -> void:
	_build_world()
	_rig = FlythroughCameraRig.new()
	_rig.fly_speed = fly_speed
	_rebuild_all()


func configure_from_params(params: Dictionary) -> void:
	if params.has("speed"):
		fly_speed = float(params["speed"])
	elif params.has("fly_speed"):
		fly_speed = float(params["fly_speed"])
	if params.has("environment") and params["environment"] is Dictionary:
		_layer_configs["environment"] = (params["environment"] as Dictionary).duplicate(true)
	if params.has("scatter") and params["scatter"] is Dictionary:
		_layer_configs["scatter"] = (params["scatter"] as Dictionary).duplicate(true)
	if params.has("centerpiece") and params["centerpiece"] is Dictionary:
		_layer_configs["centerpiece"] = (params["centerpiece"] as Dictionary).duplicate(true)
	if params.has("follow_centerpiece"):
		_follow_centerpiece = bool(params["follow_centerpiece"])
	if is_inside_tree():
		if _rig:
			_rig.fly_speed = fly_speed
		_rebuild_all()


func set_layer_source(layer_id: String, config: Dictionary) -> void:
	if layer_id not in ["environment", "scatter", "centerpiece"]:
		push_warning("FlythroughEnvironment: unknown layer %s" % layer_id)
		return
	_layer_configs[layer_id] = config.duplicate(true)
	if not is_inside_tree():
		return
	match layer_id:
		"environment":
			_rebuild_environment()
			_rebuild_path_from_environment()
			_rebuild_scatter()
			_place_centerpiece()
		"scatter":
			_rebuild_scatter()
		"centerpiece":
			_rebuild_centerpiece()
			_place_centerpiece()


func get_layer_config(layer_id: String) -> Dictionary:
	return (_layer_configs.get(layer_id, {}) as Dictionary).duplicate(true)


func handle_look_input(event: InputEvent) -> void:
	if _rig:
		_rig.handle_look_input(event)


func _build_world() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.42)
	env.ambient_light_energy = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.09, 0.11)
	env.fog_density = 0.015
	env.glow_enabled = false
	world_env.environment = env
	add_child(world_env)

	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.near = 0.05
	_camera.far = 200.0
	add_child(_camera)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.95, 0.95, 1.0)
	_light.light_energy = 1.0
	_light.omni_range = 24.0
	add_child(_light)

	_env_root = Node3D.new()
	_env_root.name = "Environment"
	add_child(_env_root)
	_scatter_root = Node3D.new()
	_scatter_root.name = "Scatter"
	add_child(_scatter_root)
	_center_root = Node3D.new()
	_center_root.name = "Centerpiece"
	add_child(_center_root)


func _rebuild_all() -> void:
	_rebuild_environment()
	_rebuild_path_from_environment()
	_rebuild_scatter()
	_rebuild_centerpiece()
	_place_centerpiece()
	if _rig and _camera and _curve:
		_rig.fly_speed = fly_speed
		_rig.setup(_camera, _curve)


func _rebuild_environment() -> void:
	for child in _env_root.get_children():
		_env_root.remove_child(child)
		child.free()
	var config: Dictionary = _layer_configs.get("environment", {})
	var source := FlythroughLayerSlot.resolve_source_string(config)
	if source.is_empty():
		source = "primitive:box_corridor"
	if FlythroughLayerSlot.is_file_path(source):
		FlythroughLayerSlot.load_asset_into(_env_root, source)
	elif FlythroughLayerSlot.is_primitive_source(source):
		var kind := FlythroughLayerSlot.normalize_primitive(source)
		FlythroughPrimitives.spawn_environment(kind, _env_root)
	else:
		FlythroughPrimitives.spawn_environment("box_corridor", _env_root)


func _rebuild_path_from_environment() -> void:
	var config: Dictionary = _layer_configs.get("environment", {})
	var source := FlythroughLayerSlot.resolve_source_string(config)
	var kind := FlythroughLayerSlot.normalize_primitive(source) if FlythroughLayerSlot.is_primitive_source(source) else ""
	if kind == "flat_plane":
		_curve = FlythroughPathBuilder.overland(80.0, 8.0)
	elif FlythroughLayerSlot.is_file_path(source):
		var aabb := FlythroughLayerSlot.compute_aabb(_env_root)
		_curve = FlythroughPathBuilder.from_aabb(aabb)
	else:
		_curve = FlythroughPathBuilder.straight(60.0, 0.0)
	if _rig and _camera:
		_rig.set_curve(_curve, true)


func _rebuild_centerpiece() -> void:
	for child in _center_root.get_children():
		_center_root.remove_child(child)
		child.free()
	_centerpiece_mesh = null
	var config: Dictionary = _layer_configs.get("centerpiece", {})
	var source := FlythroughLayerSlot.resolve_source_string(config)
	if source.is_empty():
		source = "primitive:torus"
	if FlythroughLayerSlot.is_file_path(source):
		var node := FlythroughLayerSlot.load_asset_into(_center_root, source)
		if node:
			_center_base_scale = node.scale
	elif FlythroughLayerSlot.is_primitive_source(source):
		var kind := FlythroughLayerSlot.normalize_primitive(source)
		_centerpiece_mesh = FlythroughPrimitives.spawn_centerpiece(kind, _center_root)
		_center_base_scale = Vector3.ONE
	else:
		_centerpiece_mesh = FlythroughPrimitives.spawn_centerpiece("torus", _center_root)
		_center_base_scale = Vector3.ONE


func _place_centerpiece() -> void:
	if _center_root.get_child_count() == 0 or _curve == null:
		return
	# Sit centerpiece ahead on the path so it's readable while flying.
	var ahead := mini(12.0, _curve.get_baked_length() * 0.25)
	var xf := _curve.sample_baked_with_rotation(ahead, false)
	_center_root.global_position = xf.origin
	if not _follow_centerpiece:
		return


func _rebuild_scatter() -> void:
	for child in _scatter_root.get_children():
		_scatter_root.remove_child(child)
		child.free()
	_scatter_meshes.clear()
	_scatter_base_scales.clear()
	if _curve == null:
		return
	var config: Dictionary = _layer_configs.get("scatter", {})
	var source := FlythroughLayerSlot.resolve_source_string(config)
	if source.is_empty():
		source = "primitive:cubes"
	var count := int(config.get("count", 36))
	count = clampi(count, 0, 200)
	var length := _curve.get_baked_length()
	if length <= 0.01 or count <= 0:
		return

	var template_mesh: Mesh = null
	var template_mat: Material = null
	var use_file := FlythroughLayerSlot.is_file_path(source)

	if use_file:
		# Instance the loaded asset multiple times.
		pass
	elif FlythroughLayerSlot.is_primitive_source(source):
		var kind := FlythroughLayerSlot.normalize_primitive(source)
		var proto := FlythroughPrimitives.spawn_scatter_template(kind)
		template_mesh = proto.mesh
		template_mat = proto.material_override
		proto.free()
	else:
		var proto2 := FlythroughPrimitives.spawn_scatter_template("cubes")
		template_mesh = proto2.mesh
		template_mat = proto2.material_override
		proto2.free()

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in count:
		var dist := (float(i) + 0.5) / float(count) * length
		var path_xf := _curve.sample_baked_with_rotation(dist, false)
		var side := Vector3(path_xf.basis.x.normalized())
		var up := Vector3(path_xf.basis.y.normalized())
		var offset := side * rng.randf_range(-1.6, 1.6) + up * rng.randf_range(-0.8, 0.9)
		var inst: Node3D
		if use_file:
			inst = FlythroughLayerSlot.load_asset_into(_scatter_root, source)
			if inst == null:
				continue
		else:
			var mesh_inst := MeshInstance3D.new()
			mesh_inst.mesh = template_mesh
			mesh_inst.material_override = template_mat
			_scatter_root.add_child(mesh_inst)
			inst = mesh_inst
			_scatter_meshes.append(mesh_inst)
		inst.position = path_xf.origin + offset
		inst.scale = Vector3.ONE * rng.randf_range(0.7, 1.3)
		_scatter_base_scales.append(inst.scale)


func _process(delta: float) -> void:
	if _rig:
		_rig.fly_speed = fly_speed
		_rig.advance(delta)
	if _camera and _light:
		_light.global_position = _camera.global_position + Vector3(0, 1.2, 0)
	if _follow_centerpiece and _curve and _center_root.get_child_count() > 0 and _rig:
		var ahead := fposmod(_rig.get_distance() + 10.0, maxf(_rig.get_path_length(), 0.01))
		var xf := _curve.sample_baked_with_rotation(ahead, false)
		_center_root.global_position = xf.origin


func apply_audio_state(state: AudioState) -> void:
	if not RH.enabled():
		_reset_reactive_scales()
		return
	# Environment — subtle light only when targeted (no strobing emission).
	if RH.applies_to("environment"):
		if RH.affect_light() and _light:
			_light.light_energy = 0.85 + state.energy * 0.6
	elif _light:
		_light.light_energy = 1.0

	# Scatter
	if RH.applies_to("scatter"):
		_apply_scatter_audio(state)
	else:
		_reset_scatter_scales()

	# Centerpiece (foreground is an alias via ReactivityHub)
	if RH.applies_to("centerpiece"):
		_apply_centerpiece_audio(state)
	else:
		_reset_centerpiece_scale()


func _apply_centerpiece_audio(state: AudioState) -> void:
	var node: Node3D = null
	if _center_root.get_child_count() > 0 and _center_root.get_child(0) is Node3D:
		node = _center_root.get_child(0) as Node3D
	if node == null:
		return
	if RH.affect_scale():
		var reactive := state.bass * 1.2 + state.energy * 0.5
		if state.beat:
			reactive *= 1.25
		var amt := clampf(1.0 + reactive * RH.scale_amount() * 0.12, 0.5, 8.0)
		node.scale = _center_base_scale * RH.scale_vector(amt)
	if RH.affect_rotation():
		node.rotate_y(state.mids * 0.04)
	if RH.affect_emission() and node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = mi.material_override
			mat.emission_enabled = true
			mat.emission_energy_multiplier = 0.4 + state.mids * 2.0


func _apply_scatter_audio(state: AudioState) -> void:
	if RH.affect_scale():
		var reactive := state.highs * 0.8 + state.energy * 0.4
		var amt := clampf(1.0 + reactive * RH.scale_amount() * 0.1, 0.4, 6.0)
		var scale_vec := RH.scale_vector(amt)
		for i in _scatter_meshes.size():
			var base: Vector3 = _scatter_base_scales[i] if i < _scatter_base_scales.size() else Vector3.ONE
			_scatter_meshes[i].scale = base * scale_vec
	if RH.affect_emission():
		for mi in _scatter_meshes:
			if mi.material_override is StandardMaterial3D:
				var mat: StandardMaterial3D = mi.material_override
				mat.emission_enabled = true
				mat.emission_energy_multiplier = 0.2 + state.highs * 1.5


func _reset_reactive_scales() -> void:
	_reset_centerpiece_scale()
	_reset_scatter_scales()
	if _light:
		_light.light_energy = 1.0


func _reset_centerpiece_scale() -> void:
	if _center_root.get_child_count() > 0 and _center_root.get_child(0) is Node3D:
		(_center_root.get_child(0) as Node3D).scale = _center_base_scale


func _reset_scatter_scales() -> void:
	for i in _scatter_meshes.size():
		var base: Vector3 = _scatter_base_scales[i] if i < _scatter_base_scales.size() else Vector3.ONE
		_scatter_meshes[i].scale = base


func set_cue_param(key: String, value: Variant) -> void:
	match key:
		"speed", "fly_speed":
			fly_speed = float(value)
			if _rig:
				_rig.fly_speed = fly_speed
		"environment", "scatter", "centerpiece":
			if value is Dictionary:
				set_layer_source(key, value)
		"follow_centerpiece":
			_follow_centerpiece = bool(value)
		"layer":
			# Expect { "id": "scatter", "config": { ... } }
			if value is Dictionary:
				var d: Dictionary = value
				set_layer_source(str(d.get("id", "")), d.get("config", {}) as Dictionary)
