extends Control
class_name VideoItem

const RH = preload("res://core/reactivity_hub.gd")

var item_id: String = ""
var item_loop: bool = false
var _player: VideoStreamPlayer
var _alpha: float = 1.0
var _pending_path: String = ""


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
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
	if ResourceLoader.exists(path):
		_player.stream = load(path)
	elif FileAccess.file_exists(path):
		_player.stream = load(path)
	else:
		push_warning("VideoItem: missing file %s" % path)


func set_layer_alpha(alpha: float) -> void:
	_alpha = alpha
	modulate.a = alpha


func apply_audio_state(state: AudioState) -> void:
	if not RH.enabled() or not RH.applies_to("foreground"):
		scale = Vector2.ONE
		return
	if RH.affect_scale():
		var reactive := state.bass * 1.2 + state.energy
		if state.beat:
			reactive *= 1.3
		var amt := 1.0 + reactive * RH.scale_amount() * 0.12
		var sx := amt if RH.scale_x() else 1.0
		var sy := amt if RH.scale_y() else 1.0
		scale = Vector2(sx, sy)
	if RH.affect_emission():
		var g := 1.0 + state.mids * 0.6
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
