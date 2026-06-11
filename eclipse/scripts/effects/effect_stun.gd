# effect_stun.gd
# ---------------------------------------------------------------------------
# Prevents the enemy from acting (movement AI and attacks are skipped).
# The enemy still moves under external forces (knockback).
# ---------------------------------------------------------------------------
class_name EffectStun
extends EffectData

func _init() -> void:
	id           = "stun"
	display_name = "Stunned"
	description  = "Cannot move or attack."
	icon_color   = Color(1.0, 0.95, 0.3, 1.0)   # yellow

## Re-apply only if the new duration is strictly longer than what remains.
func apply(enemy: Enemy, new_duration: float) -> bool:
	if new_duration <= duration:
		return false
	duration = new_duration
	return true
