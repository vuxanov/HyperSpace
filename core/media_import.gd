class_name MediaImport
extends RefCounted

## Detect media type from path and prepare GIFs/videos for Godot playback.


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
		"hdr", "exr":
			return "hdri"
		_:
			return ""


static func is_media_extension(path: String) -> bool:
	var t := detect_type(path)
	return t in ["image", "gif", "video"]


static func is_model_extension(path: String) -> bool:
	return detect_type(path) == "scene3d"


static func to_project_or_absolute(path: String) -> String:
	var project_root := ProjectSettings.globalize_path("res://").replace("\\", "/")
	var normalized := path.replace("\\", "/")
	if normalized.begins_with(project_root):
		return "res://" + normalized.substr(project_root.length()).lstrip("/")
	return path


static func absolute_path(path: String) -> String:
	var resolved := to_project_or_absolute(path)
	if resolved.begins_with("res://") or resolved.begins_with("user://"):
		return ProjectSettings.globalize_path(resolved)
	return resolved.replace("\\", "/")


static func prepare_path(path: String, media_type: String) -> String:
	## Return a path Godot can play. GIFs / non-ogv videos convert to ogv via ffmpeg when available.
	var resolved := to_project_or_absolute(path)
	var ext := resolved.get_extension().to_lower()
	if media_type == "gif" or (media_type == "video" and ext != "ogv"):
		var converted := _convert_to_ogv(path)
		if not converted.is_empty():
			return converted
	return resolved


static func load_texture(path: String) -> Texture2D:
	var resolved := to_project_or_absolute(path)
	if ResourceLoader.exists(resolved):
		var res: Resource = load(resolved)
		if res is Texture2D:
			return res as Texture2D
	var abs_path := absolute_path(resolved)
	if not FileAccess.file_exists(abs_path):
		return null
	var img: Image = Image.load_from_file(abs_path)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


static func load_video_stream(path: String) -> VideoStream:
	var resolved := to_project_or_absolute(path)
	if ResourceLoader.exists(resolved):
		var res: Resource = load(resolved)
		if res is VideoStream:
			return res as VideoStream
	var abs_path := absolute_path(resolved)
	if not FileAccess.file_exists(abs_path):
		return null
	var ext := abs_path.get_extension().to_lower()
	# Godot core VideoStreamPlayer supports Theora (.ogv). Prefer that.
	if ext == "ogv":
		var theora := VideoStreamTheora.new()
		theora.file = abs_path
		return theora
	# Last resort: try ResourceLoader on absolute (usually fails for external files).
	if ResourceLoader.exists(abs_path):
		var res2: Resource = load(abs_path)
		if res2 is VideoStream:
			return res2 as VideoStream
	return null


static func _convert_to_ogv(src_path: String) -> String:
	var ffmpeg := _find_ffmpeg()
	if ffmpeg.is_empty():
		push_warning("MediaImport: ffmpeg not found — animated GIF/video may be a still or unsupported. Install ffmpeg for playback.")
		return ""
	var out_dir := "user://converted_media"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var base := src_path.get_file().get_basename()
	var out_res := out_dir.path_join(base + ".ogv")
	var out_abs := ProjectSettings.globalize_path(out_res)
	if FileAccess.file_exists(out_res) or FileAccess.file_exists(out_abs):
		return out_res
	var in_abs := absolute_path(src_path)
	if not FileAccess.file_exists(in_abs):
		return ""
	# Theora + Vorbis in Ogg — widely playable by VideoStreamTheora.
	var args := PackedStringArray([
		"-y", "-i", in_abs,
		"-c:v", "libtheora", "-q:v", "7",
		"-c:a", "libvorbis", "-q:a", "4",
		"-pix_fmt", "yuv420p",
		out_abs,
	])
	var output: Array = []
	var exit_code := OS.execute(ffmpeg, args, output, true, false)
	if exit_code != 0 or not FileAccess.file_exists(out_abs):
		push_warning("MediaImport: conversion to ogv failed for %s" % src_path)
		return ""
	return out_res


static func _convert_gif_to_webm(gif_path: String) -> String:
	## Kept for callers that still expect webm; prefer _convert_to_ogv.
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
		"-y", "-i", absolute_path(gif_path),
		"-c:v", "libvpx-vp9", "-pix_fmt", "yuva420p", "-auto-alt-ref", "0",
		out_abs,
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
	if media_type.is_empty() or media_type == "hdri":
		return {}
	var prepared := prepare_path(path, media_type)
	var play_type := media_type
	if media_type == "gif":
		var ext := prepared.get_extension().to_lower()
		play_type = "video" if ext in ["ogv", "webm", "mp4"] else "image"
	elif media_type == "scene3d":
		play_type = "scene3d"
	return {
		"id": path.get_file().get_basename(),
		"type": play_type,
		"path": prepared,
		"loop": play_type == "video",
		"duration": default_duration,
		"params": {"source_type": media_type},
	}
