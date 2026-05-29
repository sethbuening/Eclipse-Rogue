class_name Enemy
extends Node

# ── exports ───────────────────────────────────────────────────────────────────

@export var data:                     EnemyData
@export var min_spawn_distance_tiles: int = 15

# ── constants ─────────────────────────────────────────────────────────────────

const ENEMY_RADIUS:    float = 8.0
const KNOCKBACK_DECAY: float = 8.0
const MIN_SEPARATION:  float = ENEMY_RADIUS * 2.0   # hard floor: enemies can never be closer than this

const NavigatorScript = preload("res://scripts/pathfinding/enemy_navigator.gd")

# ── public state ──────────────────────────────────────────────────────────────

var health:          int
var global_position: Vector2 = Vector2.ZERO
var player:          CharacterBody2D
var tilemap:         Node = null

signal died(enemy: Enemy)

# ── private state ─────────────────────────────────────────────────────────────

var _navigator:       EnemyNavigator
var _velocity:        Vector2    = Vector2.ZERO
var _status:          Dictionary = {}
var _attack_cooldown: float      = 0.0

# z-index is visual — updated in tick_move on a timer, not every frame
var _z_timer:        float = 0.0
var _z_update_every: float = 0.5   # seconds between z-index updates
var _z_offset:       float = 0.0   # stagger offset so enemies don't all update at once

# ── setup ─────────────────────────────────────────────────────────────────────

func setup(ai_tick_rate: float) -> void:
	health          = data.max_health
	_z_update_every = ai_tick_rate * 10.0   # update z once per 10 AI ticks
	_z_offset       = randf() * _z_update_every
	_navigator      = NavigatorScript.new()
	_navigator.name = "Navigator"
	add_child(_navigator)
	add_to_group("enemies")

func initialize(p: CharacterBody2D, modifier: Util.Modifier = Util.Modifier.NONE) -> void:
	data   = data.duplicate()
	player = p
	_apply_modifier(modifier)
	_navigator.move_speed = data.speed
	global_position       = _find_spawn_position()

# ── tick API (called by EnemyManager) ────────────────────────────────────────

## Runs every frame. Moves the enemy and syncs visuals.
func tick_move(delta: float) -> void:
	if player == null:
		return
	var motion: Vector2 = _velocity
	if _status.has("knockback"):
		motion += _status["knockback"]["velocity"]
	_move(motion, delta)
	_sync_children()

	# z-index is purely visual — update infrequently and staggered across enemies
	_z_timer += delta
	if _z_timer >= _z_update_every + _z_offset:
		_z_timer  = 0.0
		_z_offset = 0.0   # only apply offset on first tick, then lock to interval
		_update_z_index()

## Runs at fixed AI rate (set by EnemyManager). Handles decisions and status.
func tick_ai(delta: float) -> void:
	_tick_status(delta)
	if _status.has("stun"):
		return

	_tick_behavior(delta)
	_tick_attack(delta)

	var desired: Vector2 = _navigator.navigate_toward(player.global_position, delta, true) \
						 + _separation_velocity()
	_velocity = _velocity.lerp(desired, data.turn_speed * delta)

## Override in subclasses for custom AI-tick behavior (healing, charging, etc).
func _tick_behavior(_delta: float) -> void:
	pass

# ── movement ──────────────────────────────────────────────────────────────────

func _move(velocity: Vector2, delta: float) -> void:
	var motion: Vector2 = velocity * delta
	if motion.length_squared() < 0.01:
		return
	global_position.x += motion.x
	_resolve_tiles(true)
	global_position.y += motion.y
	_resolve_tiles(false)
	_resolve_enemies()

func _resolve_tiles(x_axis: bool) -> void:
	if tilemap == null:
		return

	var half:   float    = tilemap.TILE_SIZE.x * 0.5
	var center: Vector2i = tilemap.world_to_map(global_position)
	var r_sq:   float    = ENEMY_RADIUS * ENEMY_RADIUS

	for offset in [
		Vector2i( 0,  0), Vector2i( 1,  0), Vector2i(-1,  0),
		Vector2i( 0,  1), Vector2i( 0, -1),
		Vector2i( 1,  1), Vector2i(-1,  1), Vector2i( 1, -1), Vector2i(-1, -1),
	]:
		var tile: Vector2i = center + offset
		if not tilemap.tile_exists(tile):
			continue

		var tile_center: Vector2 = tilemap.map_to_world(tile)
		var closest:     Vector2 = global_position.clamp(
			tile_center - Vector2(half, half),
			tile_center + Vector2(half, half)
		)
		var diff:    Vector2 = global_position - closest
		var dist_sq: float   = diff.length_squared()
		if dist_sq >= r_sq:
			continue

		var normal: Vector2
		if dist_sq < 0.0001:
			var away: Vector2 = global_position - tile_center
			normal = away.normalized() if away.length_squared() > 0.0001 else Vector2(1, 0)
		else:
			normal = diff / sqrt(dist_sq)

		var push: float = ENEMY_RADIUS - sqrt(dist_sq)
		if x_axis:
			global_position.x += normal.x * push
		else:
			global_position.y += normal.y * push

	var play_radius_world: float = (tilemap.WIDTH - tilemap.BUFFER_TILES) / 2.0 * tilemap.TILE_SIZE.x * tilemap.get_parent().scale.x
	var dist: float = global_position.length()
	if dist > play_radius_world:
		global_position = global_position / dist * play_radius_world

func _resolve_enemies() -> void:
	for other in EnemyManager.get_nearby_enemies(global_position, MIN_SEPARATION):
		if not is_instance_valid(other) or other == self:
			continue
		var away: Vector2 = global_position - other.global_position
		var d_sq: float   = away.length_squared()
		if d_sq >= MIN_SEPARATION * MIN_SEPARATION:
			continue
		if d_sq < 0.0001:
			global_position += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
			continue
		var dist: float = sqrt(d_sq)
		# push this enemy out by half the overlap; the other enemy handles its own half
		global_position += (away / dist) * (MIN_SEPARATION - dist) * 0.5

# ── separation ────────────────────────────────────────────────────────────────

func _separation_velocity() -> Vector2:
	var push:     Vector2 = Vector2.ZERO
	var sep_r:    float   = data.sep_radius
	var sep_r_sq: float   = sep_r * sep_r

	for other in EnemyManager.get_nearby_enemies(global_position, sep_r):
		if not is_instance_valid(other) or other == self:
			continue
		var away: Vector2 = global_position - other.global_position
		var d_sq: float   = away.length_squared()
		if d_sq >= sep_r_sq:
			continue
		if d_sq < 0.0001:
			push += Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * data.speed * data.sep_force
			continue
		var dist: float = sqrt(d_sq)
		push += (away / dist) * (1.0 - dist / sep_r) * data.speed * data.sep_force

	return push

# ── attack ────────────────────────────────────────────────────────────────────

func _tick_attack(delta: float) -> void:
	if data.projectile_speed > 0.0:
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if _attack_cooldown > 0.0:
		return
	if global_position.distance_squared_to(player.global_position) <= data.attack_range * data.attack_range:
		_attack_cooldown  = data.attack_cooldown
		var is_crit: bool = randf() < data.crit_chance
		var damage:  int  = data.damage
		if is_crit:
			damage = int(damage * data.crit_damage_mult)
		player.take_damage(damage, data.armor_penetration, is_crit)

func deal_damage_to_player(raw_damage: int, is_crit: bool = false) -> void:
	player.take_damage(raw_damage, data.armor_penetration, is_crit)

# ── incoming damage ───────────────────────────────────────────────────────────

func take_damage(amount: int, armor_pen: int = 0, is_crit: bool = false) -> void:
	var after_armor: int = maxi(1, amount - maxi(0, data.armor - armor_pen))
	var reduced:     int = maxi(1, int(after_armor * (1.0 - data.damage_reduction)))
	health -= reduced
	DamageNumbers.spawn(global_position + Vector2(0, -16), reduced, is_crit)
	if health <= 0:
		die()

func die() -> void:
	ItemManager.spawn_xp(global_position)
	emit_signal("died", self)
	queue_free()

# ── status effects ────────────────────────────────────────────────────────────

func apply_stun(duration: float) -> void:
	var d: float = duration * (1.0 - data.stun_resistance)
	if d > 0.0 and d > _status.get("stun", {}).get("duration", 0.0):
		_status["stun"] = { "duration": d }

func apply_slow(amount: float, duration: float) -> void:
	var a: float = clampf(amount, 0.0, 1.0) * (1.0 - data.slow_resistance)
	if a <= 0.0:
		return
	if not _status.has("slow") or a >= _status["slow"]["amount"]:
		_status["slow"]       = { "duration": duration, "amount": a }
		_navigator.move_speed = data.speed * (1.0 - a)

func apply_dot(dps: float, duration: float) -> void:
	var d: float = dps * (1.0 - data.dot_resistance)
	if d <= 0.0:
		return
	if not _status.has("dot") or d * duration > _status["dot"]["dps"] * _status["dot"]["duration"]:
		_status["dot"] = { "duration": duration, "dps": d, "_accum": 0.0 }

func apply_knockback(impulse: Vector2) -> void:
	var v: Vector2 = impulse * (1.0 - data.knockback_resistance)
	if v.length_squared() <= 0.0:
		return
	if _status.has("knockback"):
		_status["knockback"]["velocity"] += v
	else:
		_status["knockback"] = { "velocity": v }

func _tick_status(delta: float) -> void:
	if _status.has("stun"):
		_status["stun"]["duration"] -= delta
		if _status["stun"]["duration"] <= 0.0:
			_status.erase("stun")

	if _status.has("slow"):
		_status["slow"]["duration"] -= delta
		if _status["slow"]["duration"] <= 0.0:
			_status.erase("slow")
			_navigator.move_speed = data.speed

	if _status.has("dot"):
		var dot: Dictionary = _status["dot"]
		dot["duration"] -= delta
		dot["_accum"]   += dot["dps"] * delta
		var whole: int   = int(dot["_accum"])
		if whole > 0:
			dot["_accum"] -= whole
			take_damage(whole)
		if not is_inside_tree():
			return
		if dot["duration"] <= 0.0:
			_status.erase("dot")

	if _status.has("knockback"):
		_status["knockback"]["velocity"] -= _status["knockback"]["velocity"] * KNOCKBACK_DECAY * delta
		if _status["knockback"]["velocity"].length_squared() < 1.0:
			_status.erase("knockback")

# ── helpers ───────────────────────────────────────────────────────────────────

func _apply_modifier(modifier: Util.Modifier) -> void:
	if modifier == Util.Modifier.FAST:
		data.speed *= 1.6

func _range_offset_target(target: Vector2, preferred_range: float) -> Vector2:
	if preferred_range <= 0.0:
		return target
	var to_target: Vector2 = target - global_position
	var dist:      float   = to_target.length()
	return global_position if dist <= preferred_range else target - to_target / dist * preferred_range

func _sync_children() -> void:
	for child in get_children():
		if child is Node2D:
			child.global_position = global_position

func _update_z_index() -> void:
	var z: int = tilemap.get_z_for(global_position)
	for child in get_children():
		if child is Node2D:
			child.z_index = z

# ── spawn ─────────────────────────────────────────────────────────────────────

func _find_spawn_position() -> Vector2:
	if tilemap == null:
		return player.global_position
	var origin: Vector2i = tilemap.world_to_map(player.global_position)

	for _i in range(40):
		var off: Vector2i = Vector2i(randi_range(-20, 20), randi_range(-20, 20))
		var c:   Vector2i = origin + off
		if not _in_bounds(c) or abs(off.x) + abs(off.y) < min_spawn_distance_tiles:
			continue
		if _is_clear(c):
			return tilemap.map_to_world(c)

	for _i in range(40):
		var off: Vector2i = Vector2i(randi_range(-25, 25), randi_range(-25, 25))
		var c:   Vector2i = origin + off
		if not _in_bounds(c) or abs(off.x) + abs(off.y) < min_spawn_distance_tiles:
			continue
		if tilemap.is_air(c):
			return tilemap.map_to_world(c)

	push_warning("[Enemy] No valid spawn for %s" % data.id)
	return player.global_position

func _is_clear(pos: Vector2i) -> bool:
	if not tilemap.is_air(pos):
		return false
	for nb in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
		if not tilemap.is_air(pos + nb):
			return false
	return true

func _in_bounds(c: Vector2i) -> bool:
	var cx: float = tilemap.WIDTH  / 2.0
	var cy: float = tilemap.HEIGHT / 2.0
	var play_radius: float = (tilemap.WIDTH - tilemap.BUFFER_TILES) / 2.0
	var dx: float = float(c.x) - cx
	var dy: float = float(c.y) - cy
	return sqrt(dx * dx + dy * dy) < play_radius
