class_name Orb
extends Resource

enum OrbType { SIMPLE, ALLOY }

@export var id:             String             = ""
@export var display_name:   String             = ""
@export var orb_type:       OrbType            = OrbType.SIMPLE
@export var abilities:      Array[AbilityData] = []
@export var orb_potency:    float              = 1.0   # renamed from power
var node_power_base:        float              = -1.0
@export var light_stored:   float              = 0.0
@export var sprite_texture: Texture2D
@export var input_action:   String             = ""

var node_index: int = -1
var cooldown: float = 0.0
var nonhold_fired: bool = false

func _init() -> void:
	var duped: Array[AbilityData] = []
	for a: AbilityData in abilities:
		duped.append(a.duplicate(true))
	abilities = duped

func clone() -> Orb:
	var duped: Orb = duplicate(true)
	var duped_abilities: Array[AbilityData] = []
	for a: AbilityData in duped.abilities:
		duped_abilities.append(a.duplicate(true))
	duped.abilities = duped_abilities
	return duped

func is_alloy() -> bool:
	return orb_type == OrbType.ALLOY

func primary_ability() -> AbilityData:
	if abilities.is_empty():
		return null
	return abilities[0]

func activate_all(context: Dictionary) -> void:
	context["orb_potency"] = orb_potency   # renamed key
	for ability: AbilityData in abilities:
		if ability != null:
			ability.activate(context)

func activate_trigger(trigger: AbilityData.TriggerType, context: Dictionary) -> void:
	context["orb_potency"] = orb_potency   # renamed key
	for ability: AbilityData in abilities:
		if ability != null and ability.trigger_type == trigger:
			ability.activate(context)

func store_light(amount: float) -> void:
	light_stored  += amount
	orb_potency    = 1.0 + light_stored * 0.01

func add_charge(stacks: int) -> void:
	var base: float = node_power_base if node_power_base >= 0.0 else orb_potency
	for ability: AbilityData in abilities:
		ability.stats.power = base * (1.0 + stacks * 0.1)

func clear_charges() -> void:
	var base: float = node_power_base if node_power_base >= 0.0 else orb_potency
	for ability: AbilityData in abilities:
		ability.stats.power = base
