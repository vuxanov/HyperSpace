extends RefCounted
class_name ModulatorBus

## Shared LFO / noise modulators for camera look and choosable reactivity drivers.
## Camera presets are rotation-forward (pitch / roll / multi-axis), not pan.

enum Preset {
	OFF,
	PITCH_ROCK,
	ROLL_BANK,
	ORBIT_TUMBLE,
	SPIRAL_TWIST,
	KICK_SNAP,
}

const PRESET_NAMES := [
	"Off",
	"Pitch rock",
	"Roll bank",
	"Orbit tumble",
	"Spiral twist",
	"Kick snap",
]

## Older UI / save names → current presets (avoid silent Off fallback).
const LEGACY_PRESET_ALIASES := {
	"Sine pan": "Orbit tumble",
	"Sine tilt": "Pitch rock",
	"Figure-8": "Orbit tumble",
	"Noise wander": "Spiral twist",
	"Pulse": "Kick snap",
}

var preset: int = Preset.OFF
var rate: float = 0.35  # Hz-ish
var depth: float = 0.55  # 0..1
var mod01: float = 0.0  # normalized 0..1 output for property drivers
var yaw_offset: float = 0.0
var pitch_offset: float = 0.0
var roll_offset: float = 0.0

var _t: float = 0.0
var _noise := FastNoiseLite.new()
var _pulse: float = 0.0


func _init() -> void:
	_noise.seed = 19
	_noise.frequency = 0.7
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH


func set_preset_name(name: String) -> void:
	var resolved := str(LEGACY_PRESET_ALIASES.get(name, name))
	var idx := PRESET_NAMES.find(resolved)
	preset = idx if idx >= 0 else Preset.OFF


func advance(delta: float, kick: float = 0.0) -> void:
	_t += delta
	if kick > 0.2:
		_pulse = maxf(_pulse, kick)
	_pulse = maxf(_pulse - delta * 3.5, 0.0)

	yaw_offset = 0.0
	pitch_offset = 0.0
	roll_offset = 0.0
	mod01 = 0.0

	if preset == Preset.OFF or depth <= 0.001:
		return

	var w := _t * rate * TAU
	var d := depth
	match preset:
		Preset.PITCH_ROCK:
			# Nod on pitch; tiny opposing roll so it feels like a rotate, not a slide.
			pitch_offset = sin(w) * d * 0.42
			roll_offset = sin(w + PI * 0.5) * d * 0.08
			mod01 = sin(w) * 0.5 + 0.5
		Preset.ROLL_BANK:
			# Airplane-style bank; slight yaw follow so the horizon rotates.
			roll_offset = sin(w) * d * 0.55
			yaw_offset = sin(w) * d * 0.12
			mod01 = sin(w) * 0.5 + 0.5
		Preset.ORBIT_TUMBLE:
			# Multi-axis tumble: phase-offset yaw/pitch/roll (no pure L/R pan).
			yaw_offset = sin(w) * d * 0.28
			pitch_offset = cos(w * 0.85 + 0.7) * d * 0.32
			roll_offset = sin(w * 1.15 + 1.9) * d * 0.38
			mod01 = (sin(w) * 0.5 + 0.5)
		Preset.SPIRAL_TWIST:
			# Coupled yaw+roll spiral with a slow pitch breathe.
			var nx := _noise.get_noise_1d(_t * rate * 6.0)
			yaw_offset = sin(w) * d * 0.22 + nx * d * 0.1
			roll_offset = sin(w + PI * 0.35) * d * 0.48
			pitch_offset = cos(w * 0.5) * d * 0.18
			mod01 = clampf(sin(w) * 0.5 + 0.5, 0.0, 1.0)
		Preset.KICK_SNAP:
			# Beat-driven rotational jolts across axes; quiet sine fill between kicks.
			var snap := clampf(_pulse, 0.0, 1.0)
			yaw_offset = sin(w * 2.0) * d * 0.08 * (0.25 + snap)
			pitch_offset = cos(w * 1.7 + 1.0) * d * 0.22 * snap
			roll_offset = sin(w * 2.3 + 0.4) * d * 0.45 * snap
			mod01 = snap
		_:
			pass
