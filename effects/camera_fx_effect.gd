extends EffectLayer
class_name CameraFxEffect

## Animatable DOF / bokeh / focal-length / aperture + beyond-fisheye lens warp.

var _focal_length: float = 28.0
var _aperture: float = 2.8
var _focus_distance: float = 8.0
var _bokeh: float = 0.55
var _lens_distortion: float = 0.0
var _rect: ColorRect


func _ready() -> void:
	effect_id = "camera_fx"
	layer = 3
	_rect = _make_screen_color_rect("res://effects/lens_distort.gdshader")
	_rect.visible = false
	visible = false


func set_active(is_on: bool) -> void:
	enabled = is_on
	if is_on:
		_resolve()
		_push_to_scene(true, _pack())
	else:
		_push_to_scene(false, {})
		_set_lens_overlay(false, 0.0)


func apply_params(params: Dictionary) -> void:
	super.apply_params(params)
	_resolve()
	if enabled:
		_push_to_scene(true, _pack())


func apply_audio_state(_state: AudioState) -> void:
	if not enabled:
		_push_to_scene(false, {})
		_set_lens_overlay(false, 0.0)
		return
	_resolve()
	_push_to_scene(true, _pack())


func apply_modulator(_mod01: float) -> void:
	pass


func _on_params_changed(_params: Dictionary) -> void:
	_resolve()


func _resolve() -> void:
	_focal_length = eval_num("focal_length", _focal_length, 1.0, 2000.0)
	_aperture = eval_num("aperture", _aperture, 0.7, 22.0)
	_focus_distance = eval_num("focus_distance", _focus_distance, 0.2, 200.0)
	if has_raw_param("bokeh"):
		_bokeh = eval_num("bokeh", _bokeh, 0.0, 1.5)
	elif has_raw_param("dof_amount"):
		_bokeh = eval_num("dof_amount", _bokeh, 0.0, 1.5)
	_lens_distortion = eval_num("lens_distortion", _lens_distortion, 0.0, 1.0)


func _pack() -> Dictionary:
	return {
		"focal_length": _focal_length,
		"aperture": _aperture,
		"focus_distance": _focus_distance,
		"bokeh": _bokeh,
		"dof_amount": _bokeh,
		"lens_distortion": _lens_distortion,
		"far_enabled": true,
		"near_enabled": true,
		"drive": 1.0,
	}


func _push_to_scene(on: bool, params: Dictionary) -> void:
	var lens := float(params.get("lens_distortion", _lens_distortion)) if on else 0.0
	_set_lens_overlay(on and lens > 0.008, lens)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var director: Node = tree.root.get_node_or_null("ShowDirector")
	if director == null:
		return
	var node: Variant = director.get("current_item_node")
	if node != null and node is Node and (node as Node).has_method("set_camera_fx"):
		(node as Node).call("set_camera_fx", on, params)


func _set_lens_overlay(on: bool, amount: float) -> void:
	visible = on
	if _rect:
		_rect.visible = on
		var mat := _rect.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("lens_amount", clampf(amount, 0.0, 1.0))
			var vp := get_viewport()
			if vp:
				var sz: Vector2 = vp.get_visible_rect().size
				mat.set_shader_parameter("aspect", maxf(sz.x / maxf(sz.y, 1.0), 0.2))
