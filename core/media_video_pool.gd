class_name MediaVideoPool
extends RefCounted

## One shared decode SubViewport + ImageTexture per video path.
## Avoids N× get_image readbacks when multiple props play the same file.


const VIEW_SIZE := Vector2i(640, 360)
const PULL_HZ := 18.0
const FALLBACK_CHARCOAL := Color(0.08, 0.08, 0.1)

## path -> { viewport, player, frame_tex, refs, accum, aspect, last_sz }
static var _slots: Dictionary = {}
static var _last_tick_frame: int = -1


static func acquire(path: String, stream: VideoStream, loop: bool) -> Dictionary:
	## Returns { ok, frame_tex, aspect, key } or { ok: false }.
	if path.is_empty() or stream == null:
		return {"ok": false}
	var key := path.replace("\\", "/")
	if _slots.has(key):
		var existing: Dictionary = _slots[key]
		existing["refs"] = int(existing.get("refs", 0)) + 1
		var player: VideoStreamPlayer = existing.get("player") as VideoStreamPlayer
		if player != null and not player.is_playing():
			player.play()
		return {
			"ok": true,
			"frame_tex": existing.get("frame_tex"),
			"aspect": float(existing.get("aspect", 16.0 / 9.0)),
			"key": key,
		}
	var host := _video_host()
	if host == null:
		return {"ok": false}
	var viewport := SubViewport.new()
	viewport.name = "SharedVideo_%s" % key.get_file().get_basename()
	viewport.size = VIEW_SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	host.add_child(viewport)
	var bg := ColorRect.new()
	bg.color = FALLBACK_CHARCOAL
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(bg)
	var player2 := VideoStreamPlayer.new()
	player2.expand = true
	player2.set_anchors_preset(Control.PRESET_FULL_RECT)
	player2.size = Vector2(VIEW_SIZE)
	player2.autoplay = false
	player2.stream = stream
	player2.set_meta("loop", loop)
	player2.finished.connect(func() -> void:
		if bool(player2.get_meta("loop", true)) and player2.stream != null:
			player2.play()
	)
	viewport.add_child(player2)
	player2.play()
	var frame_tex := ImageTexture.new()
	var seed_img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	seed_img.fill(FALLBACK_CHARCOAL)
	frame_tex.set_image(seed_img)
	_slots[key] = {
		"viewport": viewport,
		"player": player2,
		"frame_tex": frame_tex,
		"refs": 1,
		"accum": 0.0,
		"aspect": 16.0 / 9.0,
		"last_sz": Vector2i(4, 4),
	}
	return {"ok": true, "frame_tex": frame_tex, "aspect": 16.0 / 9.0, "key": key}


static func release(path: String) -> void:
	var key := path.replace("\\", "/")
	if not _slots.has(key):
		return
	var slot: Dictionary = _slots[key]
	slot["refs"] = int(slot.get("refs", 1)) - 1
	if int(slot["refs"]) > 0:
		return
	var player: VideoStreamPlayer = slot.get("player") as VideoStreamPlayer
	if player != null:
		player.stop()
	var viewport: SubViewport = slot.get("viewport") as SubViewport
	if viewport != null and is_instance_valid(viewport):
		viewport.queue_free()
	_slots.erase(key)


static func tick(delta: float) -> void:
	## Pull frames for all live slots at capped Hz (one get_image per path per tick).
	if _slots.is_empty():
		return
	var frame := Engine.get_process_frames()
	if frame == _last_tick_frame:
		return
	_last_tick_frame = frame
	var interval := 1.0 / PULL_HZ
	for key in _slots.keys():
		var slot: Dictionary = _slots[key]
		slot["accum"] = float(slot.get("accum", 0.0)) + delta
		if float(slot["accum"]) < interval:
			continue
		slot["accum"] = 0.0
		_pull_slot(slot)


static func aspect_for(path: String) -> float:
	var key := path.replace("\\", "/")
	if _slots.has(key):
		return float(_slots[key].get("aspect", 16.0 / 9.0))
	return 16.0 / 9.0


static func _pull_slot(slot: Dictionary) -> void:
	var player: VideoStreamPlayer = slot.get("player") as VideoStreamPlayer
	var frame_tex: ImageTexture = slot.get("frame_tex") as ImageTexture
	var viewport: SubViewport = slot.get("viewport") as SubViewport
	if player == null or frame_tex == null:
		return
	var src: Texture2D = null
	if player.has_method("get_video_texture"):
		src = player.call("get_video_texture") as Texture2D
	if src == null and viewport != null:
		src = viewport.get_texture()
	if src == null:
		return
	var img: Image = src.get_image() if src.has_method("get_image") else null
	if img == null or img.is_empty():
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var max_dim := maxi(VIEW_SIZE.x, VIEW_SIZE.y)
	if img.get_width() > max_dim or img.get_height() > max_dim:
		var sc := float(max_dim) / float(maxi(img.get_width(), img.get_height()))
		img.resize(
			maxi(1, int(img.get_width() * sc)),
			maxi(1, int(img.get_height() * sc)),
			Image.INTERPOLATE_BILINEAR
		)
	var img_sz := img.get_size()
	var tex_sz: Vector2i = slot.get("last_sz", Vector2i(4, 4))
	if tex_sz != img_sz:
		frame_tex.set_image(img)
		slot["last_sz"] = img_sz
	else:
		frame_tex.update(img)
	if img_sz.y > 0:
		slot["aspect"] = float(img_sz.x) / float(img_sz.y)


static func _video_host() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var root := tree.root
	var holder := root.get_node_or_null("HyperSpaceMediaVideoHost")
	if holder == null:
		holder = Node.new()
		holder.name = "HyperSpaceMediaVideoHost"
		root.add_child(holder)
	return holder
