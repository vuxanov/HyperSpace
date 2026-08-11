class_name MediaImport
extends RefCounted

## Detect media type from path and prepare GIFs/videos for Godot playback.

const _GifDecoder = preload("res://core/gif_decoder.gd")
const _AssetCache := preload("res://core/asset_cache.gd")

## Soft caps for runtime GIF memory / upload cost on 3D screens.
const MAX_GIF_DIM := 512
const MAX_GIF_FRAMES := 90
const MAX_STILL_DIM := 2048

## absolute_path -> { ok, frames: Array[ImageTexture], durations, width, height }
static var _gif_cache: Dictionary = {}
## absolute_path -> Texture2D (stills)
static var _tex_cache: Dictionary = {}
## Cached ffmpeg executable path ("" = missing, "__unset__" = not probed).
static var _ffmpeg_cached: String = "__unset__"
## Paths currently converting to ogv in a background process.
static var _converting: Dictionary = {}


static func clear_gif_cache() -> void:
	_gif_cache.clear()
	_tex_cache.clear()


static func prefetch_gif(path: String) -> void:
	## Decode off the apply hot-path when possible (still main-thread, but early).
	var key := absolute_path(path)
	if _gif_cache.has(key):
		return
	# Defer so Play step / layer apply returns first.
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.create_timer(0.05).timeout.connect(func() -> void:
			if not _gif_cache.has(key):
				load_gif_animation(path)
		)
	else:
		load_gif_animation(path)


static func warm_path(path: String) -> void:
	## Eager cache for playlist warm — decode GIF / texture / queue video / scene now.
	var resolved := to_project_or_absolute(path)
	if resolved.is_empty() or resolved.begins_with("primitive:"):
		return
	var media_type := detect_type(resolved)
	match media_type:
		"gif":
			load_gif_animation(resolved)
		"image":
			load_texture(resolved)
		"hdri":
			_AssetCache.request_texture(resolved)
		"video":
			prepare_path(resolved, "video")
			var ogv := _ogv_if_cached(resolved)
			if not ogv.is_empty():
				load_video_stream(ogv)
			else:
				# Kick convert; stream loads later from cache when ready.
				pass
		"scene3d":
			_AssetCache.request_scene(resolved)
		_:
			var lower := resolved.to_lower()
			if lower.ends_with(".hdr") or lower.ends_with(".exr"):
				_AssetCache.request_texture(resolved)


static func warm_paths_sync_media(paths: Array, max_items: int = 1) -> int:
	## Process up to max_items GIF/image warm steps this frame. Returns remaining media paths needing work.
	var remaining := 0
	var done := 0
	for p in paths:
		var s := str(p).strip_edges()
		if s.is_empty() or s.begins_with("primitive:"):
			continue
		var t := detect_type(s)
		if t == "gif":
			if gif_cached(s):
				continue
			if done < max_items:
				load_gif_animation(s)
				done += 1
			else:
				remaining += 1
		elif t == "image":
			if texture_cached(s):
				continue
			if done < max_items:
				load_texture(s)
				done += 1
			else:
				remaining += 1
		elif t == "video":
			prepare_path(s, "video")
	return remaining


static func gif_cached(path: String) -> bool:
	return _gif_cache.has(absolute_path(path))


static func texture_cached(path: String) -> bool:
	var key := absolute_path(path)
	return _tex_cache.has(key) or _AssetCache.has_texture(path)


static func detect_type(path: String) -> String:
	var ext := path.get_extension().to_lower()
	match ext:
		"glb", "gltf", "fbx", "tscn":
			return "scene3d"
		"webm", "mp4", "ogv", "avi", "mov":
			return "video"
		"gif":
			return "gif"
		"png", "jpg", "jpeg", "svg", "webp", "bmp", "tga":
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
	return normalized


static func absolute_path(path: String) -> String:
	var resolved := to_project_or_absolute(path)
	if resolved.begins_with("res://") or resolved.begins_with("user://"):
		return ProjectSettings.globalize_path(resolved).replace("\\", "/")
	return resolved.replace("\\", "/")


static func prepare_path(path: String, media_type: String) -> String:
	## Return a path Godot can play. Uses cached ogv when present; never blocks on ffmpeg.
	## GIFs stay as .gif — decoded natively (GifDecoder) or via VideoItem fallback.
	var resolved := to_project_or_absolute(path)
	var ext := resolved.get_extension().to_lower()
	if media_type == "video" and ext != "ogv":
		var converted := _ogv_if_cached(path)
		if not converted.is_empty():
			return converted
		_queue_convert_to_ogv(path)
	return resolved


static func prepare_path_blocking(path: String, media_type: String) -> String:
	## Explicit sync convert (import tools only — avoid during live Play).
	var resolved := to_project_or_absolute(path)
	var ext := resolved.get_extension().to_lower()
	if media_type == "video" and ext != "ogv":
		var converted := _convert_to_ogv(path)
		if not converted.is_empty():
			return converted
	return resolved


static func load_texture(path: String) -> Texture2D:
	## Prefer runtime Image→ImageTexture so external uploads always sample as LDR RGBA.
	var cache_key := absolute_path(path)
	if _tex_cache.has(cache_key):
		return _tex_cache[cache_key] as Texture2D
	var cached_asset := _AssetCache.get_texture(path)
	if cached_asset != null:
		_tex_cache[cache_key] = cached_asset
		return cached_asset
	var abs_path := cache_key
	if FileAccess.file_exists(abs_path):
		var img: Image = Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			var tex := _image_to_texture(img)
			_tex_cache[cache_key] = tex
			_AssetCache.put_texture(path, tex)
			return tex
	var resolved := to_project_or_absolute(path)
	if ResourceLoader.exists(resolved):
		var res: Resource = ResourceLoader.load(resolved)
		if res is Texture2D:
			var src := res as Texture2D
			var img2: Image = src.get_image() if src.has_method("get_image") else null
			if img2 != null and not img2.is_empty():
				var tex2 := _image_to_texture(img2)
				_tex_cache[cache_key] = tex2
				_AssetCache.put_texture(path, tex2)
				return tex2
			_tex_cache[cache_key] = src
			_AssetCache.put_texture(path, src)
			return src
	if FileAccess.file_exists(abs_path):
		var f := FileAccess.open(abs_path, FileAccess.READ)
		if f:
			var buf := f.get_buffer(f.get_length())
			f.close()
			var img3 := Image.new()
			var err := img3.load_png_from_buffer(buf)
			if err != OK:
				err = img3.load_jpg_from_buffer(buf)
			if err != OK:
				err = img3.load_webp_from_buffer(buf)
			if err == OK and not img3.is_empty():
				var tex3 := _image_to_texture(img3)
				_tex_cache[cache_key] = tex3
				return tex3
	# GIF still-frame fallback via native decoder.
	if abs_path.get_extension().to_lower() == "gif":
		var gif := load_gif_animation(path)
		if bool(gif.get("ok", false)):
			var frames: Array = gif.get("frames", [])
			if not frames.is_empty() and frames[0] is ImageTexture:
				var gf := frames[0] as ImageTexture
				_tex_cache[cache_key] = gf
				return gf
	push_warning("MediaImport.load_texture: failed for %s" % path)
	return null


static func load_gif_animation(path: String) -> Dictionary:
	## { ok, frames: Array[ImageTexture], durations: Array[float], width, height }
	## Cached + downscaled so scatter clones / rebinds share the same GPU textures.
	var cache_key := absolute_path(path)
	if _gif_cache.has(cache_key):
		return _gif_cache[cache_key]
	var decoded := _GifDecoder.decode_path(cache_key)
	var tex_frames: Array[ImageTexture] = []
	var tex_durs: Array[float] = []
	if bool(decoded.get("ok", false)):
		var imgs: Array = decoded.get("frames", [])
		var durs: Array = decoded.get("durations", [])
		_subsample_frames(imgs, durs, MAX_GIF_FRAMES)
		for i in imgs.size():
			if imgs[i] is Image:
				var im := imgs[i] as Image
				_downscale_image(im, MAX_GIF_DIM)
				tex_frames.append(_image_to_texture(im))
				tex_durs.append(maxf(float(durs[i]) if i < durs.size() else 0.08, 0.04))
	else:
		# ffmpeg explode as secondary path.
		var anim := _gif_to_animated_texture(path)
		if anim is AnimatedTexture:
			var at := anim as AnimatedTexture
			for fi in at.frames:
				var ft := at.get_frame_texture(fi)
				if ft is ImageTexture:
					var it := ft as ImageTexture
					var im2: Image = it.get_image() if it.has_method("get_image") else null
					if im2 != null and not im2.is_empty():
						_downscale_image(im2, MAX_GIF_DIM)
						tex_frames.append(_image_to_texture(im2))
					else:
						tex_frames.append(it)
				elif ft != null:
					var im3: Image = ft.get_image() if ft.has_method("get_image") else null
					if im3 != null and not im3.is_empty():
						_downscale_image(im3, MAX_GIF_DIM)
						tex_frames.append(_image_to_texture(im3))
				tex_durs.append(maxf(at.get_frame_duration(fi), 0.04))
			_subsample_texture_frames(tex_frames, tex_durs, MAX_GIF_FRAMES)
		elif anim is ImageTexture:
			tex_frames.append(anim as ImageTexture)
			tex_durs.append(0.08)
	if tex_frames.is_empty():
		var empty := {"ok": false, "frames": [], "durations": [], "width": 0, "height": 0}
		return empty
	var result := {
		"ok": true,
		"frames": tex_frames,
		"durations": tex_durs,
		"width": tex_frames[0].get_width(),
		"height": tex_frames[0].get_height(),
	}
	_gif_cache[cache_key] = result
	return result


static func _downscale_image(img: Image, max_dim: int) -> void:
	if img == null or img.is_empty() or max_dim <= 0:
		return
	var w := img.get_width()
	var h := img.get_height()
	var m := maxi(w, h)
	if m <= max_dim:
		return
	var sc := float(max_dim) / float(m)
	img.resize(maxi(1, int(w * sc)), maxi(1, int(h * sc)), Image.INTERPOLATE_BILINEAR)


static func _subsample_frames(imgs: Array, durs: Array, max_frames: int) -> void:
	if imgs.size() <= max_frames:
		return
	var step := int(ceili(float(imgs.size()) / float(max_frames)))
	step = maxi(step, 2)
	var new_imgs: Array = []
	var new_durs: Array = []
	var i := 0
	while i < imgs.size():
		new_imgs.append(imgs[i])
		var acc := 0.0
		for j in step:
			if i + j < durs.size():
				acc += float(durs[i + j])
			elif i < durs.size():
				acc += float(durs[i])
			else:
				acc += 0.08
		new_durs.append(maxf(acc, 0.04))
		i += step
	imgs.clear()
	durs.clear()
	for k in new_imgs.size():
		imgs.append(new_imgs[k])
		durs.append(new_durs[k])


static func _subsample_texture_frames(frames: Array, durs: Array, max_frames: int) -> void:
	if frames.size() <= max_frames:
		return
	var step := int(ceili(float(frames.size()) / float(max_frames)))
	step = maxi(step, 2)
	var nf: Array = []
	var nd: Array = []
	var i := 0
	while i < frames.size():
		nf.append(frames[i])
		var acc := 0.0
		for j in step:
			if i + j < durs.size():
				acc += float(durs[i + j])
			else:
				acc += 0.08
		nd.append(maxf(acc, 0.04))
		i += step
	frames.clear()
	durs.clear()
	for k in nf.size():
		frames.append(nf[k])
		durs.append(nd[k])


static func load_gif_texture(path: String) -> Texture2D:
	## Prefer multi-frame animation data; returns first frame Texture2D for simple callers.
	## Prefer AnimatedTexture only for Control nodes — 3D shaders need manual frame cycling.
	var anim := load_gif_animation(path)
	if not bool(anim.get("ok", false)):
		return null
	var frames: Array = anim.get("frames", [])
	if frames.is_empty():
		return null
	if frames.size() == 1:
		return frames[0] as Texture2D
	var at := AnimatedTexture.new()
	at.frames = frames.size()
	var durs: Array = anim.get("durations", [])
	for fi in frames.size():
		at.set_frame_texture(fi, frames[fi])
		at.set_frame_duration(fi, float(durs[fi]) if fi < durs.size() else 0.08)
	at.one_shot = false
	at.pause = false
	return at


static func _image_to_texture(img: Image) -> ImageTexture:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_downscale_image(img, MAX_STILL_DIM)
	return ImageTexture.create_from_image(img)


static func load_video_stream(path: String) -> VideoStream:
	var resolved := to_project_or_absolute(path)
	if ResourceLoader.exists(resolved):
		var res: Resource = load(resolved)
		if res is VideoStream:
			return res as VideoStream
	var abs_path := absolute_path(resolved)
	if not FileAccess.file_exists(abs_path):
		# user:// converted paths
		if resolved.begins_with("user://") and FileAccess.file_exists(resolved):
			abs_path = ProjectSettings.globalize_path(resolved)
		else:
			return null
	var ext := abs_path.get_extension().to_lower()
	# Godot core VideoStreamPlayer supports Theora (.ogv). Prefer that.
	if ext == "ogv":
		var theora := VideoStreamTheora.new()
		theora.file = abs_path
		return theora
	if ResourceLoader.exists(abs_path):
		var res2: Resource = load(abs_path)
		if res2 is VideoStream:
			return res2 as VideoStream
	return null


static func _cache_key(src_path: String) -> String:
	var abs_p := absolute_path(src_path)
	return abs_p.md5_text().substr(0, 16)


static func _ogv_if_cached(src_path: String) -> String:
	var out_dir := "user://converted_media"
	var key := _cache_key(src_path)
	var out_res := out_dir.path_join(key + ".ogv")
	var out_abs := ProjectSettings.globalize_path(out_res)
	if FileAccess.file_exists(out_res) or FileAccess.file_exists(out_abs):
		return out_res
	return ""


static func _queue_convert_to_ogv(src_path: String) -> void:
	## Fire-and-forget ffmpeg so Play/apply never blocks on OS.execute.
	var key := _cache_key(src_path)
	if _converting.has(key):
		return
	if not _ogv_if_cached(src_path).is_empty():
		return
	var ffmpeg := _find_ffmpeg()
	if ffmpeg.is_empty():
		return
	var out_dir := "user://converted_media"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var out_res := out_dir.path_join(key + ".ogv")
	var out_abs := ProjectSettings.globalize_path(out_res)
	var in_abs := absolute_path(src_path)
	if not FileAccess.file_exists(in_abs):
		return
	_converting[key] = true
	var args := PackedStringArray([
		"-y", "-i", in_abs,
		"-c:v", "libtheora", "-q:v", "7",
		"-an",
		"-pix_fmt", "yuv420p",
		out_abs,
	])
	OS.create_process(ffmpeg, args)


static func _convert_to_ogv(src_path: String) -> String:
	var cached := _ogv_if_cached(src_path)
	if not cached.is_empty():
		return cached
	var ffmpeg := _find_ffmpeg()
	if ffmpeg.is_empty():
		push_warning("MediaImport: ffmpeg not found — animated GIF/video may use native GIF decode or fail. Place ffmpeg at tools/ffmpeg/ffmpeg.exe.")
		return ""
	var out_dir := "user://converted_media"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var key := _cache_key(src_path)
	var out_res := out_dir.path_join(key + ".ogv")
	var out_abs := ProjectSettings.globalize_path(out_res)
	var in_abs := absolute_path(src_path)
	if not FileAccess.file_exists(in_abs):
		return ""
	# Theora + Vorbis in Ogg — widely playable by VideoStreamTheora.
	var args := PackedStringArray([
		"-y", "-i", in_abs,
		"-c:v", "libtheora", "-q:v", "7",
		"-an",
		"-pix_fmt", "yuv420p",
		out_abs,
	])
	var output: Array = []
	var exit_code := OS.execute(ffmpeg, args, output, true, false)
	if exit_code != 0 or not FileAccess.file_exists(out_abs):
		# Retry with audio (some builds prefer it).
		args = PackedStringArray([
			"-y", "-i", in_abs,
			"-c:v", "libtheora", "-q:v", "7",
			"-c:a", "libvorbis", "-q:a", "4",
			"-pix_fmt", "yuv420p",
			out_abs,
		])
		output = []
		exit_code = OS.execute(ffmpeg, args, output, true, false)
	if exit_code != 0 or not FileAccess.file_exists(out_abs):
		push_warning("MediaImport: conversion to ogv failed for %s" % src_path)
		return ""
	return out_res


static func _gif_to_animated_texture(gif_path: String) -> Texture2D:
	## Explode GIF to PNG frames via ffmpeg, then build AnimatedTexture.
	var ffmpeg := _find_ffmpeg()
	if ffmpeg.is_empty():
		return null
	var abs_gif := absolute_path(gif_path)
	if not FileAccess.file_exists(abs_gif):
		return null
	var key := _cache_key(gif_path)
	var frame_dir := "user://converted_gif_frames/%s" % key
	var frame_abs := ProjectSettings.globalize_path(frame_dir)
	DirAccess.make_dir_recursive_absolute(frame_abs)
	var pattern := frame_abs.path_join("f_%04d.png")
	var existing := DirAccess.open(frame_dir)
	var has_frames := false
	if existing:
		existing.list_dir_begin()
		var n := existing.get_next()
		while n != "":
			if n.begins_with("f_") and n.ends_with(".png"):
				has_frames = true
				break
			n = existing.get_next()
		existing.list_dir_end()
	if not has_frames:
		var args := PackedStringArray([
			"-y", "-i", abs_gif,
			"-vsync", "0",
			pattern.replace("\\", "/"),
		])
		var output: Array = []
		var code := OS.execute(ffmpeg, args, output, true, false)
		if code != 0:
			return null
	var frames: Array[ImageTexture] = []
	var durations: Array[float] = []
	var i := 1
	while i <= 120:
		var fp := frame_dir.path_join("f_%04d.png" % i)
		var fp_abs := ProjectSettings.globalize_path(fp)
		if not FileAccess.file_exists(fp) and not FileAccess.file_exists(fp_abs):
			break
		var img := Image.load_from_file(fp_abs if FileAccess.file_exists(fp_abs) else ProjectSettings.globalize_path(fp))
		if img == null or img.is_empty():
			break
		frames.append(_image_to_texture(img))
		durations.append(0.08)
		i += 1
	if frames.is_empty():
		return null
	if frames.size() == 1:
		return frames[0]
	var anim := AnimatedTexture.new()
	anim.frames = frames.size()
	for fi in frames.size():
		anim.set_frame_texture(fi, frames[fi])
		anim.set_frame_duration(fi, durations[fi])
	anim.one_shot = false
	anim.pause = false
	return anim


static func _convert_gif_to_webm(gif_path: String) -> String:
	## Kept for callers that still expect webm; prefer _convert_to_ogv.
	var ffmpeg := _find_ffmpeg()
	if ffmpeg.is_empty():
		push_warning("MediaImport: ffmpeg not found — GIF may play as a still frame. Install ffmpeg for animated GIFs.")
		return ""
	var out_dir := "user://converted_gifs"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var out_name := _cache_key(gif_path) + ".webm"
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
	if _ffmpeg_cached != "__unset__":
		return _ffmpeg_cached
	# Prefer local tools path before PATH probe (PATH probe is a sync OS.execute hitch).
	var candidates: Array[String] = [
		ProjectSettings.globalize_path("res://tools/ffmpeg/ffmpeg.exe"),
		ProjectSettings.globalize_path("res://tools/ffmpeg/ffmpeg"),
		OS.get_executable_path().get_base_dir().path_join("ffmpeg.exe"),
		OS.get_executable_path().get_base_dir().path_join("tools/ffmpeg/ffmpeg.exe"),
	]
	# Common Windows install locations.
	var home := OS.get_environment("USERPROFILE")
	var local := OS.get_environment("LOCALAPPDATA")
	var pf := OS.get_environment("ProgramFiles")
	if not home.is_empty():
		candidates.append(home.path_join("scoop/shims/ffmpeg.exe"))
		candidates.append(home.path_join("ffmpeg/bin/ffmpeg.exe"))
	if not local.is_empty():
		candidates.append(local.path_join("Microsoft/WinGet/Links/ffmpeg.exe"))
	if not pf.is_empty():
		candidates.append(pf.path_join("ffmpeg/bin/ffmpeg.exe"))
	candidates.append("C:/ffmpeg/bin/ffmpeg.exe")
	for c in candidates:
		var p := c.replace("\\", "/")
		if FileAccess.file_exists(p):
			_ffmpeg_cached = p
			return p
	# Last resort: PATH (one-time cost, then cached).
	if OS.execute("ffmpeg", PackedStringArray(["-version"]), [], true, false) == 0:
		_ffmpeg_cached = "ffmpeg"
		return "ffmpeg"
	_ffmpeg_cached = ""
	return ""


static func build_item_dict(path: String, default_duration: float = 8.0) -> Dictionary:
	var media_type := detect_type(path)
	if media_type.is_empty() or media_type == "hdri":
		return {}
	var prepared := prepare_path(path, media_type)
	var play_type := media_type
	if media_type == "gif":
		var ext := prepared.get_extension().to_lower()
		# Native GIF stays type image for still playlists; video only if converted to ogv.
		play_type = "video" if ext in ["ogv", "webm", "mp4"] else "gif"
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
