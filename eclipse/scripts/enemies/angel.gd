class_name E_Angel
extends Enemy

var _pylons:       Array[E_Pylon] = []
var _pylons_alive: int            = 0
var _vulnerable:   bool           = false
var _heal_timer:   float          = 0.0

var _nav_target:       Vector2 = Vector2.ZERO
var _nav_target_raw:   Vector2 = Vector2.ZERO
var _nav_update_timer: float   = 0.0
var _smoothed_sep_vel: Vector2 = Vector2.ZERO

const NAV_UPDATE_INTERVAL: float = 0.2
const NAV_TARGET_LERP:     float = 4.0

# ── lifecycle ─────────────────────────────────────────────────────────────────

func initialize(p: CharacterBody2D, modifier: Util.Modifier = Util.Modifier.NONE) -> void:
	super.initialize(p, modifier)
	_nav_target     = player.global_position
	_nav_target_raw = player.global_position
	_spawn_pylons()

# ── pylons ────────────────────────────────────────────────────────────────────

func _spawn_pylons() -> void:
	for i in data.spawn_count:
		var pylon: E_Pylon = data.spawned_unit_data.scene.instantiate() as E_Pylon
		pylon.data         = data.spawned_unit_data
		pylon.health       = data.spawned_unit_data.max_health
		add_child(pylon)
		pylon.setup(self, (TAU / data.spawn_count) * i)
		pylon.died.connect(_on_pylon_died)
		EnemyManager.register_enemy(pylon)
		_pylons.append(pylon)
	_pylons_alive = _pylons.size()

func _on_pylon_died(pylon: E_Pylon) -> void:
	_pylons.erase(pylon)
	_pylons_alive -= 1
	if _pylons_alive <= 0:
		_vulnerable = true
		print("angel is now vulnerable: %d pylons left" % _pylons_alive)

# ── behavior ──────────────────────────────────────────────────────────────────

func _tick_behavior(delta: float) -> void:
	_tick_healing(delta)

func _tick_healing(delta: float) -> void:
	_heal_timer += delta
	if _heal_timer < data.heal_interval:
		return
	_heal_timer = 0.0
	var heal: int = int(data.heal_amount_per_sec * data.heal_interval)
	for enemy: Enemy in EnemyManager.living_enemies:
		if not is_instance_valid(enemy) or enemy == self or enemy.data == null:
			continue
		if global_position.distance_to(enemy.global_position) <= data.heal_radius:
			var actual: int = mini(heal, enemy.data.max_health - enemy.health)
			if actual <= 0:
				continue
			enemy.health += actual
			DamageNumbers.spawn_heal(enemy.global_position + Vector2(0, -16), actual)

# ── movement ──────────────────────────────────────────────────────────────────

func _compute_nav_velocity(delta: float) -> Vector2:
	_nav_update_timer += delta
	if _nav_update_timer >= NAV_UPDATE_INTERVAL:
		_nav_update_timer = 0.0
		_nav_target_raw   = _find_best_target()

	_nav_target       = _nav_target.lerp(_nav_target_raw, NAV_TARGET_LERP * delta)
	_smoothed_sep_vel = _smoothed_sep_vel.lerp(_separation_velocity(), 10.0 * delta)

	var target: Vector2 = _range_offset_target(_nav_target, data.preferred_range)
	if NavManager._built:
		return _navigator.navigate_toward(target, delta) + _smoothed_sep_vel
	return (target - global_position).normalized() * data.speed + _smoothed_sep_vel

func _find_best_target() -> Vector2:
	var best_pos:   Vector2 = Vector2.ZERO
	var best_count: int     = 0
	for candidate: Enemy in EnemyManager.living_enemies:
		if not is_instance_valid(candidate) or candidate == self or candidate is E_Pylon:
			continue
		var count: int = 0
		for other: Enemy in EnemyManager.living_enemies:
			if not is_instance_valid(other) or other == self or other is E_Pylon:
				continue
			if candidate.global_position.distance_to(other.global_position) < data.heal_radius:
				count += 1
		if count > best_count:
			best_count = count
			best_pos   = candidate.global_position
	return best_pos if best_count > 0 else player.global_position

# ── combat ────────────────────────────────────────────────────────────────────

func take_damage(amount: int, is_crit: bool = false) -> void:
	if not _vulnerable:
		return
	super.take_damage(amount, is_crit)

func die() -> void:
	for pylon: E_Pylon in _pylons:
		if is_instance_valid(pylon):
			EnemyManager.unregister_enemy(pylon)
			pylon.queue_free()
	super.die()
