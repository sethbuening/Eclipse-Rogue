# relic_fractured_prism.gd
# "Fractured Prism"
# Every cast splinters into additional projectiles with increased crit chance.
#
# Note: the shatter-triggered version of this relic requires on_orb_shatter()
# to be wired in player.gd alongside on_equip/tick.  Until then this grants
# its bonus passively.
class_name RelicFracturedPrism
extends RelicData

const PROJ_BONUS:  float = 1.0    # +1 projectile per cast
const CRIT_BONUS:  float = 0.10   # +10% crit chance

func on_equip(player: CharacterBody2D) -> void:
	player.stats.projectile_count_flat += PROJ_BONUS
	player.stats.crit_chance_flat      += CRIT_BONUS
