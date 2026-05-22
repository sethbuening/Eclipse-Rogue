# insulator.gd
class_name E_Insulator
extends Enemy

const DAMPEN_RADIUS: float = 120.0
const DAMPEN_FACTOR: float = 0.15   # arcs do 15% damage within range

static var living_insulators: Array[E_Insulator] = []

func _ready() -> void:
	super._ready()
	living_insulators.append(self)

func die() -> void:
	living_insulators.erase(self)
	super.die()

## Returns a 0.0–1.0 damage multiplier for an arc between two world positions.
static func get_arc_multiplier(from: Vector2, to: Vector2) -> float:
	for ins: E_Insulator in living_insulators:
		if not is_instance_valid(ins):
			continue
		if ins.global_position.distance_to(from) <= DAMPEN_RADIUS \
		or ins.global_position.distance_to(to)   <= DAMPEN_RADIUS:
			return DAMPEN_FACTOR
	return 1.0
