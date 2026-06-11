# relic_bloodied_lens.gd
# "Bloodied Lens"
# Raw killing pressure sharpened into critical precision.
# Grants bonus power, faster cooldowns, and increased crit chance.
#
# Note: the kill-stacking version of this relic requires on_kill() to be wired
# up in player.gd (_tick_relics already handles tick; on_kill needs the same
# treatment whenever an enemy dies).  Until then this is a strong passive relic.
class_name RelicBloodiedLens
extends RelicData

const POWER_FLAT:      float = 5.0    # +5 flat damage
const COOLDOWN_MULT:   float = -0.10  # -10% cooldown (abilities fire faster)
const CRIT_CHANCE_FLAT: float = 0.08  # +8% crit chance

func on_equip(player: CharacterBody2D) -> void:
	player.stats.power_flat      += POWER_FLAT
	player.stats.cooldown_mult   += COOLDOWN_MULT
	player.stats.crit_chance_flat += CRIT_CHANCE_FLAT
