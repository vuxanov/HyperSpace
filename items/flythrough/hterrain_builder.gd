extends RefCounted
class_name FlythroughHTerrainBuilder

## Runtime HTerrain generation via zylann.hterrain (higher-detail noise + procedural ground).

const HTerrain = preload("res://addons/zylann.hterrain/hterrain.gd")
const HTerrainData = preload("res://addons/zylann.hterrain/hterrain_data.gd")
const HTerrainTextureSet = preload("res://addons/zylann.hterrain/hterrain_texture_set.gd")

## Preset id → generation knobs (resolution 513, denser map_scale for mesh detail).
const PRESETS := {
	"hills": {
		"seed": 11,
		"base_freq": 0.0045,
		"detail_freq": 0.028,
		"height": 22.0,
		"detail_amp": 3.5,
		"ridge": 0.0,
		"map_scale": Vector3(1.15, 1.0, 1.15),
		"resolution": 513,
		"fly_clearance": 11.0,
	},
	"mountains": {
		"seed": 42,
		"base_freq": 0.0032,
		"detail_freq": 0.022,
		"height": 62.0,
		"detail_amp": 7.0,
		"ridge": 0.4,
		"map_scale": Vector3(1.25, 1.15, 1.25),
		"resolution": 513,
		"fly_clearance": 18.0,
	},
	"canyon": {
		"seed": 77,
		"base_freq": 0.0055,
		"detail_freq": 0.03,
		"height": 36.0,
		"detail_amp": 4.0,
		"ridge": 0.82,
		"map_scale": Vector3(1.1, 1.0, 1.1),
		"resolution": 513,
		"fly_clearance": 15.0,
	},
}


static func normalize_preset(kind: String) -> String:
	var k := kind.replace("primitive:", "")
	if k.begins_with("hterrain_"):
		k = k.substr("hterrain_".length())
	if PRESETS.has(k):
		return k
	return "hills"


static func is_hterrain_kind(kind: String) -> bool:
	var k := kind.replace("primitive:", "")
	return k.begins_with("hterrain") or PRESETS.has(k)


static func spawn(parent: Node3D, kind: String) -> Dictionary:
	var preset_id := normalize_preset(kind)
	var cfg: Dictionary = PRESETS[preset_id]
	var resolution: int = int(cfg.get("resolution", 513))
	var height_mul: float = float(cfg.get("height", 22.0))
	var detail_amp: float = float(cfg.get("detail_amp", 3.0))
	var base_freq: float = float(cfg.get("base_freq", 0.004))
	var detail_freq: float = float(cfg.get("detail_freq", 0.025))
	var ridge: float = float(cfg.get("ridge", 0.0))
	var map_scale: Vector3 = cfg.get("map_scale", Vector3.ONE)
	var fly_clearance: float = float(cfg.get("fly_clearance", 12.0))
	var noise_seed: int = int(cfg.get("seed", 1))

	var data := HTerrainData.new()
	data.resize(resolution)

	var base_noise := FastNoiseLite.new()
	base_noise.seed = noise_seed
	base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base_noise.frequency = base_freq
	base_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	base_noise.fractal_octaves = 6
	base_noise.fractal_lacunarity = 2.1
	base_noise.fractal_gain = 0.5

	var detail_noise := FastNoiseLite.new()
	detail_noise.seed = noise_seed + 91
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.frequency = detail_freq
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.fractal_octaves = 4
	detail_noise.fractal_gain = 0.45

	var heightmap: Image = data.get_image(HTerrainData.CHANNEL_HEIGHT)
	var normalmap: Image = data.get_image(HTerrainData.CHANNEL_NORMAL)
	var splatmap: Image = data.get_image(HTerrainData.CHANNEL_SPLAT)
	var colormap: Image = data.get_image(HTerrainData.CHANNEL_COLOR)

	# Precompute heights for proper normals (avoids double noise / soft demo edges).
	var heights := PackedFloat32Array()
	heights.resize(resolution * resolution)
	for z in resolution:
		for x in resolution:
			heights[x + z * resolution] = _sample_height(
				base_noise, detail_noise, float(x), float(z), height_mul, detail_amp, ridge
			)

	var step := 1.0
	for z in resolution:
		for x in resolution:
			var i := x + z * resolution
			var h: float = heights[i]
			heightmap.set_pixel(x, z, Color(h, 0.0, 0.0))

			var h_l: float = heights[maxi(x - 1, 0) + z * resolution]
			var h_r: float = heights[mini(x + 1, resolution - 1) + z * resolution]
			var h_d: float = heights[x + maxi(z - 1, 0) * resolution]
			var h_u: float = heights[x + mini(z + 1, resolution - 1) * resolution]
			var normal := Vector3(h_l - h_r, 2.0 * step, h_d - h_u).normalized()
			normalmap.set_pixel(x, z, HTerrainData.encode_normal(normal))

			var slope := clampf(1.0 - normal.dot(Vector3.UP), 0.0, 1.0)
			var elev := h / maxf(height_mul + detail_amp, 0.01)
			# Grass flats, rock slopes/peaks, dirt/sand low basins
			var rock := clampf(slope * 1.8 + maxf(elev - 0.35, 0.0) * 0.9, 0.0, 1.0)
			var sand := clampf((-elev) * 1.2 + 0.15, 0.0, 1.0) * (1.0 - rock * 0.7)
			var grass := clampf(1.0 - rock - sand, 0.05, 1.0)
			var total := grass + rock + sand + 0.0001
			splatmap.set_pixel(x, z, Color(grass / total, rock / total, sand / total, 0.0))

			# Subtle tint variation (avoids plastic flat look)
			var tint_n := detail_noise.get_noise_2d(float(x) * 0.4, float(z) * 0.4)
			var tint := Color(0.92 + tint_n * 0.08, 0.95 + tint_n * 0.05, 0.88, 1.0)
			colormap.set_pixel(x, z, tint)

	var region := Rect2(Vector2.ZERO, heightmap.get_size())
	data.notify_region_change(region, HTerrainData.CHANNEL_HEIGHT)
	data.notify_region_change(region, HTerrainData.CHANNEL_NORMAL)
	data.notify_region_change(region, HTerrainData.CHANNEL_SPLAT)
	data.notify_region_change(region, HTerrainData.CHANNEL_COLOR)

	var texture_set := _make_texture_set()
	var terrain: Node3D = HTerrain.new()
	terrain.set_shader_type(HTerrain.SHADER_CLASSIC4)
	terrain.set_data(data)
	terrain.set_texture_set(texture_set)
	terrain.set_map_scale(map_scale)
	terrain.set_centered(true)
	# Tighter ground UVs → more visible texture detail while flying.
	if terrain.has_method("set_shader_param"):
		terrain.call("set_shader_param", "u_ground_uv_scale_per_texture", Color(6.0, 7.0, 5.5, 8.0))
		terrain.call("set_shader_param", "u_ground_uv_scale", 6.0)
	terrain.name = "HTerrain_%s" % preset_id
	parent.add_child(terrain)

	return {
		"terrain": terrain,
		"data": data,
		"map_scale": map_scale,
		"resolution": resolution,
		"fly_clearance": fly_clearance,
		"preset": preset_id,
	}


static func _sample_height(
	base_noise: FastNoiseLite,
	detail_noise: FastNoiseLite,
	x: float,
	z: float,
	height_mul: float,
	detail_amp: float,
	ridge: float
) -> float:
	var n := base_noise.get_noise_2d(x, z)
	if ridge > 0.0:
		var r := 1.0 - absf(n)
		r *= r
		n = lerpf(n, r * 2.0 - 1.0, ridge)
	var d := detail_noise.get_noise_2d(x, z)
	# Warp detail by slope of base for craggier mountains
	return n * height_mul + d * detail_amp * (0.55 + absf(n) * 0.7)


static func build_flight_path(meta: Dictionary, points: int = 36) -> Curve3D:
	var data: HTerrainData = meta.get("data")
	var map_scale: Vector3 = meta.get("map_scale", Vector3.ONE)
	var clearance: float = float(meta.get("fly_clearance", 12.0))
	if data == null:
		return FlythroughPathBuilder.overland(80.0, 12.0)
	var res := data.get_resolution()
	var half := 0.5 * float(res - 1)
	var curve := Curve3D.new()
	curve.bake_interval = 0.75
	var count := maxi(points, 4)
	for i in count:
		var t := float(i) / float(count - 1)
		var cell_x := int(half)
		var cell_z := int(lerpf(float(res) * 0.1, float(res) * 0.9, t))
		var h := data.get_height_at(cell_x, cell_z)
		var local := Vector3(
			(float(cell_x) - half) * map_scale.x,
			h * map_scale.y + clearance,
			(float(cell_z) - half) * map_scale.z
		)
		curve.add_point(local)
	return curve


static func _make_texture_set() -> HTerrainTextureSet:
	var texture_set := HTerrainTextureSet.new()
	texture_set.set_mode(HTerrainTextureSet.MODE_TEXTURES)
	# Grass, rock, dirt/sand — procedural but detailed (256²)
	var defs := [
		{"seed": 3, "c0": Color(0.22, 0.38, 0.16), "c1": Color(0.34, 0.48, 0.2), "rough": 0.85, "bump": 0.55},
		{"seed": 17, "c0": Color(0.28, 0.27, 0.26), "c1": Color(0.48, 0.45, 0.4), "rough": 0.7, "bump": 1.0},
		{"seed": 29, "c0": Color(0.45, 0.36, 0.22), "c1": Color(0.62, 0.52, 0.34), "rough": 0.9, "bump": 0.45},
	]
	for i in defs.size():
		var d: Dictionary = defs[i]
		texture_set.insert_slot(-1)
		var pair := _make_ground_maps(
			int(d["seed"]), d["c0"], d["c1"], float(d["rough"]), float(d["bump"])
		)
		texture_set.set_texture(i, HTerrainTextureSet.TYPE_ALBEDO_BUMP, pair["albedo_bump"])
		texture_set.set_texture(i, HTerrainTextureSet.TYPE_NORMAL_ROUGHNESS, pair["normal_rough"])
	return texture_set


static func _make_ground_maps(
	tex_seed: int,
	c0: Color,
	c1: Color,
	roughness: float,
	bump_strength: float
) -> Dictionary:
	var size := 256
	var n := FastNoiseLite.new()
	n.seed = tex_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.045
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5

	var n2 := FastNoiseLite.new()
	n2.seed = tex_seed + 5
	n2.noise_type = FastNoiseLite.TYPE_CELLULAR
	n2.frequency = 0.08
	n2.fractal_octaves = 1

	var height := PackedFloat32Array()
	height.resize(size * size)
	var albedo := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var fx := float(x)
			var fy := float(y)
			var a := n.get_noise_2d(fx, fy) * 0.5 + 0.5
			var b := n2.get_noise_2d(fx, fy) * 0.5 + 0.5
			var h := clampf(a * 0.75 + b * 0.25, 0.0, 1.0)
			height[x + y * size] = h
			var col := c0.lerp(c1, h)
			# Fine grit
			var grit := n.get_noise_2d(fx * 3.0, fy * 3.0) * 0.06
			col.r = clampf(col.r + grit, 0.0, 1.0)
			col.g = clampf(col.g + grit, 0.0, 1.0)
			col.b = clampf(col.b + grit * 0.7, 0.0, 1.0)
			var bump := clampf(h * bump_strength, 0.0, 1.0)
			albedo.set_pixel(x, y, Color(col.r, col.g, col.b, bump))

	var normal_img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var h_c: float = height[x + y * size]
			var h_r: float = height[(x + 1) % size + y * size]
			var h_u: float = height[x + ((y + 1) % size) * size]
			var dx := (h_c - h_r) * bump_strength * 4.0
			var dy := (h_c - h_u) * bump_strength * 4.0
			var nn := Vector3(dx, dy, 1.0).normalized()
			# Store tangent normal in RGB, roughness in A (plugin convention)
			normal_img.set_pixel(x, y, Color(
				nn.x * 0.5 + 0.5,
				nn.y * 0.5 + 0.5,
				nn.z * 0.5 + 0.5,
				roughness
			))

	return {
		"albedo_bump": ImageTexture.create_from_image(albedo),
		"normal_rough": ImageTexture.create_from_image(normal_img),
	}
