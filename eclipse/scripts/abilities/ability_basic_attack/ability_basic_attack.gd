class_name AbilityBasicAttack
extends AbilityData

var _cooldown_remaining: float = 0.0
var _active_projectiles: Array = []   # untyped — typed Array validates refs on iteration and crashes

const HOME_SPEED_MULT: float = 2.5
const TURN_SPEED:      float = 8.0
const LOS_INTERVAL:    float = 0.1
const LOST_TARGET_TIME: float = 0.3

# ── tick ──────────────────────────────────────────────────────────────────────

func tick(ctx: Dictionary) -> void:
	super.tick(ctx)
	if stats == null:
		push_error("AbilityBasicAttack: stats is null")
		return

	var delta:  float           = ctx["delta"]
	var player: CharacterBody2D = ctx["player"]
	var tilemap                 = player.get_node("%TilemapManager")

	_tick_homing(delta, tilemap)

	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if _cooldown_remaining > 0.0:
		return

	var target: Enemy = _find_nearest_enemy(player, tilemap)
	if target == null:
		return

	if stats.projectile_speed > 0.0:
		_spawn_homing(player.global_position, target, player)
	else:
		var is_crit: bool = _roll_crit(player)
		var damage:  int  = _compute_damage(is_crit)
		target.take_damage(damage, stats.get_armor_pen(), is_crit)
		_apply_on_hit_effects(target, player, is_crit)

	_cooldown_remaining = maxf(0.05, stats.cooldown)

# ── homing tick ───────────────────────────────────────────────────────────────

func _tick_homing(delta: float, tilemap) -> void:
	var alive: Array = []
	for p in _active_projectiles:
		p["travelled"] += p["vel"].length() * delta

		if p["travelled"] >= p["max_range"]:
			continue

		# safely resolve target before any access
		var raw = p["target"]
		var target: Enemy = raw if is_instance_valid(raw) else null
		p["target"] = target

		# los re-check
		p["los_timer"] -= delta
		if p["los_timer"] <= 0.0:
			p["los_timer"] = LOS_INTERVAL
			if target != null and _has_los(p["pos"], target.global_position, tilemap):
				p["los_lost_timer"] = LOST_TARGET_TIME
			else:
				p["los_lost_timer"] = maxf(0.0, p["los_lost_timer"] - LOS_INTERVAL)

		if target != null:
			if p["los_lost_timer"] > 0.0:
				var desired: Vector2 = (target.global_position - p["pos"]).normalized()
				var current: Vector2 = p["vel"].normalized()
				var turn: float = clampf(
					current.angle_to(desired) * HOME_SPEED_MULT,
					-TURN_SPEED * delta,
					 TURN_SPEED * delta
				)
				p["vel"] = p["vel"].rotated(turn)
				p["vel"] = p["vel"].normalized() * stats.projectile_speed
			else:
				p["los_lost_timer"] = maxf(0.0, p["los_lost_timer"] - delta)

		p["pos"] += p["vel"] * delta

		if target != null:
			var dist_sq: float   = p["pos"].distance_squared_to(target.global_position)
			var threshold: float = p["radius"] + 8.0
			if dist_sq <= threshold * threshold:
				target.take_damage(p["damage"], p["armor_pen"], p["is_crit"])
				if p["on_hit"].is_valid():
					p["on_hit"].call(target)
				ProjectileManager._spawn_flash(p["pos"], p["color"])
				if p["pierce"] <= 0:
					continue
				else:
					p["pierce"] -= 1
					p["target"] = _find_next_target(p["pos"], target, p["player"], tilemap)

		alive.append(p)

	_active_projectiles = alive

# ── spawn ─────────────────────────────────────────────────────────────────────

func _spawn_homing(origin: Vector2, target: Enemy, player: CharacterBody2D) -> void:
	var is_crit: bool = _roll_crit(player)
	var damage:  int  = _compute_damage(is_crit)
	var dir: Vector2  = (target.global_position - origin).normalized()

	_active_projectiles.append({
		"pos":            origin,
		"vel":            dir * stats.projectile_speed,
		"target":         target,
		"player":         player,
		"damage":         damage,
		"is_crit":        is_crit,
		"pierce":         maxi(0, stats.pierce),
		"max_range":      stats.range if stats.range > 0.0 else 2000.0,
		"travelled":      0.0,
		"radius":         ProjectileManager.DRAW_RADIUS,
		"color":          ProjectileManager.COLOR_CRIT if is_crit else ProjectileManager.COLOR_NORMAL,
		"los_timer":      0.0,
		"los_lost_timer": LOST_TARGET_TIME,
		"armor_pen":      stats.get_armor_pen(),
		"on_hit":         func(t: Enemy): _apply_on_hit_effects(t, player, is_crit),
	})

# ── targeting ─────────────────────────────────────────────────────────────────

func _find_nearest_enemy(player: CharacterBody2D, tilemap) -> Enemy:
	var use_range: bool  = stats.range > 0.0
	var range_sq:  float = stats.range * stats.range
	var best:      Enemy = null
	var best_dist: float = INF

	for node in player.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or not node is Enemy:
			continue
		var d: float = player.global_position.distance_squared_to(node.global_position)
		if use_range and d > range_sq:
			continue
		if not _has_los(player.global_position, node.global_position, tilemap):
			continue
		if d < best_dist:
			best_dist = d
			best      = node
	return best

func _find_next_target(from: Vector2, just_hit: Enemy, player: CharacterBody2D, tilemap) -> Enemy:
	var use_range: bool  = stats.range > 0.0
	var range_sq:  float = stats.range * stats.range
	var best:      Enemy = null
	var best_dist: float = INF

	for node in player.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or not node is Enemy:
			continue
		if node == just_hit:
			continue
		var d: float = from.distance_squared_to(node.global_position)
		if use_range and d > range_sq:
			continue
		if not _has_los(from, node.global_position, tilemap):
			continue
		if d < best_dist:
			best_dist = d
			best      = node
	return best

# ── line of sight ─────────────────────────────────────────────────────────────

func _has_los(from: Vector2, to: Vector2, tilemap) -> bool:
	var steps: int = maxi(1, int(from.distance_to(to) / (tilemap.TILE_SIZE.x * 0.5)))
	for i in range(1, steps):
		var sample: Vector2  = from.lerp(to, float(i) / float(steps))
		var cell:   Vector2i = tilemap.world_to_map(sample)
		if tilemap.tile_exists(cell):
			return false
	return true

# ── drawing — called by ProjectileManager._on_canvas_draw ────────────────────

func draw_projectiles(canvas: Node2D) -> void:
	var xform: Transform2D = canvas.get_global_transform().affine_inverse()
	for p in _active_projectiles:
		canvas.draw_circle(xform * p["pos"], p["radius"], p["color"])

# ── damage helpers ────────────────────────────────────────────────────────────

func _compute_damage(is_crit: bool) -> int:
	var base: float = maxf(1.0, stats.power)
	if not is_crit:
		return int(base)
	var mult: float = stats.crit_damage if stats.crit_damage > 0.0 else 2.0
	return int(base * mult)

func _roll_crit(player: CharacterBody2D) -> bool:
	if player.guaranteed_crits > 0:
		player.guaranteed_crits -= 1
		return true
	if stats.crit_chance <= 0.0:
		return false
	return randf() < stats.crit_chance

func _apply_on_hit_effects(target: Enemy, player: CharacterBody2D, is_crit: bool) -> void:
	if stats.knockback > 0.0:
		var dir: Vector2 = (target.global_position - player.global_position).normalized()
		target.apply_knockback(dir * stats.knockback)
	if stats.stun_duration > 0.0:
		target.apply_stun(stats.stun_duration)
	if stats.slow_amount > 0.0 and stats.slow_duration > 0.0:
		target.apply_slow(stats.slow_amount, stats.slow_duration)
	if stats.dot_damage > 0.0 and stats.dot_duration > 0.0:
		target.apply_dot(stats.dot_damage, stats.dot_duration)
	if stats.light_on_hit > 0.0:
		player.light += stats.light_on_hit
	if is_crit and stats.light_on_crit > 0.0:
		player.light += stats.light_on_crit
