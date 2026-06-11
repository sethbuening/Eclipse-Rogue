# relic_iron_veil.gd
# "Iron Veil"
# Fortifies the player with absorption, shielding, armor, and armor pen.
class_name RelicIronVeil
extends RelicData

const DAMAGE_ABSORB_FLAT:  float = 3.0    # absorb 3 flat damage per hit
const REFLECT_CHANCE_FLAT: float = 0.08   # +8% reflect chance
const SHIELD_AMOUNT_FLAT:  float = 15.0   # +15 shield HP
const ARMOR_BONUS_FLAT:    float = 2.0    # +2 armor
const ARMOR_PEN_FLAT:      float = 2.0    # +2 armor penetration on hits

func on_equip(player: CharacterBody2D) -> void:
	player.stats.damage_absorb_flat  += DAMAGE_ABSORB_FLAT
	player.stats.reflect_chance_flat += REFLECT_CHANCE_FLAT
	player.stats.shield_amount_flat  += SHIELD_AMOUNT_FLAT
	player.stats.armor_bonus_flat    += ARMOR_BONUS_FLAT
	player.stats.armor_pen_flat      += ARMOR_PEN_FLAT
