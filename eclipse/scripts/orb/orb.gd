class_name Orb
extends Resource

enum OrbType { SIMPLE, ALLOY }

@export var id:             String             = ""
@export var display_name:   String             = ""
@export var orb_type:       OrbType            = OrbType.SIMPLE
@export var abilities:      Array[AbilityData] = []
@export var orb_potency:    float              = 1.0
var node_power_base:        float              = -1.0
@export var sprite_texture: Texture2D
@export var input_action:   String             = ""
var cooldown:               float              = 0.0

var node_index: int = -1:
	set(value):
		var was_equipped: bool = node_index != -1
		node_index = value
		var is_equipped: bool = node_index != -1
		if was_equipped != is_equipped:
			SteamStats.update_equipped_orbs_stat()

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

func add_charge(stacks: int) -> void:
	var base: float = node_power_base if node_power_base >= 0.0 else orb_potency
	for ability: AbilityData in abilities:
		ability.stats.power = base * (1.0 + stacks * 0.1)

func clear_charges() -> void:
	var base: float = node_power_base if node_power_base >= 0.0 else orb_potency
	for ability: AbilityData in abilities:
		ability.stats.power = base
