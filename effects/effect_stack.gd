extends Node
class_name EffectStack

## Factory and container for stackable effect layers on the output.


func create_effect(effect_id: String) -> EffectLayer:
	match effect_id:
		"ascii":
			return AsciiEffect.new()
		"particles":
			return ParticleAudioEffect.new()
		"feedback":
			return FeedbackEffect.new()
		"glitch":
			return GlitchEffect.new()
		"chromatic":
			return ChromaticEffect.new()
		"pixel_sort":
			return PixelSortEffect.new()
		"wireframe":
			return WireframeEffect.new()
		_:
			push_warning("EffectStack: unknown effect '%s'" % effect_id)
			return null
