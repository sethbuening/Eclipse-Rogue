class_name AbilityData
extends Resource

enum TriggerType { ACTIVE, PASSIVE }

@export var id:            String       = ""
@export var display_name:  String       = ""
@export var description:   String       = ""
@export var trigger_type:  TriggerType  = TriggerType.ACTIVE
@export var requires_hold: bool         = false
@export var stats:         AbilityStats = AbilityStats.new()

enum TargetingMode {
	NONE,        # instant, no preview (dash, passive)
	DIRECTION,   # shows a line/arrow from player to mouse (basic attack, drill)
	AREA,        # shows a radius circle at cursor (bomb, seismic)
	TILE,        # highlights tiles under cursor (focus mine)
	POINT,       # click anywhere on the map, no enemy required (teleport)
	ENEMY,       # click an enemy to select it; respects max_targets (tether, slow)
	SELF_AREA,   # shows a radius circle around the player (shockwave, burst)
}

@export var targeting_mode: TargetingMode = TargetingMode.NONE

## How many enemies must be selected before the ability fires.
## Only used when targeting_mode == ENEMY.
@export var max_targets: int = 1

## Stats listed here are multiplied by orb_potency when accessed via get_stat().
@export var main_stats: Array[String] = []

var _orb_potency:        float = 1.0

func get_stat(stat_name: String) -> float:
	return stats.get_stat(stat_name, _orb_potency, main_stats)

func activate(context: Dictionary) -> void:
	_orb_potency = context.get("orb_potency", 1.0)
