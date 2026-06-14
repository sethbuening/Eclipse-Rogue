# relic_arcane_core.gd
# "Arcane Core"
# Increases the damage and range of all abilities.
class_name RelicArcaneCore
extends RelicData

const DAMAGE_FLAT: float = 5.0
const RANGE_MULT: float = 0.2   # +20% range

func on_equip(player: CharacterBody2D) -> void:
	player.stats.damage_flat += DAMAGE_FLAT
	player.stats.range_mult += RANGE_MULT
