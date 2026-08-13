class_name BootCache
extends RefCounted

## Full playlist catalog warm set — must finish on splash before main UI appears.

const _AssetCache := preload("res://core/asset_cache.gd")
const _MediaImport := preload("res://core/media_import.gd")
const _SessionStore := preload("res://core/session_store.gd")
const _Catalog := preload("res://items/flythrough/asset_catalog.gd")

const MAIN_SCENE_PATH := "res://ui/main.tscn"

## Set by BootLoader when the full warm drained idle (sidebar uses this to skip UI).
static var full_warm_completed: bool = false

const FX_SHADER_PATHS := [
	"res://effects/ascii_effect.gdshader",
	"res://effects/feedback_effect.gdshader",
	"res://effects/glitch_effect.gdshader",
	"res://effects/chromatic_effect.gdshader",
	"res://effects/reaction_diffusion.gdshader",
	"res://effects/reaction_diffusion_sim.gdshader",
	"res://effects/noise_deform.gdshader",
	"res://effects/media_screen.gdshader",
	"res://effects/point_cloud.gdshader",
	"res://effects/lens_distort.gdshader",
]


static func collect_critical_paths() -> Array:
	## Same set playlist sidebar warms (session lists if present, else catalog defaults).
	## Includes env/hero/scatter models, HDRIs, and all playlist media — no post-main pass.
	var paths: Array = []
	var seen: Dictionary = {}
	_add_playlist_warm_paths(paths, seen)
	_add_active_session_stage_paths(paths, seen)
	return paths


static func collect_shader_paths() -> Array:
	var out: Array = []
	for p in FX_SHADER_PATHS:
		if ResourceLoader.exists(p):
			out.append(p)
	return out


static func mark_full_warm_completed() -> void:
	full_warm_completed = true


static func _add_playlist_warm_paths(paths: Array, seen: Dictionary) -> void:
	## Mirror playlist_sidebar._load_catalog_entries + session restore + _collect_all_playlist_paths.
	var lists := _resolve_sidebar_entry_lists()
	_add_entry_list_paths(paths, seen, lists.get("env", []), "environment")
	_add_entry_list_paths(paths, seen, lists.get("main", []), "centerpiece")
	_add_entry_list_paths(paths, seen, lists.get("scatter", []), "scatter")
	_add_entry_list_paths(paths, seen, lists.get("light", []), "lighting")


static func _resolve_sidebar_entry_lists() -> Dictionary:
	## Prefer saved session lists (what main will restore); else catalog chooser defaults.
	var data := _SessionStore.load_session()
	var sidebar: Variant = data.get("sidebar", {}) if not data.is_empty() else {}
	var use_session := sidebar is Dictionary and not (sidebar as Dictionary).is_empty()
	if use_session:
		var sb: Dictionary = sidebar
		# Only trust session when it actually stored list keys (same as sidebar restore).
		if sb.has("env_entries") or sb.has("main_entries") \
				or sb.has("scatter_entries") or sb.has("light_entries"):
			return {
				"env": _entries_or_catalog(sb, "env_entries", "env"),
				"main": _entries_or_catalog(sb, "main_entries", "main"),
				"scatter": _entries_or_catalog(sb, "scatter_entries", "scatter"),
				"light": _entries_or_catalog(sb, "light_entries", "light"),
			}
	return _catalog_entry_lists()


static func _entries_or_catalog(sb: Dictionary, key: String, kind: String) -> Array:
	## Honor explicit empty lists (user cleared catalog rows). Missing key → catalog default.
	if sb.has(key):
		return _SessionStore.entries_from_variant(sb.get(key, []))
	var catalog := _catalog_entry_lists()
	return catalog.get(kind, []) as Array


static func _catalog_entry_lists() -> Dictionary:
	var env: Array = []
	for entry in _Catalog.environment_chooser_entries():
		env.append((entry as Dictionary).duplicate(true))
	var main: Array = []
	var scatter: Array = []
	for entry in _Catalog.prop_chooser_entries():
		var e: Dictionary = (entry as Dictionary).duplicate(true)
		var roles: Array = e.get("roles", []) as Array
		if "centerpiece" in roles:
			main.append(e.duplicate(true))
		if "scatter" in roles:
			scatter.append(e.duplicate(true))
	var light: Array = []
	for entry in _Catalog.lighting_chooser_entries():
		light.append((entry as Dictionary).duplicate(true))
	return {"env": env, "main": main, "scatter": scatter, "light": light}


static func _add_entry_list_paths(paths: Array, seen: Dictionary, entries: Array, role: String) -> void:
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var cfg: Dictionary = _Catalog.layer_config_from_entry(entry as Dictionary, role)
		_add_layer_paths(paths, seen, cfg)


static func _add_active_session_stage_paths(paths: Array, seen: Dictionary) -> void:
	var data := _SessionStore.load_session()
	if data.is_empty():
		return
	var items: Variant = data.get("items", [])
	if not (items is Array) or (items as Array).is_empty():
		return
	var idx := clampi(int(data.get("current_index", 0)), 0, (items as Array).size() - 1)
	var item: Variant = (items as Array)[idx]
	if not (item is Dictionary):
		return
	var d: Dictionary = item
	_add_path(paths, seen, str(d.get("path", "")))
	var params: Variant = d.get("params", {})
	if not (params is Dictionary):
		return
	var p: Dictionary = params
	for layer_key in ["environment", "scatter", "centerpiece", "lighting"]:
		var layer: Variant = p.get(layer_key, {})
		if layer is Dictionary:
			_add_layer_paths(paths, seen, layer as Dictionary)


static func _add_layer_paths(paths: Array, seen: Dictionary, cfg: Dictionary) -> void:
	_add_path(paths, seen, str(cfg.get("path", "")))
	_add_path(paths, seen, str(cfg.get("hdri_path", "")))
	var source := str(cfg.get("source", "")).strip_edges()
	if not source.is_empty() and not source.begins_with("primitive:"):
		_add_path(paths, seen, source)


static func _add_path(paths: Array, seen: Dictionary, path: String) -> void:
	var key := path.replace("\\", "/").strip_edges()
	if key.is_empty() or key.begins_with("primitive:"):
		return
	if seen.has(key):
		return
	var exists := ResourceLoader.exists(key) or FileAccess.file_exists(key)
	if not exists and (key.begins_with("res://") or key.begins_with("user://")):
		var abs := ProjectSettings.globalize_path(key)
		exists = FileAccess.file_exists(abs)
	if not exists and not key.begins_with("res://") and not key.begins_with("user://"):
		exists = FileAccess.file_exists(key)
	if not exists:
		return
	seen[key] = true
	paths.append(key)


static func path_is_warmed(path: String) -> bool:
	var s := path.strip_edges()
	if s.is_empty() or s.begins_with("primitive:"):
		return true
	var t := _MediaImport.detect_type(s)
	match t:
		"gif":
			return _MediaImport.gif_cached(s)
		"image":
			return _MediaImport.texture_cached(s) or _AssetCache.has_texture(s)
		"hdri":
			return _AssetCache.has_texture(s)
		"scene3d":
			return _AssetCache.has_scene(s)
		"video":
			# Convert may continue in background; do not block boot on ffmpeg.
			return true
		_:
			var lower := s.to_lower()
			if lower.ends_with(".hdr") or lower.ends_with(".exr"):
				return _AssetCache.has_texture(s)
			if lower.ends_with(".glb") or lower.ends_with(".gltf") \
					or lower.ends_with(".fbx") or lower.ends_with(".tscn"):
				return _AssetCache.has_scene(s)
			return true
