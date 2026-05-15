# ability_data.gd
class_name AbilityData
extends Resource

enum TriggerType { ACTIVE, PASSIVE }

@export var id:           String       = ""
@export var display_name: String       = ""
@export var description:  String       = ""
@export var trigger_type: TriggerType  = TriggerType.ACTIVE
@export var requires_hold: bool = false  # true = is_action_pressed, false = is_action_just_pressed
@export var stats:        AbilityStats = AbilityStats.new()

# Override in subclasses to define what this ability does.
# context carries mutable state the ability can read and write:
# { "player": Node, "power": float, "position": Vector2, "damage": float, ... }
func activate(context: Dictionary) -> void:
	pass
