extends RefCounted
class_name FlythroughAssetCatalog

## Known project assets under `3D models/` for fly-through layers.


const CONVENT_GLB := "res://3D models/chiostro-ex-convento-di-civitaretenga-laquila/source/02_08_2026 (1).glb"
const STREET_CITY_FBX := "res://3D models/street-city-buildings-8/source/улица скетч.fbx"
const BURGER_GLB := "res://3D models/stylized-3d-cheeseburger-rapid-assets/source/438b5714-5600-4eef-b364-03f11e3a7fb8.glb"


static func default_environment_path() -> String:
	if ResourceLoader.exists(STREET_CITY_FBX) or FileAccess.file_exists(STREET_CITY_FBX):
		return STREET_CITY_FBX
	if ResourceLoader.exists(CONVENT_GLB) or FileAccess.file_exists(CONVENT_GLB):
		return CONVENT_GLB
	return "primitive:box_corridor"


static func default_burger_path() -> String:
	if ResourceLoader.exists(BURGER_GLB) or FileAccess.file_exists(BURGER_GLB):
		return BURGER_GLB
	return "primitive:torus"


static func default_layer_configs() -> Dictionary:
	var params := default_flythrough_params()
	return {
		"environment": (params.get("environment", {}) as Dictionary).duplicate(true),
		"scatter": (params.get("scatter", {}) as Dictionary).duplicate(true),
		"centerpiece": (params.get("centerpiece", {}) as Dictionary).duplicate(true),
	}


static func default_flythrough_params() -> Dictionary:
	var env := default_environment_path()
	var burger := default_burger_path()
	var env_cfg: Dictionary
	var sc_cfg: Dictionary
	var cp_cfg: Dictionary
	if env.begins_with("primitive:"):
		env_cfg = {"source": env}
	else:
		env_cfg = {"path": env}
	if burger.begins_with("primitive:"):
		sc_cfg = {"source": burger, "count": 18}
		cp_cfg = {"source": burger}
	else:
		sc_cfg = {"path": burger, "count": 18}
		cp_cfg = {"path": burger}
	return {
		"style": "flythrough",
		"speed": 2.0,
		"centerpiece_locked": true,
		"center_distance": 2.75,
		"environment": env_cfg,
		"scatter": sc_cfg,
		"centerpiece": cp_cfg,
		"lighting": default_lighting_config(),
	}


## Empty fly-through stage for the three-tab asset UI (no default props / sequence).
static func blank_stage_params() -> Dictionary:
	return {
		"style": "flythrough",
		"speed": 2.0,
		"centerpiece_locked": true,
		"center_distance": 2.75,
		"environment": {"source": "primitive:box_corridor"},
		"scatter": empty_scatter_config(),
		"centerpiece": empty_centerpiece_config(),
		"lighting": default_lighting_config(),
	}


static func default_lighting_config() -> Dictionary:
	## Neutral studio fill — avoid strong blue ambient cast so textures read correctly.
	return {
		"preset": "studio",
		"sun_energy": 1.05,
		"sun_color": {"r": 1.0, "g": 0.98, "b": 0.94},
		"sun_rotation_deg": {"x": -42.0, "y": 35.0, "z": 0.0},
		"ambient_energy": 0.7,
		"ambient_color": {"r": 0.55, "g": 0.55, "b": 0.56},
		"bg_color": {"r": 0.08, "g": 0.08, "b": 0.09},
		"sky_top": {"r": 0.45, "g": 0.48, "b": 0.52},
		"sky_horizon": {"r": 0.65, "g": 0.66, "b": 0.68},
		"use_sky": false,
		"fog_density": 0.0,
		"fill_energy": 0.55,
	}


const HDRI_DIR := "res://assets/hdris/"


static func hdri_path(file_name: String) -> String:
	return HDRI_DIR + file_name


static func hdri_lighting_config(preset_id: String, path: String, extras: Dictionary = {}) -> Dictionary:
	## IBL-first look: panorama sky visible as background; soft sun/fill; no fog wash.
	var cfg := {
		"preset": preset_id,
		"hdri_path": path,
		"use_hdri": true,
		"use_sky": true,
		"sun_energy": 0.35,
		"sun_color": {"r": 1.0, "g": 0.98, "b": 0.95},
		"sun_rotation_deg": {"x": -50.0, "y": 30.0, "z": 0.0},
		"ambient_energy": 0.55,
		"ambient_color": {"r": 0.5, "g": 0.5, "b": 0.5},
		"bg_color": {"r": 0.05, "g": 0.05, "b": 0.05},
		"fog_density": 0.0,
		"fill_energy": 0.12,
		"tonemap_exposure": 0.95,
		"background_energy": 1.0,
		"sky_energy": 1.0,
	}
	for k in extras.keys():
		cfg[k] = extras[k]
	return cfg


static func lighting_chooser_entries() -> Array[Dictionary]:
	## Procedural looks + Poly Haven CC0 HDRIs under assets/hdris/.
	var entries: Array[Dictionary] = [
		{
			"id": "studio",
			"label": "Studio fill",
			"config": default_lighting_config(),
		},
	]
	var hdris := [
		{
			"id": "hdri_studio_small_08",
			"label": "HDRI · Studio Small 08",
			"file": "studio_small_08_1k.hdr",
			"extras": {"sun_energy": 0.35, "tonemap_exposure": 0.95},
		},
		{
			"id": "hdri_photo_studio",
			"label": "HDRI · Photo Studio Loft",
			"file": "photo_studio_loft_hall_1k.hdr",
			"extras": {"sun_energy": 0.3, "tonemap_exposure": 1.0},
		},
		{
			"id": "hdri_warehouse",
			"label": "HDRI · Empty Warehouse",
			"file": "empty_warehouse_01_1k.hdr",
			"extras": {"sun_energy": 0.55, "fill_energy": 0.2, "tonemap_exposure": 1.05},
		},
		{
			"id": "hdri_kloppenheim",
			"label": "HDRI · Outdoor Pure Sky",
			"file": "kloppenheim_06_puresky_1k.hdr",
			"extras": {
				"sun_energy": 0.9,
				"sun_rotation_deg": {"x": -55.0, "y": 25.0, "z": 0.0},
				"fill_energy": 0.1,
				"tonemap_exposure": 1.1,
			},
		},
		{
			"id": "hdri_venice_sunset",
			"label": "HDRI · Venice Sunset",
			"file": "venice_sunset_1k.hdr",
			"extras": {
				"sun_energy": 0.7,
				"sun_color": {"r": 1.0, "g": 0.75, "b": 0.45},
				"sun_rotation_deg": {"x": -12.0, "y": 40.0, "z": 0.0},
				"fill_energy": 0.2,
				"tonemap_exposure": 1.05,
			},
		},
	]
	for spec in hdris:
		var path := hdri_path(str(spec["file"]))
		if ResourceLoader.exists(path) or FileAccess.file_exists(path):
			entries.append({
				"id": str(spec["id"]),
				"label": str(spec["label"]),
				"config": hdri_lighting_config(
					str(spec["id"]),
					path,
					spec.get("extras", {}) as Dictionary
				),
			})
	entries.append_array([
		{
			"id": "noon_sun",
			"label": "Noon sun",
			"config": {
				"preset": "noon_sun",
				"sun_energy": 1.6,
				"sun_color": {"r": 1.0, "g": 0.98, "b": 0.92},
				"sun_rotation_deg": {"x": -75.0, "y": 20.0, "z": 0.0},
				"ambient_energy": 0.55,
				"ambient_color": {"r": 0.55, "g": 0.58, "b": 0.62},
				"bg_color": {"r": 0.55, "g": 0.62, "b": 0.72},
				"sky_top": {"r": 0.35, "g": 0.5, "b": 0.75},
				"sky_horizon": {"r": 0.75, "g": 0.8, "b": 0.88},
				"use_sky": true,
				"fog_density": 0.006,
				"fill_energy": 0.35,
			},
		},
		{
			"id": "golden_hour",
			"label": "Golden hour",
			"config": {
				"preset": "golden_hour",
				"sun_energy": 1.35,
				"sun_color": {"r": 1.0, "g": 0.62, "b": 0.28},
				"sun_rotation_deg": {"x": -18.0, "y": 50.0, "z": 0.0},
				"ambient_energy": 0.45,
				"ambient_color": {"r": 0.55, "g": 0.35, "b": 0.25},
				"bg_color": {"r": 0.35, "g": 0.18, "b": 0.12},
				"sky_top": {"r": 0.15, "g": 0.2, "b": 0.45},
				"sky_horizon": {"r": 1.0, "g": 0.55, "b": 0.25},
				"use_sky": true,
				"fog_density": 0.02,
				"fill_energy": 0.7,
			},
		},
		{
			"id": "blue_hour",
			"label": "Blue hour",
			"config": {
				"preset": "blue_hour",
				"sun_energy": 0.35,
				"sun_color": {"r": 0.45, "g": 0.55, "b": 1.0},
				"sun_rotation_deg": {"x": -8.0, "y": -30.0, "z": 0.0},
				"ambient_energy": 0.7,
				"ambient_color": {"r": 0.2, "g": 0.28, "b": 0.55},
				"bg_color": {"r": 0.05, "g": 0.08, "b": 0.18},
				"sky_top": {"r": 0.05, "g": 0.08, "b": 0.22},
				"sky_horizon": {"r": 0.25, "g": 0.35, "b": 0.65},
				"use_sky": true,
				"fog_density": 0.025,
				"fill_energy": 1.2,
			},
		},
		{
			"id": "neon_night",
			"label": "Neon night",
			"config": {
				"preset": "neon_night",
				"sun_energy": 0.15,
				"sun_color": {"r": 0.6, "g": 0.2, "b": 1.0},
				"sun_rotation_deg": {"x": -25.0, "y": 120.0, "z": 0.0},
				"ambient_energy": 0.4,
				"ambient_color": {"r": 0.15, "g": 0.05, "b": 0.25},
				"bg_color": {"r": 0.02, "g": 0.02, "b": 0.05},
				"sky_top": {"r": 0.02, "g": 0.0, "b": 0.08},
				"sky_horizon": {"r": 0.15, "g": 0.0, "b": 0.2},
				"use_sky": true,
				"fog_density": 0.03,
				"fill_energy": 1.8,
			},
		},
		{
			"id": "overcast",
			"label": "Overcast soft",
			"config": {
				"preset": "overcast",
				"sun_energy": 0.25,
				"sun_color": {"r": 0.85, "g": 0.88, "b": 0.95},
				"sun_rotation_deg": {"x": -55.0, "y": 10.0, "z": 0.0},
				"ambient_energy": 1.15,
				"ambient_color": {"r": 0.7, "g": 0.72, "b": 0.78},
				"bg_color": {"r": 0.55, "g": 0.58, "b": 0.62},
				"sky_top": {"r": 0.55, "g": 0.58, "b": 0.65},
				"sky_horizon": {"r": 0.7, "g": 0.72, "b": 0.75},
				"use_sky": true,
				"fog_density": 0.018,
				"fill_energy": 0.9,
			},
		},
		{
			"id": "dramatic",
			"label": "Dramatic rim",
			"config": {
				"preset": "dramatic",
				"sun_energy": 2.2,
				"sun_color": {"r": 1.0, "g": 0.9, "b": 0.75},
				"sun_rotation_deg": {"x": -30.0, "y": 140.0, "z": 0.0},
				"ambient_energy": 0.25,
				"ambient_color": {"r": 0.2, "g": 0.2, "b": 0.22},
				"bg_color": {"r": 0.02, "g": 0.02, "b": 0.04},
				"sky_top": {"r": 0.1, "g": 0.1, "b": 0.14},
				"sky_horizon": {"r": 0.3, "g": 0.25, "b": 0.2},
				"use_sky": true,
				"fog_density": 0.012,
				"fill_energy": 0.55,
			},
		},
	])
	return entries


static func empty_centerpiece_config() -> Dictionary:
	return {"source": ""}


static func empty_scatter_config() -> Dictionary:
	return {"source": "primitive:cubes", "count": 0}


static func is_empty_layer_config(config: Variant) -> bool:
	if not (config is Dictionary):
		return true
	var d: Dictionary = config
	var source := str(d.get("source", "")).strip_edges()
	var path := str(d.get("path", "")).strip_edges()
	if path != "":
		# Scatter with explicit count 0 is treated as empty.
		if d.has("count") and int(d["count"]) <= 0:
			return true
		return false
	if source == "":
		return true
	if d.has("count") and int(d["count"]) <= 0:
		return true
	return false


## Chooser entries for main character / scatter props (UI list + sequence builder).
static func prop_chooser_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if ResourceLoader.exists(BURGER_GLB) or FileAccess.file_exists(BURGER_GLB):
		entries.append({
			"id": "burger",
			"label": "Stylized burger",
			"roles": ["centerpiece", "scatter"],
			"config": {"path": BURGER_GLB},
		})
	entries.append({
		"id": "torus",
		"label": "Torus (debug)",
		"roles": ["centerpiece"],
		"config": {"source": "primitive:torus"},
	})
	entries.append({
		"id": "icosphere",
		"label": "Icosphere (debug)",
		"roles": ["centerpiece"],
		"config": {"source": "primitive:icosphere"},
	})
	entries.append({
		"id": "cubes",
		"label": "Cubes (debug)",
		"roles": ["scatter"],
		"config": {"source": "primitive:cubes"},
	})
	entries.append({
		"id": "spheres",
		"label": "Spheres (debug)",
		"roles": ["scatter"],
		"config": {"source": "primitive:spheres"},
	})
	return entries


static func environment_chooser_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if ResourceLoader.exists(STREET_CITY_FBX) or FileAccess.file_exists(STREET_CITY_FBX):
		entries.append({
			"id": "street_city",
			"label": "Street city buildings",
			"config": {"path": STREET_CITY_FBX},
		})
	if ResourceLoader.exists(CONVENT_GLB) or FileAccess.file_exists(CONVENT_GLB):
		entries.append({
			"id": "ex_convento",
			"label": "Ex-convento (chiostro)",
			"config": {"path": CONVENT_GLB},
		})
	entries.append({
		"id": "box_corridor",
		"label": "Box corridor (debug)",
		"config": {"source": "primitive:box_corridor"},
	})
	entries.append({
		"id": "hills",
		"label": "HTerrain hills",
		"config": {"source": "primitive:hterrain_hills"},
	})
	entries.append({
		"id": "mountains",
		"label": "HTerrain mountains",
		"config": {"source": "primitive:hterrain_mountains"},
	})
	return entries


static func find_prop_entry(entry_id: String) -> Dictionary:
	for entry in prop_chooser_entries():
		if str(entry.get("id", "")) == entry_id:
			return entry
	return {}


static func layer_config_from_entry(entry: Dictionary, role: String, scatter_count: int = 18) -> Dictionary:
	var cfg: Dictionary = (entry.get("config", {}) as Dictionary).duplicate(true)
	if role == "scatter":
		cfg["count"] = scatter_count
	return cfg


static func short_label_for_config(config: Variant) -> String:
	if config is Dictionary:
		var d: Dictionary = config
		if d.has("preset") and str(d.get("preset", "")).strip_edges() != "":
			var preset := str(d["preset"])
			for entry in lighting_chooser_entries():
				if str(entry.get("id", "")) == preset:
					return str(entry.get("label", preset))
			if str(d.get("hdri_path", "")).strip_edges() != "":
				return str(d["hdri_path"]).get_file().get_basename()
			return preset.replace("_", " ")
		if d.has("hdri_path") and str(d["hdri_path"]).strip_edges() != "":
			return str(d["hdri_path"]).get_file().get_basename()
		if d.has("path") and str(d["path"]).strip_edges() != "":
			var path := str(d["path"])
			if path.contains("cheeseburger") or path.contains("438b5714"):
				return "Stylized burger"
			if path.contains("street-city") or path.contains("улица"):
				return "Street city"
			if path.contains("chiostro") or path.contains("convento"):
				return "Ex-convento"
			var ext := path.get_extension().to_lower()
			if ext in ["gif", "mp4", "webm", "ogv", "mov", "avi"]:
				return path.get_file()
			if ext in ["png", "jpg", "jpeg", "webp", "bmp", "svg"]:
				return path.get_file()
			return path.get_file()
		if d.has("source"):
			return str(d["source"]).replace("primitive:", "")
	return "?"


## Default timed progression: one main prop, then scatters that change.
static func default_element_sequence() -> Array:
	var burger := default_burger_path()
	var main_cfg: Dictionary
	var sc_burger: Dictionary
	if burger.begins_with("primitive:"):
		main_cfg = {"source": burger}
		sc_burger = {"source": burger, "count": 18}
	else:
		main_cfg = {"path": burger}
		sc_burger = {"path": burger, "count": 18}
	return [
		{
			"id": "main_only",
			"label": "Main only",
			"duration": 8.0,
			"centerpiece": main_cfg.duplicate(true),
			"scatter": _empty_scatter(sc_burger),
		},
		{
			"id": "scatter_main",
			"label": "Scatter: same as main",
			"duration": 10.0,
			"centerpiece": main_cfg.duplicate(true),
			"scatter": sc_burger.duplicate(true),
		},
		{
			"id": "scatter_cubes",
			"label": "Scatter: cubes",
			"duration": 10.0,
			"centerpiece": main_cfg.duplicate(true),
			"scatter": {"source": "primitive:cubes", "count": 36},
		},
		{
			"id": "scatter_spheres",
			"label": "Scatter: spheres",
			"duration": 10.0,
			"centerpiece": main_cfg.duplicate(true),
			"scatter": {"source": "primitive:spheres", "count": 28},
		},
	]


static func _empty_scatter(template: Dictionary) -> Dictionary:
	var empty: Dictionary = template.duplicate(true)
	empty["count"] = 0
	return empty


static func sequence_total_duration(sequence: Array) -> float:
	var total := 0.0
	for step in sequence:
		if step is Dictionary:
			total += maxf(float((step as Dictionary).get("duration", 8.0)), 0.5)
	return total


static func make_sequence_step(mode: String, entry: Dictionary, duration: float = 8.0, scatter_count: int = 18, keep_centerpiece: Dictionary = {}) -> Dictionary:
	var label := str(entry.get("label", "Element"))
	var center: Dictionary
	var scatter: Dictionary
	match mode:
		"main_only":
			center = layer_config_from_entry(entry, "centerpiece")
			scatter = _empty_scatter(layer_config_from_entry(entry, "scatter", scatter_count))
			label = "Main: %s" % label
		"scatter":
			if keep_centerpiece.is_empty():
				center = layer_config_from_entry(entry, "centerpiece")
			else:
				center = keep_centerpiece.duplicate(true)
			scatter = layer_config_from_entry(entry, "scatter", scatter_count)
			label = "Scatter: %s ×%d" % [str(entry.get("label", "?")), scatter_count]
		"main_and_scatter":
			center = layer_config_from_entry(entry, "centerpiece")
			scatter = layer_config_from_entry(entry, "scatter", scatter_count)
			label = "Main+scatter: %s" % label
		_:
			center = layer_config_from_entry(entry, "centerpiece")
			scatter = layer_config_from_entry(entry, "scatter", scatter_count)
	return {
		"id": "%s_%s" % [mode, str(entry.get("id", "el"))],
		"label": label,
		"duration": maxf(duration, 0.5),
		"centerpiece": center,
		"scatter": scatter,
	}
