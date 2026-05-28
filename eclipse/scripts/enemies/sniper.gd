# sniper.gd
class_name E_Sniper
extends Enemy

const PREFERRED_DIST: float = 240.0
const FLEE_DIST:      float = 120.0

var _attack_timer: float = 0.0

func _tick_behavior(delta: float) -> void:
	_attack_timer += delta
	if _attack_timer >= data.attack_cooldown:
		_attack_timer = 0.0
		_fire()

func _fire() -> void:
	var is_crit: bool = data.stats_roll_crit()  # see note below
	var damage:  int  = data.damage * (3 if is_crit else 1)
	# Spawn a projectile node toward player — reuse basic_attack_traveller or make a new one
	# For now, instant hitscan version:
	var dist: float = global_position.distance_to(player.global_position)
	if dist <= data.attack_range:
		player.light -= damage
		DamageNumbers.spawn(player.global_position + Vector2(0,-28), damage, is_crit)
