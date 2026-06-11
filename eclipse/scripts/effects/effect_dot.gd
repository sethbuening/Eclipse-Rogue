# effect_dot.gd
# ---------------------------------------------------------------------------
# Deals damage over time at [dps] per second.
# The highest total-damage application wins (dps * duration).
#
# Usage:
#   var e := _get_or_create_effect("dot") as EffectDot
#   e.dps = scaled_dps
#   e.apply(enemy, duration)
# ---------------------------------------------------------------------------
class_name EffectDot
extends EffectData

## Damage per second (already resistance-adjusted before being stored here).
## Set this before calling apply().
var dps:    float = 0.0
var _accum: float = 0.0

func _init() -> void:
	id           = "dot"
	display_name = "Burning"
	description  = "Taking damage over time."
	icon_color   = Color(1.0, 0.45, 0.1, 1.0)   # orange

## Keep the application with the highest total damage (dps × duration).
func apply(enemy: Enemy, new_duration: float) -> bool:
	if dps * new_duration <= dps * duration:
		return false
	duration = new_duration
	_accum   = 0.0
	return true

func tick(delta: float, enemy: Enemy) -> void:
	duration -= delta
	_accum   += dps * delta
	var whole: int = int(_accum)
	if whole > 0:
		_accum -= whole
		enemy.take_damage(whole)
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			duration = 0.0
