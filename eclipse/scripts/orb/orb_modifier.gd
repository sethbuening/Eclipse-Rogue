# orb_modifier.gd
class_name OrbModifier
extends Resource

enum ModType { ADDITIVE, MULTIPLICATIVE }

@export var stat_name:     String  = ""
@export var mod_type:      ModType = ModType.ADDITIVE
@export var value:         float   = 0.0
@export var ability_index: int     = -1  # -1 = apply to all abilities on the orb

func apply(orb: Orb) -> void:
	var targets: Array[AbilityData] = []
	if ability_index == -1:
		targets = orb.abilities
	else:
		if ability_index < orb.abilities.size():
			targets = [orb.abilities[ability_index]]

	for ability: AbilityData in targets:
		var current: Variant = ability.stats.get(stat_name)
		if not (current is float or current is int):
			push_warning("[ForgeModifier] Unknown or non-numeric stat: " + stat_name)
			continue
		match mod_type:
			ModType.ADDITIVE:
				ability.stats.set(stat_name, float(current) + value)
			ModType.MULTIPLICATIVE:
				ability.stats.set(stat_name, float(current) * value)

func unapply(orb: Orb) -> void:
	var targets: Array[AbilityData] = []
	if ability_index == -1:
		targets = orb.abilities
	else:
		if ability_index < orb.abilities.size():
			targets = [orb.abilities[ability_index]]

	for ability: AbilityData in targets:
		var current: Variant = ability.stats.get(stat_name)
		if not (current is float or current is int):
			push_warning("[ForgeModifier] Unknown or non-numeric stat: " + stat_name)
			continue
		match mod_type:
			ModType.ADDITIVE:
				ability.stats.set(stat_name, float(current) - value)
			ModType.MULTIPLICATIVE:
				ability.stats.set(stat_name, float(current) / value)
