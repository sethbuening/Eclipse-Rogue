# relic_expanding_field.gd
# "Expanding Field"
# Widens blast radius and adds pierce to all abilities.
class_name RelicExpandingField
extends RelicData

const AOE_RADIUS_MULT: float = 0.30   # +30% AoE radius
const PIERCE_FLAT:     float = 1.0    # +1 pierce

func on_equip(player: CharacterBody2D) -> void:
	player.stats.aoe_radius_mult += AOE_RADIUS_MULT
	player.stats.pierce_flat     += PIERCE_FLAT
