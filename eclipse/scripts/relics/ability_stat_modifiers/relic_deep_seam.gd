# relic_deep_seam.gd
# "Deep Seam"
# Stronger mining, wider reach, and richer ore drops.
class_name RelicDeepSeam
extends RelicData

const MINING_POWER_FLAT:  float = 2.0    # +2 mining power
const MINING_RADIUS_FLAT: float = 1.0    # +1 tile mining radius
const ORE_YIELD_MULT:     float = 0.50   # +50% ore per block

func on_equip(player: CharacterBody2D) -> void:
	player.stats.mining_power_flat  += MINING_POWER_FLAT
	player.stats.mining_radius_flat += MINING_RADIUS_FLAT
	player.stats.ore_yield_mult     += ORE_YIELD_MULT
