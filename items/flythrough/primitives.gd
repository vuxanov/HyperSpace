extends RefCounted
class_name FlythroughPrimitives

## Rudimentary meshes for testing layer slots before real uploads.


static func make_material(color: Color, emission_strength: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	if emission_strength > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission_strength
	return mat


static func spawn_environment(kind: String, parent: Node3D) -> void:
	match kind:
		"flat_plane", "primitive:flat_plane":
			_spawn_flat_plane(parent)
		# Former HTerrain presets — fall back to flat plane (addon removed).
		"hterrain_hills", "primitive:hterrain_hills", "hills", \
		"hterrain_mountains", "primitive:hterrain_mountains", "mountains", \
		"hterrain_canyon", "primitive:hterrain_canyon", "canyon":
			_spawn_flat_plane(parent)
		"box_corridor", "primitive:box_corridor", _:
			_spawn_box_corridor(parent)


static func spawn_centerpiece(kind: String, parent: Node3D) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	match kind:
		"icosphere", "primitive:icosphere":
			var sphere := SphereMesh.new()
			sphere.radius = 0.55
			sphere.height = 1.1
			sphere.radial_segments = 16
			sphere.rings = 8
			mesh_inst.mesh = sphere
			mesh_inst.material_override = make_material(Color(0.95, 0.55, 0.25), 0.0)
		"torus", "primitive:torus", _:
			var torus := TorusMesh.new()
			torus.inner_radius = 0.35
			torus.outer_radius = 0.7
			torus.rings = 24
			torus.ring_segments = 16
			mesh_inst.mesh = torus
			mesh_inst.material_override = make_material(Color(0.45, 0.75, 1.0), 0.0)
	parent.add_child(mesh_inst)
	return mesh_inst


static func spawn_scatter_template(kind: String) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	match kind:
		"spheres", "primitive:spheres":
			var sphere := SphereMesh.new()
			sphere.radius = 0.12
			sphere.height = 0.24
			mesh_inst.mesh = sphere
			mesh_inst.material_override = make_material(Color(0.7, 0.85, 0.95), 0.0)
		"cubes", "primitive:cubes", _:
			var box := BoxMesh.new()
			box.size = Vector3(0.2, 0.2, 0.2)
			mesh_inst.mesh = box
			mesh_inst.material_override = make_material(Color(0.55, 0.7, 0.85), 0.0)
	return mesh_inst


static func _spawn_box_corridor(parent: Node3D) -> void:
	var length := 64.0
	var half_w := 2.2
	var half_h := 2.0
	var wall_mat := make_material(Color(0.12, 0.13, 0.16))
	var floor_mat := make_material(Color(0.16, 0.17, 0.2))
	var accent_mat := make_material(Color(0.22, 0.28, 0.34), 0.08)
	# Floor
	_add_box(parent, Vector3(half_w * 2.0, 0.08, length), Vector3(0, -half_h, -length * 0.5), floor_mat)
	# Ceiling
	_add_box(parent, Vector3(half_w * 2.0, 0.08, length), Vector3(0, half_h, -length * 0.5), wall_mat)
	# Left / right walls
	_add_box(parent, Vector3(0.08, half_h * 2.0, length), Vector3(-half_w, 0, -length * 0.5), wall_mat)
	_add_box(parent, Vector3(0.08, half_h * 2.0, length), Vector3(half_w, 0, -length * 0.5), wall_mat)
	# Soft floor center stripe for orientation (not flashing)
	_add_box(parent, Vector3(0.6, 0.02, length), Vector3(0, -half_h + 0.06, -length * 0.5), accent_mat)


static func _spawn_flat_plane(parent: Node3D) -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	ground.mesh = plane
	ground.material_override = make_material(Color(0.18, 0.22, 0.18))
	ground.position = Vector3(0, 0, -40)
	parent.add_child(ground)
	# A few distant blocks as "land" landmarks
	var landmark_mat := make_material(Color(0.25, 0.3, 0.28))
	for i in 12:
		var x := sin(float(i) * 1.7) * 28.0
		var z := -8.0 - float(i) * 6.0
		_add_box(parent, Vector3(2.5, 1.0 + float(i % 3), 2.5), Vector3(x, 0.5, z), landmark_mat)


static func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	inst.mesh = box
	inst.material_override = mat
	inst.position = pos
	parent.add_child(inst)
