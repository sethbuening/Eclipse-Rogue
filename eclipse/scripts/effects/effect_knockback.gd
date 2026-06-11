# effect_knockback.gd
# ---------------------------------------------------------------------------
# Applies a velocity impulse that decays over time.
# Multiple knockbacks stack additively on the velocity vector.
#
# Usage:
#   var e := _get_or_create_effect("knockback") as EffectKnockback
#   e.velocity += impulse
#   e.apply(enemy, 0.0)
# ---------------------------------------------------------------------------
class_name EffectKnockback
extends EffectData

const DECAY:     float = 8.0
const MIN_SPEED: float = 1.0

## Set / accumulate this before calling apply().
var velocity: Vector2 = Vector2.ZERO

func _init() -> void:
	id           = "knockback"
	display_name = "Knockback"
	description  = "Being pushed back."
	icon_color   = Color(1.0, 1.0, 1.0, 0.6)

func apply(_enemy: Enemy, _new_duration: float) -> bool:
	duration = 99999.0
	return true

func tick(delta: float, _enemy: Enemy) -> void:
	velocity -= velocity * DECAY * delta
	if velocity.length_squared() < MIN_SPEED * MIN_SPEED:
		duration = 0.0

func on_remove(_enemy: Enemy) -> void:
	velocity = Vector2.ZERO
