# relic_warden_chains.gd
# "Warden Chains"
# Amplifies all crowd-control and damage-over-time effects.
class_name RelicWardenChains
extends RelicData

const KNOCKBACK_MULT:     float = 0.30   # +30% knockback force
const STUN_DURATION_MULT: float = 0.25   # +25% stun duration
const SLOW_AMOUNT_FLAT:   float = 0.10   # +10% slow magnitude
const SLOW_DURATION_MULT: float = 0.20   # +20% slow duration
const DOT_DAMAGE_MULT:    float = 0.25   # +25% DoT damage per tick
const DOT_DURATION_MULT:  float = 0.20   # +20% DoT duration

func on_equip(player: CharacterBody2D) -> void:
	player.stats.knockback_mult     += KNOCKBACK_MULT
	player.stats.stun_duration_mult += STUN_DURATION_MULT
	player.stats.slow_amount_flat   += SLOW_AMOUNT_FLAT
	player.stats.slow_duration_mult += SLOW_DURATION_MULT
	player.stats.dot_damage_mult    += DOT_DAMAGE_MULT
	player.stats.dot_duration_mult  += DOT_DURATION_MULT
