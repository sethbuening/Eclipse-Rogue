# relic_storm_weaver.gd
# "Storm Weaver"
# Adds an extra projectile and chain hop to all abilities.
class_name RelicStormWeaver
extends RelicData

const PROJECTILE_COUNT_FLAT: float = 1.0   # +1 projectile per cast
const CHAIN_LENGTH_FLAT:     float = 1.0   # +1 chain hop / beam

func on_equip(player: CharacterBody2D) -> void:
	player.stats.projectile_count_flat += PROJECTILE_COUNT_FLAT
	player.stats.chain_length_flat     += CHAIN_LENGTH_FLAT
