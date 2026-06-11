# relic_bone_mantle.gd
# "Bone Mantle"
# The remains of fallen enemies reinforce the wearer.
# Grants damage absorption, armor, and extended ability durations.
#
# Note: the kill-stacking version of this relic requires on_kill() to be wired
# in player.gd.  Until then this grants a solid passive defensive bonus.
class_name RelicBoneMantle
extends RelicData

const DAMAGE_ABSORB_FLAT: float = 4.0    # absorb 4 flat damage per hit
const ARMOR_BONUS_FLAT:   float = 3.0    # +3 armor
const DURATION_MULT:      float = 0.15   # +15% ability duration

func on_equip(player: CharacterBody2D) -> void:
	player.stats.damage_absorb_flat += DAMAGE_ABSORB_FLAT
	player.stats.armor_bonus_flat   += ARMOR_BONUS_FLAT
	player.stats.duration_mult      += DURATION_MULT
