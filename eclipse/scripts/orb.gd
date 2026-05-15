# orb.gd
class_name Orb
extends Resource

enum OrbType { SIMPLE, ALLOY }

@export var id:           String             = ""
@export var display_name: String             = ""
@export var orb_type:     OrbType            = OrbType.SIMPLE
@export var abilities:    Array[AbilityData] = []
@export var power:        float              = 1.0
@export var light_stored: float              = 0.0
@export var sprite_texture: Texture2D
@export var input_action: String = ""  # e.g. "attack_interact", "orb_secondary"
									   # leave empty for passive orbs

func _init() -> void:
	# deep duplicate so each orb owns its own stat instances
	var duped: Array[AbilityData] = []
	for a: AbilityData in abilities:
		duped.append(a.duplicate(true))
	abilities = duped

func is_alloy() -> bool:
	return orb_type == OrbType.ALLOY

func primary_ability() -> AbilityData:
	if abilities.is_empty():
		return null
	return abilities[0]

func activate_all(context: Dictionary) -> void:
	context["power"] = power
	for ability: AbilityData in abilities:
		if ability != null:
			ability.activate(context)

func activate_trigger(trigger: AbilityData.TriggerType, context: Dictionary) -> void:
	context["power"] = power
	for ability: AbilityData in abilities:
		if ability != null and ability.trigger_type == trigger:
			ability.activate(context)

func store_light(amount: float) -> void:
	light_stored += amount
	power         = 1.0 + light_stored * 0.01
