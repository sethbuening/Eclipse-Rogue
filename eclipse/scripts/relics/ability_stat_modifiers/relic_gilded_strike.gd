# relic_gilded_strike.gd
# "Gilded Strike"
# Improves critical hit chance, damage, and explosion radius.
class_name RelicGildedStrike
extends RelicData

const CRIT_CHANCE_FLAT: float = 0.10   # +10% crit chance
const CRIT_DAMAGE_MULT: float = 0.25   # +25% crit damage multiplier
const CRIT_AOE_FLAT:    float = 8.0    # +8 units on crit explosion radius

func on_equip(player: CharacterBody2D) -> void:
	player.stats.crit_chance_flat += CRIT_CHANCE_FLAT
	player.stats.crit_damage_mult += CRIT_DAMAGE_MULT
	player.stats.crit_aoe_flat    += CRIT_AOE_FLAT
