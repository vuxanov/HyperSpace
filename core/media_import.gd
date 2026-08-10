class_name MediaImport
extends RefCounted

## Detect media type from path and prepare GIFs (ffmpeg → webm when available).


static func detect_type(path: String) -> String:
	var ext := path.get_extension().to_lower()
	match ext:
		"glb", "gltf", "fbx", "tscn":
			return "scene3d"
		"webm", "mp4", "ogv", "avi", "mov":
			return "video"
		"gif":
			return "gif"
		"png", "jpg", "jpeg", "svg", "webp", "bmp":
			return "image"
		_:
			return ""


static func to_project_or_absolute(path: String) -> String:
	var project_root := ProjectSettings.globalize_path("res://").replace("\\", "/")
	var normalized := path.replace("\\", "/")
	if normalized.begins_with(project_root):
		return "res://" + normalized.substr(project_root.length()).lstrip("/")
	return path


static func prepare_path(path: String, media_type: String) -> String:
	var resolved := to_project_or_absolute(path)
	if media_type != "gif":
		return resolved
	var converted := _convert_gif_to_webm(path)
	if not converted.is_empty():
		return converted
	# Fallback: still try original path as image/video source.
	return resolved


static func _convert_gif_to_webm(gif_path: String) -> String:
	var ffmpeg := _find_ffmpeg()
	if ffmpeg.is_empty():
		push_warning("MediaImport: ffmpeg not found — GIF may play as a still frame. Install ffmpeg for animated GIFs.")
		return ""
	var out_dir := "user://converted_gifs"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var out_name := gif_path.get_file().get_basename() + ".webm"
	var out_res := out_dir.path_join(out_name)
	var out_abs := ProjectSettings.globalize_path(out_res)
	if FileAccess.file_exists(out_res):
		return out_res
	var args := PackedStringArray([
		"-y", "-i", gif_path,
		"-c:v", "libvpx-vp9", "-pix_fmt", "yuva420p", "-auto-alt-ref", "0",
		out_abs
	])
	var output: Array = []
	var exit_code := OS.execute(ffmpeg, args, output, true, false)
	if exit_code != 0 or not FileAccess.file_exists(out_res):
		push_warning("MediaImport: GIF conversion failed for %s" % gif_path)
		return ""
	return out_res


static func _find_ffmpeg() -> String:
	if OS.execute("ffmpeg", PackedStringArray(["-version"]), [], true, false) == 0:
		return "ffmpeg"
	return ""


static func build_item_dict(path: String, default_duration: float = 8.0) -> Dictionary:
	var media_type := detect_type(path)
	if media_type.is_empty():
		return {}
	var prepared := prepare_path(path, media_type)
	var play_type := media_type
	if media_type == "gif":
		play_type = "video" if prepared.get_extension().to_lower() == "webm" else "image"
	return {
		"id": path.get_file().get_basename(),
		"type": play_type,
		"path": prepared,
		"loop": play_type == "video",
		"duration": default_duration,
		"params": {"source_type": media_type},
	}
