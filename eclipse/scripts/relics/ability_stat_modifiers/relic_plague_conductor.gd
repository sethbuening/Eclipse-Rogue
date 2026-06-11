# relic_plague_conductor.gd
# "Plague Conductor"
# Chains carry disease — extra hops spread stronger, longer-lasting DoT.
class_name RelicPlagueConductor
extends RelicData

const CHAIN_LENGTH_FLAT: float = 1.0    # +1 chain hop / beam
const DOT_DAMAGE_MULT:   float = 0.40   # +40% DoT damage per tick
const DOT_DURATION_FLAT: float = 1.5    # +1.5 seconds DoT duration

func on_equip(player: CharacterBody2D) -> void:
	player.stats.chain_length_flat += CHAIN_LENGTH_FLAT
	player.stats.dot_damage_mult   += DOT_DAMAGE_MULT
	player.stats.dot_duration_flat += DOT_DURATION_FLAT
