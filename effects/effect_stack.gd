extends Node
class_name EffectStack

## Factory and container for stackable effect layers on the output.

const _HoleEffect := preload("res://effects/hole_effect.gd")


func create_effect(effect_id: String) -> EffectLayer:
	match effect_id:
		"ascii":
			return AsciiEffect.new()
		"feedback":
			return FeedbackEffect.new()
		"glitch":
			return GlitchEffect.new()
		"chromatic":
			return ChromaticEffect.new()
		"tone":
			return ToneEffect.new()
		"hole":
			return _HoleEffect.new() as EffectLayer
		"wireframe":
			return WireframeEffect.new()
		"point_cloud":
			return PointCloudEffect.new()
		"camera_fx":
			return CameraFxEffect.new()
		"material_override":
			return MaterialOverrideEffect.new()
		"fog":
			return FogEffect.new()
		_:
			push_warning("EffectStack: unknown effect '%s'" % effect_id)
			return null
