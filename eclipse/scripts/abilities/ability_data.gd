class_name AbilityData
extends Resource

enum TriggerType { ACTIVE, PASSIVE }

@export var id:            String       = ""
@export var display_name:  String       = ""
@export var description:   String       = ""
@export var trigger_type:  TriggerType  = TriggerType.ACTIVE
@export var requires_hold: bool         = false
@export var targeting_type: Util.TargetingType = Util.TargetingType.ENEMY_TILE
@export var stats:         AbilityStats = AbilityStats.new()

## Stats listed here are multiplied by orb_potency when accessed via get_stat().
@export var main_stats: Array[String] = []

var _orb_potency: float = 1.0

func get_stat(stat_name: String) -> float:
	return stats.get_stat(stat_name, _orb_potency, main_stats)

## Base activate — stores orb_potency from context.
## Subclasses should call super.activate(context) first, or handle _orb_potency themselves.
func activate(context: Dictionary) -> void:
	_orb_potency = context.get("potency", 1.0)
