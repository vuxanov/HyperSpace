class_name AudioState
extends Resource

## Snapshot of audio analysis for one frame, shared across all reactive systems.

@export var bands: PackedFloat32Array = PackedFloat32Array()
@export var energy: float = 0.0
@export var peak: float = 0.0
@export var beat: bool = false
@export var bpm_estimate: float = 120.0
@export var bass: float = 0.0
@export var mids: float = 0.0
@export var highs: float = 0.0


func duplicate_state() -> AudioState:
	var copy := AudioState.new()
	copy.bands = bands.duplicate()
	copy.energy = energy
	copy.peak = peak
	copy.beat = beat
	copy.bpm_estimate = bpm_estimate
	copy.bass = bass
	copy.mids = mids
	copy.highs = highs
	return copy
