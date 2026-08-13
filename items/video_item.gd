extends Control
class_name VideoItem

const RH = preload("res://core/reactivity_hub.gd")

var item_id: String = ""
var item_loop: bool = false
var _player: VideoStreamPlayer
var _fallback: TextureRect
var _alpha: float = 1.0
var _pending_path: String = ""


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	_fallback = TextureRect.new()
	_fallback.set_anchors_preset(PRESET_FULL_RECT)
	_fallback.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fallback.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_fallback.visible = false
	_fallback.modulate = Color(0.42, 0.08, 0.1, 1.0)
	add_child(_fallback)
	_player = VideoStreamPlayer.new()
	_player.set_anchors_preset(PRESET_FULL_RECT)
	_player.expand = true
	_player.finished.connect(_on_finished)
	add_child(_player)
	if not _pending_path.is_empty():
		_apply_path(_pending_path)


func configure(item: PlaylistItem) -> void:
	item_id = item.id
	item_loop = item.loop
	_pending_path = item.path
	if _player:
		_apply_path(item.path)


func _apply_path(path: String) -> void:
	if path.is_empty():
		return
	_fallback.visible = false
	_player.visible = true
	var stream := MediaImport.load_video_stream(path)
	if stream != null:
		_player.stream = stream
		return
	# GIF / failed video → still or animated texture fallback (never blank white).
	var tex: Texture2D = null
	if path.get_extension().to_lower() == "gif":
		tex = MediaImport.load_gif_texture(path)
	else:
		tex = MediaImport.load_texture(path)
	if tex != null:
		_player.stream = null
		_player.visible = false
		_fallback.texture = tex
		_fallback.modulate = Color.WHITE
		_fallback.visible = true
		return
	push_warning("VideoItem: missing or unplayable file %s" % path)
	_player.stream = null
	_player.visible = false
	_fallback.texture = null
	_fallback.modulate = Color(0.42, 0.08, 0.1, 1.0)
	_fallback.visible = true


func set_layer_alpha(alpha: float) -> void:
	_alpha = alpha
	modulate.a = alpha


func apply_audio_state(state: AudioState) -> void:
	if not RH.enabled() or not RH.applies_to("foreground"):
		scale = Vector2.ONE
		return
	if RH.affect_scale():
		var amt := RH.scale_multiplier()
		var sx := amt if RH.scale_x() else 1.0
		var sy := amt if RH.scale_y() else 1.0
		scale = Vector2(sx, sy)
	if RH.affect_emission():
		var g := 1.0 + state.mids * 0.35
		modulate = Color(g, g, g, _alpha)


func start_item() -> void:
	visible = true
	modulate.a = _alpha
	if _player and _player.stream:
		_player.play()


func stop_item() -> void:
	visible = false
	if _player:
		_player.stop()


func _on_finished() -> void:
	if item_loop and _player.stream:
		_player.play()
