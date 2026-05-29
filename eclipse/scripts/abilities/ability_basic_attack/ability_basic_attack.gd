class_name AbilityBasicAttack
extends AbilityData

var _cooldown_remaining: float = 0.0
var _active_projectiles: Array = []   # untyped — typed Array validates refs on iteration and crashes
var tilemap: Node
var player: CharacterBody2D

const LOS_INTERVAL:     float = 0.1
const LOST_TARGET_TIME: float = 0.3

# ── tick ──────────────────────────────────────────────────────────────────────

func tick(ctx: Dictionary) -> void:
	super.tick(ctx)
	if stats == null:
		push_error("AbilityBasicAttack: stats is null")
		return

	var delta: float = ctx["delta"]
	if not player:
		player  = ctx["player"]
	if not tilemap:
		tilemap = player.get_node("%TilemapManager")

	_tick_bullets(delta, tilemap)

	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if _cooldown_remaining > 0.0:
		return

	var target: Enemy = _find_nearest_enemy(player, tilemap)
	if target == null:
		return

	if get_stat("projectile_speed") > 0.0:
		_spawn_bullet(player.global_position, target, player)
	else:
		var is_crit: bool = stats.roll_crit(player)
		var damage:  int  = _compute_damage(is_crit)
		target.take_damage(damage, stats.get_armor_pen(), is_crit)
		apply_hit_effects(target, player, is_crit)

	_cooldown_remaining = maxf(0.05, get_stat("cooldown"))

# ── bullet tick ───────────────────────────────────────────────────────────────

func _tick_bullets(delta: float, tilemap) -> void:
	var alive: Array = []
	for p in _active_projectiles:
		var step: Vector2 = p["vel"] * delta
		p["pos"]       += step
		p["travelled"] += step.length()

		# Store trail history (last ~6 positions for streak rendering)
		p["trail"].push_front(p["pos"])
		if p["trail"].size() > 6:
			p["trail"].pop_back()

		if p["travelled"] >= p["max_range"]:
			continue

		# Hit detection — bullets hit any enemy within threshold
		var hit_this_frame: bool = false
		var enemies: Array = player.get_tree().get_nodes_in_group("enemies")
		for node in enemies:
			if not is_instance_valid(node) or not node is Enemy:
				continue
			var id: int = node.get_instance_id()
			if id in p["hit_ids"]:
				continue
			var dist_sq: float   = p["pos"].distance_squared_to(node.global_position)
			var threshold: float = 10.0
			if dist_sq <= threshold * threshold:
				node.take_damage(p["damage"], p["armor_pen"], p["is_crit"])
				if p["on_hit"].is_valid():
					p["on_hit"].call(node)
				p["hit_ids"].append(id)

				if p["pierce"] <= 0:
					# Final hit — spawn explosion flash
					ProjectileManager._spawn_bullet_explosion(p["pos"], p["color"])
					hit_this_frame = true
					break
				else:
					# Piercing hit — small spark, keep going
					ProjectileManager._spawn_flash(p["pos"], p["color"])
					p["pierce"] -= 1

		if not hit_this_frame:
			alive.append(p)

	_active_projectiles = alive

# ── spawn ─────────────────────────────────────────────────────────────────────

func _spawn_bullet(origin: Vector2, target: Enemy, player: CharacterBody2D) -> void:
	var is_crit: bool = stats.roll_crit(player)
	var damage:  int  = _compute_damage(is_crit)
	var dir:     Vector2 = (target.global_position - origin).normalized()

	var speed: float = maxf(0.0, get_stat("projectile_speed"))
	_active_projectiles.append({
		"pos":       origin,
		"vel":       dir * speed,
		"dir":       dir,
		"trail":     [origin],
		"damage":    damage,
		"is_crit":   is_crit,
		"pierce":    maxi(0, int(get_stat("pierce"))),
		"max_range": get_stat("range") if get_stat("range") > 0.0 else 2000.0,
		"travelled": 0.0,
		"hit_ids":   [],
		"color":     ProjectileManager.COLOR_CRIT if is_crit else Color(1.0, 1.0, 1.0, 1.0),
		"armor_pen": stats.get_armor_pen(),
		"on_hit":    func(t: Enemy): apply_hit_effects(t, player, is_crit),
	})

# ── targeting ─────────────────────────────────────────────────────────────────

func _find_nearest_enemy(player: CharacterBody2D, tilemap) -> Enemy:
	var use_range: bool  = get_stat("range") > 0.0
	var range_sq:  float = get_stat("range") * get_stat("range") if use_range else 0.0
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
		var trail: Array = p["trail"]
		if trail.size() < 2:
			canvas.draw_circle(xform * p["pos"], 1.5, p["color"])
			continue

		# Draw the streak as a series of lines fading from tip to tail
		var segments: int = trail.size() - 1
		for i in range(segments):
			var from_pt: Vector2 = xform * trail[i]
			var to_pt:   Vector2 = xform * trail[i + 1]
			var t:     float = 1.0 - float(i) / float(segments)
			var alpha: float = t * t
			var width: float = lerpf(0.5, 2.5, t)
			var col:   Color = Color(p["color"].r, p["color"].g, p["color"].b, alpha)
			canvas.draw_line(from_pt, to_pt, col, width, true)

		# Bright tip glow
		var tip_glow: Color = Color(p["color"].r, p["color"].g, p["color"].b, 0.9)
		canvas.draw_circle(xform * p["pos"], 2.0, tip_glow)

# ── damage helpers ────────────────────────────────────────────────────────────

func _compute_damage(is_crit: bool) -> int:
	return int(maxf(1.0, stats.get_power(is_crit)))
