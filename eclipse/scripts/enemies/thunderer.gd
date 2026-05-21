class_name E_Thunderer
extends Enemy

var buffed_enemies: Array[Enemy] = []
var _buff_timer:    float        = 0.0
var _pulse_timer:   float        = 0.0
@export var buff_pulse_interval: float = 1.5

func _ready() -> void:
	super._ready()
	z_index = 1

#func _draw() -> void:
	#draw_arc(Vector2.ZERO, data.buff_radius, 0.0, TAU, 64, Color(1.0, 0.85, 0.2, 0.5), 1.0)

# ── behavior ──────────────────────────────────────────────────────────────────

func _tick_behavior(delta: float) -> void:
	_tick_buff(delta)

func _tick_buff(delta: float) -> void:
	_buff_timer  += delta
	_pulse_timer += delta

	if _buff_timer >= data.buff_interval:
		_buff_timer = 0.0
		var newly_buffed: Array[Enemy] = []
		for enemy: Enemy in EnemyManager.living_enemies:
			if not is_instance_valid(enemy) or enemy == self or enemy is E_Thunderer or enemy.data == null:
				continue
			if enemy.data.buff_immune:
				continue
			if global_position.distance_to(enemy.global_position) > data.buff_radius:
				continue
			if not buffed_enemies.has(enemy):
				_apply_buff(enemy)
			newly_buffed.append(enemy)
		for enemy: Enemy in buffed_enemies:
			if is_instance_valid(enemy) and not newly_buffed.has(enemy):
				_remove_buff(enemy)
		buffed_enemies = newly_buffed

	if _pulse_timer >= data.buff_pulse_interval and buffed_enemies.size() > 0:
		_pulse_timer = 0.0

# ── apply / remove ────────────────────────────────────────────────────────────

func _apply_buff(enemy: Enemy) -> void:
	enemy.data.speed           = enemy.data.speed * data.buff_speed_mult
	enemy.data.damage          = int(enemy.data.damage * data.buff_damage_mult)
	enemy.data.attack_cooldown = enemy.data.attack_cooldown * data.buff_cooldown_mult
	enemy.data.stun_resistance = minf(enemy.data.stun_resistance + data.buff_stun_resistance, 1.0)
	enemy.data.slow_resistance = minf(enemy.data.slow_resistance + data.buff_slow_resistance, 1.0)
	enemy.data.sep_force       = enemy.data.sep_force * data.buff_sep_force_mult
	enemy._navigator.move_speed = enemy.data.speed

func _remove_buff(enemy: Enemy) -> void:
	if data.buff_speed_mult     != 0.0: enemy.data.speed           = enemy.data.speed / data.buff_speed_mult
	if data.buff_damage_mult    != 0.0: enemy.data.damage          = int(enemy.data.damage / data.buff_damage_mult)
	if data.buff_cooldown_mult  != 0.0: enemy.data.attack_cooldown = enemy.data.attack_cooldown / data.buff_cooldown_mult
	if data.buff_sep_force_mult != 0.0: enemy.data.sep_force       = enemy.data.sep_force / data.buff_sep_force_mult
	enemy.data.stun_resistance  = maxf(enemy.data.stun_resistance - data.buff_stun_resistance, 0.0)
	enemy.data.slow_resistance  = maxf(enemy.data.slow_resistance - data.buff_slow_resistance, 0.0)
	enemy._navigator.move_speed = enemy.data.speed

# ── movement ──────────────────────────────────────────────────────────────────

func _compute_nav_velocity(delta: float) -> Vector2:
	var best_pos:   Vector2 = Vector2.ZERO
	var best_count: int     = 0
	for candidate: Enemy in EnemyManager.living_enemies:
		if not is_instance_valid(candidate) or candidate == self or candidate is E_Thunderer:
			continue
		var count: int = 0
		for other: Enemy in EnemyManager.living_enemies:
			if not is_instance_valid(other) or other == self or other is E_Thunderer:
				continue
			if candidate.global_position.distance_to(other.global_position) < data.buff_radius:
				count += 1
		if count > best_count:
			best_count = count
			best_pos   = candidate.global_position
	var raw_target: Vector2 = best_pos if best_count > 0 else player.global_position
	var target:     Vector2 = _range_offset_target(raw_target, data.preferred_range)
	if NavManager._built:
		return _navigator.navigate_toward(target, delta) + _separation_velocity()
	return (target - global_position).normalized() * data.speed + _separation_velocity()

# ── combat ────────────────────────────────────────────────────────────────────

func die() -> void:
	for enemy: Enemy in buffed_enemies:
		if is_instance_valid(enemy):
			_remove_buff(enemy)
	buffed_enemies.clear()
	super.die()
