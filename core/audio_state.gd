class_name AudioState
extends Resource

## Snapshot of audio analysis for one frame, shared across all reactive systems.

@export var bands: PackedFloat32Array = PackedFloat32Array()
@export var energy: float = 0.0
@export var peak: float = 0.0
@export var input_level: float = 0.0  ## Peak-normalized capture level 0..1 (EQ / meter)
@export var beat: bool = false
@export var bass: float = 0.0
@export var mids: float = 0.0
@export var highs: float = 0.0
@export var kick: float = 0.0  # short onset envelope (not sustained bass)


func duplicate_state() -> AudioState:
	var copy := AudioState.new()
	copy.bands = bands.duplicate()
	copy.energy = energy
	copy.peak = peak
	copy.input_level = input_level
	copy.beat = beat
	copy.bass = bass
	copy.mids = mids
	copy.highs = highs
	copy.kick = kick
	return copy
