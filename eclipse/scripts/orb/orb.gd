class_name Orb
extends Resource

enum OrbType { SIMPLE, ALLOY }

@export var id:             String             = ""
@export var display_name:   String             = ""
@export var orb_type:       OrbType            = OrbType.SIMPLE
@export var abilities:      Array[AbilityData] = []
@export var orb_potency:    float              = 1.0
var node_damage_base:        float              = -1.0
@export var sprite_texture: Texture2D
@export var input_action:   String             = ""
var cooldown:               float              = 0.0

## Total metal units ever forged into this orb (cumulative across all forge sessions).
## Every 100 metal increases ability_max by 1.
var total_metal_forged:     int                = 0

## Maximum number of abilities this orb can hold.
## Starts at 1 and increases by 1 for every 100 total metal forged into it.
var ability_max:            int                = 1

## Per-metal breakdown of all metal ever forged into this orb.
## Used to compute weighted ability type for the "add ability" level-up upgrade.
## Keys: MetalData  Values: int (cumulative count)
var metal_composition:      Dictionary         = {}  # MetalData → int

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
	_compute_cooldown()

func _compute_cooldown() -> void:
	if cooldown != 0.0:
		return
	var total: float = 0.0
	var count: int   = 0
	for ability: AbilityData in abilities:
		if ability.stats != null and ability.stats.cooldown != -1:
			total += ability.stats.cooldown
			count += 1
	cooldown = total / count if count > 0 else 1.0

func clone() -> Orb:
	var duped: Orb = duplicate(true)
	var duped_abilities: Array[AbilityData] = []
	for a: AbilityData in duped.abilities:
		duped_abilities.append(a.duplicate(true))
	duped.abilities = duped_abilities
	duped.cooldown = 0.0
	duped.total_metal_forged = total_metal_forged
	duped.ability_max = ability_max
	duped.metal_composition = metal_composition.duplicate()
	duped._compute_cooldown()
	return duped

func is_alloy() -> bool:
	return orb_type == OrbType.ALLOY

## Register [amount] units of metal being forged into this orb.
## Recalculates ability_max: 1 base + 1 per 100 cumulative metal.
## Pass [metal] to also update the per-metal composition used for ability-type weighting.
func add_metal_forged(amount: int, metal: MetalData = null) -> void:
	total_metal_forged += amount
	ability_max = 1 + total_metal_forged / 100
	if metal != null and amount > 0:
		metal_composition[metal] = metal_composition.get(metal, 0) + amount

## Returns true when the orb has at least one empty ability slot.
func has_empty_ability_slot() -> bool:
	return abilities.size() < ability_max

func primary_ability() -> AbilityData:
	if abilities.is_empty():
		return null
	return abilities[0]

func add_charge(stacks: int) -> void:
	var base: float = node_damage_base if node_damage_base >= 0.0 else orb_potency
	for ability: AbilityData in abilities:
		ability.stats.damage = base * (1.0 + stacks * 0.1)

func clear_charges() -> void:
	var base: float = node_damage_base if node_damage_base >= 0.0 else orb_potency
	for ability: AbilityData in abilities:
		ability.stats.damage = base
