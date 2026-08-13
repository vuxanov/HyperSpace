extends EffectLayer
class_name ReactionDiffusionEffect

## Gray-Scott reaction-diffusion overlay. Sim runs in a small ping-pong viewport.

const SIM_SIZE := 256
const PRESETS := {
	"Coral": {"feed": 0.0545, "kill": 0.062},
	"Mitosis": {"feed": 0.0367, "kill": 0.0649},
	"Spots": {"feed": 0.035, "kill": 0.065},
	"Worms": {"feed": 0.046, "kill": 0.063},
	"Waves": {"feed": 0.025, "kill": 0.06},
}

var _rect: ColorRect
var _vp: Array[SubViewport] = []
var _sim_rects: Array[ColorRect] = []
var _swap: int = 0
var _seed_t: float = 0.4
var _time: float = 0.0
var _feed: float = 0.0545
var _kill: float = 0.062
var _speed: float = 1.0
var _mix: float = 0.55


func _ready() -> void:
	effect_id = "rd"
	layer = 8
	_build_sim()
	_rect = _make_screen_color_rect("res://effects/reaction_diffusion.gdshader")
	_apply_display()
	visible = false
	set_process(true)


func _build_sim() -> void:
	var sim_shader: Shader = load("res://effects/reaction_diffusion_sim.gdshader") as Shader
	for i in 2:
		var vp := SubViewport.new()
		vp.size = Vector2i(SIM_SIZE, SIM_SIZE)
		vp.transparent_bg = false
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
		var r := ColorRect.new()
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.size = Vector2(SIM_SIZE, SIM_SIZE)
		var mat := ShaderMaterial.new()
		if sim_shader:
			mat.shader = sim_shader
		r.material = mat
		vp.add_child(r)
		add_child(vp)
		_vp.append(vp)
		_sim_rects.append(r)
	_vp[0].render_target_update_mode = SubViewport.UPDATE_ONCE


func set_active(is_on: bool) -> void:
	enabled = is_on
	visible = is_on
	if _rect:
		_rect.visible = is_on
	if is_on:
		_seed_t = 0.45
	set_process(is_on)


func apply_params(params: Dictionary) -> void:
	super.apply_params(params)
	_apply_resolved()
	visible = enabled


func apply_audio_state(_state: AudioState) -> void:
	if not enabled:
		visible = false
		return
	visible = true
	_apply_resolved()


func _on_params_changed(_params: Dictionary) -> void:
	_apply_resolved()
	visible = enabled


func _apply_resolved() -> void:
	if has_raw_param("preset"):
		var pname := str(_raw_params.get("preset", ""))
		if PRESETS.has(pname):
			var p: Dictionary = PRESETS[pname]
			if not has_raw_param("feed"):
				_feed = float(p.get("feed", _feed))
			if not has_raw_param("kill"):
				_kill = float(p.get("kill", _kill))
	_feed = eval_num("feed", _feed, 0.01, 0.1)
	_kill = eval_num("kill", _kill, 0.04, 0.08)
	_speed = eval_num("speed", _speed, 0.1, 3.0)
	_mix = eval_num("mix_amount", _mix, 0.0, 1.0)
	_apply_display()


func _apply_display() -> void:
	var mat := _mat()
	if mat == null or mat.shader == null:
		return
	var src: Texture2D = _vp[_swap].get_texture() if _vp.size() == 2 else null
	if src:
		mat.set_shader_parameter("rd_tex", src)
	mat.set_shader_parameter("mix_amount", clampf(_mix, 0.0, 1.0))


func _process(delta: float) -> void:
	if not enabled or _vp.size() < 2:
		return
	_time += delta
	if _seed_t > 0.0:
		_seed_t = maxf(_seed_t - delta, 0.0)
	var src_i := _swap
	var dst_i := 1 - _swap
	var smat := _sim_rects[dst_i].material as ShaderMaterial
	if smat and smat.shader:
		smat.set_shader_parameter("prev_tex", _vp[src_i].get_texture())
		smat.set_shader_parameter("feed", _feed)
		smat.set_shader_parameter("kill", _kill)
		smat.set_shader_parameter("speed", _speed)
		smat.set_shader_parameter("seed_on", 1.0 if _seed_t > 0.0 else 0.0)
		smat.set_shader_parameter("time_sec", _time)
	_vp[dst_i].render_target_update_mode = SubViewport.UPDATE_ONCE
	_swap = dst_i
	_apply_display()


func _mat() -> ShaderMaterial:
	if _rect and _rect.material is ShaderMaterial:
		return _rect.material as ShaderMaterial
	return null
