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

func _compute_nav_velocity(delta: float) -> Vector2:
	var dist: float   = global_position.distance_to(player.global_position)
	var target: Vector2
	if dist < FLEE_DIST:
		# flee directly away
		target = global_position + (global_position - player.global_position).normalized() * PREFERRED_DIST
	else:
		target = _range_offset_target(player.global_position, PREFERRED_DIST)
	if NavManager._built:
		return _navigator.navigate_toward(target, delta) + _separation_velocity()
	return (target - global_position).normalized() * data.speed + _separation_velocity()

func _fire() -> void:
	var is_crit: bool = data.stats_roll_crit()  # see note below
	var damage:  int  = data.damage * (3 if is_crit else 1)
	# Spawn a projectile node toward player — reuse basic_attack_traveller or make a new one
	# For now, instant hitscan version:
	var dist: float = global_position.distance_to(player.global_position)
	if dist <= data.attack_range:
		player.light -= damage
		DamageNumbers.spawn(player.global_position + Vector2(0,-28), damage, is_crit)
