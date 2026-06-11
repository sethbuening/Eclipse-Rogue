# relic_kinetic_surge.gd
# "Kinetic Surge"
# Accelerates cast speed, projectile speed, and player movement.
class_name RelicKineticSurge
extends RelicData

const CAST_SPEED_MULT:  float = 0.25   # +25% cast speed
const PROJ_SPEED_MULT:  float = 0.20   # +20% projectile speed
const MOVE_SPEED_FLAT:  float = 20.0   # +20 flat movement speed

func on_equip(player: CharacterBody2D) -> void:
	player.stats.cast_speed_mult       += CAST_SPEED_MULT
	player.stats.projectile_speed_mult += PROJ_SPEED_MULT
	player.stats.move_speed_bonus_flat += MOVE_SPEED_FLAT
