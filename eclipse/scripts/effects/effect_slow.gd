# effect_slow.gd
# ---------------------------------------------------------------------------
# Reduces the enemy's move speed by [amount] (0–1 fraction).
# The strongest active application wins; weaker ones are silently rejected.
#
# Usage:
#   var e := _get_or_create_effect("slow") as EffectSlow
#   e.amount = scaled_amount
#   e.apply(enemy, duration)
# ---------------------------------------------------------------------------
class_name EffectSlow
extends EffectData

## Fraction of speed removed (0 = no slow, 1 = fully stopped).
## Set this before calling apply().
var amount: float = 0.0

func _init() -> void:
	id           = "slow"
	display_name = "Slowed"
	description  = "Movement speed reduced."
	icon_color   = Color(0.4, 0.7, 1.0, 1.0)   # ice blue

func apply(enemy: Enemy, new_duration: float) -> bool:
	# Keep the strongest slow.
	if amount <= 0.0 and new_duration <= duration:
		return false
	duration = new_duration
	enemy._navigator.move_speed = enemy.data.speed * (1.0 - amount)
	return true

func tick(delta: float, _enemy: Enemy) -> void:
	duration -= delta

func on_remove(enemy: Enemy) -> void:
	enemy._navigator.move_speed = enemy.data.speed
