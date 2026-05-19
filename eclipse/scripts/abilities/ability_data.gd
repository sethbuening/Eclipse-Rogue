class_name AbilityData
extends Resource

enum TriggerType { ACTIVE, PASSIVE }

@export var id:            String       = ""
@export var display_name:  String       = ""
@export var description:   String       = ""
@export var trigger_type:  TriggerType  = TriggerType.ACTIVE
@export var requires_hold: bool         = false
@export var stats:         AbilityStats = AbilityStats.new()

var _cooldown_remaining: float = 0.0

func activate(context: Dictionary) -> void:
	pass

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
