class_name AbilityData
extends Resource

@export var id:            String       = ""
@export var display_name:  String       = ""
@export var description:   String       = ""
@export var targeting_type: Util.TargetingType = Util.TargetingType.ENEMY_TILE
@export var stats:         AbilityStats = AbilityStats.new()

## Stats listed here are multiplied by orb_potency when accessed via get_stat().
@export var main_stats: Array[String] = []

var _orb_potency: float = 1.0

func get_stat(stat_name: String) -> float:
	return stats.get_stat(stat_name, _orb_potency, main_stats)

## Called every frame by the player for every ability, regardless of type.
## Subclasses fire whenever they find a valid target — no input gating.
## Write context["activated"] = true to trigger the orb shatter / light cost.
func tick(context: Dictionary) -> void:
	_orb_potency = context.get("potency", 1.0)
