extends Control
class_name ImageItem

## Image / GIF still frame — reacts to audio and can break into particles.

const RH = preload("res://core/reactivity_hub.gd")

var item_id: String = ""
var item_loop: bool = false
var _texture_rect: TextureRect
var _particles: GPUParticles2D
var _alpha: float = 1.0
var _pending_path: String = ""
var _particles_mode: bool = false
var _base_scale := Vector2.ONE


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	_texture_rect = TextureRect.new()
	_texture_rect.set_anchors_preset(PRESET_FULL_RECT)
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_texture_rect)
	_particles = GPUParticles2D.new()
	_particles.emitting = false
	_particles.amount = 280
	_particles.lifetime = 1.4
	_particles.explosiveness = 0.25
	_particles.position = Vector2(960, 540)
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(700, 400, 0)
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 40.0
	mat.initial_velocity_max = 220.0
	mat.gravity = Vector3(0, 80, 0)
	mat.scale_min = 2.0
	mat.scale_max = 8.0
	mat.color = Color(1, 1, 1, 0.85)
	_particles.process_material = mat
	add_child(_particles)
	if not _pending_path.is_empty():
		_apply_path(_pending_path)


func configure(item: PlaylistItem) -> void:
	item_id = item.id
	item_loop = item.loop
	_pending_path = item.path
	if _texture_rect:
		_apply_path(item.path)


func _apply_path(path: String) -> void:
	if path.is_empty():
		return
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null:
			tex = ImageTexture.create_from_image(image)
	if tex == null:
		push_warning("ImageItem: missing file %s" % path)
		return
	_texture_rect.texture = tex
	if _particles:
		_particles.texture = tex


func set_layer_alpha(alpha: float) -> void:
	_alpha = alpha
	modulate.a = alpha


func apply_audio_state(state: AudioState) -> void:
	_sync_particles()
	if not RH.enabled():
		scale = _base_scale
		modulate = Color(1, 1, 1, _alpha)
		return
	if RH.affect_scale() and RH.applies_to("foreground"):
		var reactive := state.bass * 1.5 + state.energy
		if state.beat:
			reactive *= 1.4
		var amt := 1.0 + reactive * RH.scale_amount() * 0.15
		var sx := amt if RH.scale_x() else 1.0
		var sy := amt if RH.scale_y() else 1.0
		scale = Vector2(sx, sy)
	if RH.affect_emission():
		var glow := 1.0 + state.mids * 0.8
		modulate = Color(glow, glow, glow, _alpha)
	if _particles_mode and _particles:
		_particles.emitting = true
		_particles.amount = clampi(int(100 + state.bass * 400), 80, 800)
		if _particles.process_material is ParticleProcessMaterial:
			var mat: ParticleProcessMaterial = _particles.process_material
			mat.initial_velocity_max = 80.0 + state.energy * 400.0
		if state.beat:
			_particles.restart()


func _sync_particles() -> void:
	var want := ShowDirector.get_effect_enabled("particles")
	if want == _particles_mode:
		return
	_particles_mode = want
	if _texture_rect:
		# Keep image visible faintly so ASCII/feedback still have something to sample,
		# but emphasize particles when active.
		_texture_rect.modulate.a = 0.25 if _particles_mode else 1.0
	if _particles:
		_particles.emitting = _particles_mode
		_particles.visible = _particles_mode


func start_item() -> void:
	visible = true
	modulate.a = _alpha
	_sync_particles()


func stop_item() -> void:
	visible = false
	if _particles:
		_particles.emitting = false
