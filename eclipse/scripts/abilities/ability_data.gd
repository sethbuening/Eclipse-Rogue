class_name AbilityData
extends Resource

enum TriggerType { ACTIVE, PASSIVE }

@export var id:            String       = ""
@export var display_name:  String       = ""
@export var description:   String       = ""
@export var trigger_type:  TriggerType  = TriggerType.ACTIVE
@export var requires_hold: bool         = false
@export var stats:         AbilityStats = AbilityStats.new()

## Stats listed here are multiplied by orb_potency when accessed via get_stat().
## Set this in each subclass _init() or via the Inspector.
## Example: ["power", "mining_radius"]
@export var main_stats: Array[String] = []

var _cooldown_remaining: float = 0.0
var _orb_potency:        float = 1.0  # written by Orb before activate()

## Call this instead of stats.power etc. inside activate().
## Automatically applies orb_potency multiplier to declared main_stats.
func get_stat(stat_name: String) -> float:
	return stats.get_stat(stat_name, _orb_potency, main_stats)

func activate(context: Dictionary) -> void:
	_orb_potency = context.get("orb_potency", 1.0)

func tick_cooldown(delta: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)

func is_ready() -> bool:
	return _cooldown_remaining <= 0.0

func start_cooldown() -> void:
	_cooldown_remaining = stats.cooldown

func cooldown_fraction() -> float:
	if stats.cooldown <= 0.0:
		return 1.0
	return 1.0 - (_cooldown_remaining / stats.cooldown)

func reset_cooldown() -> void:
	_cooldown_remaining = 0.0
