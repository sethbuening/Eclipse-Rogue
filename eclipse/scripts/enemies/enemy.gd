class_name Enemy
extends CharacterBody2D

@export var data:                     EnemyData
@export var min_spawn_distance_tiles: int = 15

const EnemyNavigatorScript = preload("res://scripts/pathfinding/enemy_navigator.gd")

var health:          int
var player:          CharacterBody2D
var tilemap_manager: Node = null

var _nearby_enemies: Dictionary = {}

signal died(enemy: Enemy)

var _navigator: EnemyNavigator

var _status: Dictionary = {}

var _attack_cooldown_remaining: float = 0.0

const KNOCKBACK_DECAY: float = 8.0

# ── lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	health      = data.max_health
	_navigator  = EnemyNavigatorScript.new()
	_navigator.name = "EnemyNavigator"
	motion_mode    = CharacterBody2D.MOTION_MODE_FLOATING
	collision_mask = collision_mask | 8
	add_child(_navigator)

	var sep_circle    := CircleShape2D.new()
	sep_circle.radius = data.sep_radius
	var sep_shape     := CollisionShape2D.new()
	sep_shape.shape   = sep_circle
	var sep_area      := Area2D.new()
	sep_area.name            = "SepArea"
	sep_area.collision_layer = 0
	sep_area.collision_mask  = 1 << 3
	sep_area.monitoring      = true
	sep_area.monitorable     = true
	sep_area.add_child(sep_shape)
	sep_area.body_entered.connect(_on_sep_body_entered)
	sep_area.body_exited.connect(_on_sep_body_exited)
	add_child(sep_area)

	add_to_group("enemies")

func initialize(p: CharacterBody2D, modifier: Util.Modifier = Util.Modifier.NONE) -> void:
	data   = data.duplicate()
	player = p
	_apply_modifier(modifier)
	_navigator.move_speed = data.speed
	_spawn()

# ── spawning ──────────────────────────────────────────────────────────────────

func _spawn() -> void:
	global_position = _find_spawn_position()
	reset_physics_interpolation()

func _find_spawn_position() -> Vector2:
	if tilemap_manager == null:
		return global_position
	var player_tile: Vector2i = tilemap_manager.world_to_map(player.global_position)
	for _attempt in range(40):
		var offset:    Vector2i = Vector2i(randi_range(-20, 20), randi_range(-20, 20))
		var candidate: Vector2i = player_tile + offset
		if not _in_playable_bounds(candidate):
			continue
		if abs(offset.x) + abs(offset.y) < min_spawn_distance_tiles:
			continue
		if not _is_clear(candidate):
			continue
		return tilemap_manager.map_to_world(candidate)
	return global_position

func _is_clear(map_pos: Vector2i) -> bool:
	if not tilemap_manager.is_air(map_pos):
		return false
	for neighbor: Vector2i in [
		map_pos + Vector2i( 0, -1),
		map_pos + Vector2i( 0,  1),
		map_pos + Vector2i(-1,  0),
		map_pos + Vector2i( 1,  0),
	]:
		if not tilemap_manager.is_air(neighbor):
			return false
	return true

func _in_playable_bounds(candidate: Vector2i) -> bool:
	var buf: int = tilemap_manager.BUFFER_TILES
	return (
		candidate.x >= buf and candidate.x < tilemap_manager.WIDTH  - buf and
		candidate.y >= buf and candidate.y < tilemap_manager.HEIGHT - buf
	)

# ── process ───────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if player == null:
		return
	z_index = tilemap_manager.get_z_for(global_position)
	_tick_status(delta)
	if not _status.has("stun"):
		_tick_behavior(delta)
		_tick_attack(delta)
		velocity = _compute_nav_velocity(delta)
		if _status.has("knockback"):
			velocity += _status["knockback"]["velocity"]
		move_and_slide()

## Override to run per-frame logic that isn't movement (e.g. healing, charging).
## Called every frame the enemy is not stunned, before velocity is applied.
func _tick_behavior(_delta: float) -> void:
	pass

## Override to change how this enemy moves.
## Status effects are handled by the base class — never replicate them here.
func _compute_nav_velocity(delta: float) -> Vector2:
	if NavManager._built:
		return _navigator.navigate_toward(player.global_position, delta) + _separation_velocity()
	return (player.global_position - global_position).normalized() * data.speed + _separation_velocity()

# ── attacking ─────────────────────────────────────────────────────────────────

## Ticks the melee attack cooldown and fires when in range.
## Projectile-based enemies should override _tick_behavior and set
## data.projectile_speed > 0 to bypass this.
func _tick_attack(delta: float) -> void:
	if data.projectile_speed > 0.0:
		return   # projectile subclass handles its own attack timing
	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)
	if _attack_cooldown_remaining > 0.0:
		return
	var dist: float = global_position.distance_to(player.global_position)
	if dist <= data.attack_range:
		_attack_player()

func _attack_player() -> void:
	_attack_cooldown_remaining = data.attack_cooldown

	# Roll crit before armour so the full raw value is used for the crit multiply.
	var is_crit:    bool = randf() < data.crit_chance
	var raw_damage: int  = data.damage
	if is_crit:
		raw_damage = int(float(raw_damage) * data.crit_damage_mult)

	# Pass this enemy's armor_penetration so the player can factor it in.
	player.take_damage(raw_damage, data.armor_penetration, is_crit)

## Convenience for projectile subclasses — call this from the projectile's
## on_hit callback instead of _attack_player().
func deal_damage_to_player(raw_damage: int, is_crit: bool = false) -> void:
	player.take_damage(raw_damage, data.armor_penetration, is_crit)

# ── separation ────────────────────────────────────────────────────────────────

func _on_sep_body_entered(body: Node2D) -> void:
	if body != self and body is Enemy:
		_nearby_enemies[body.get_instance_id()] = body

func _on_sep_body_exited(body: Node2D) -> void:
	_nearby_enemies.erase(body.get_instance_id())

func _separation_velocity() -> Vector2:
	var push := Vector2.ZERO
	for other in _nearby_enemies.values():
		if not is_instance_valid(other) or other == self:
			continue
		var away: Vector2 = global_position - other.global_position
		var dist: float   = away.length()
		away = away.normalized() if dist > 0.001 else Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
		push += away * (1.0 - clampf(dist / data.sep_radius, 0.0, 1.0)) * data.speed * data.sep_force
	return push

## Returns a target position offset so the enemy hovers at preferred_range
## from the destination rather than walking into it.
func _range_offset_target(target: Vector2, preferred: float) -> Vector2:
	if preferred <= 0.0:
		return target
	var to_target: Vector2 = target - global_position
	var dist:      float   = to_target.length()
	if dist <= preferred:
		return global_position   # already close enough, hold position
	return target - to_target.normalized() * preferred

# ── modifiers ─────────────────────────────────────────────────────────────────

func _apply_modifier(modifier: Util.Modifier) -> void:
	match modifier:
		Util.Modifier.FAST:
			data.speed *= 1.6

# ── combat (incoming) ─────────────────────────────────────────────────────────

## Main entry point for all incoming damage.
##
## armor_penetration — flat armor the attacker ignores (from their EnemyData or
##                     a player ability). Defaults to 0 so callers that don't
##                     care about armor (e.g. plain AoE) can omit it.
##
## Damage pipeline:
##   1. Subtract armor, offset by penetration.  Minimum 1 so armor never
##      makes an enemy fully immune to non-zero hits.
##   2. Apply flat percentage damage_reduction (resistances layer).
##   Result is always at least 1.
func take_damage(amount: int, armor_penetration: int = 0, is_crit: bool = false) -> void:
	# Step 1 — armor
	var after_armor: int = amount - maxi(0, data.armor - armor_penetration)
	after_armor = maxi(1, after_armor)   # armor never negates a hit entirely

	# Step 2 — percentage reduction (elemental resistances etc. feed here)
	var reduced: int = maxi(1, int(float(after_armor) * (1.0 - data.damage_reduction)))

	health -= reduced
	DamageNumbers.spawn(global_position + Vector2(0, -16), reduced, is_crit)
	if health <= 0:
		die()

func die() -> void:
	ItemManager.spawn_light_orb(global_position)
	emit_signal("died", self)
	queue_free()

# ── status effects ────────────────────────────────────────────────────────────

func apply_stun(duration: float) -> void:
	var reduced: float = duration * (1.0 - data.stun_resistance)
	if reduced <= 0.0:
		return
	if not _status.has("stun") or reduced > _status["stun"]["duration"]:
		_status["stun"] = { "duration": reduced }

func apply_slow(amount: float, duration: float) -> void:
	var reduced: float = clampf(amount, 0.0, 1.0) * (1.0 - data.slow_resistance)
	if reduced <= 0.0:
		return
	if not _status.has("slow") or reduced >= _status["slow"]["amount"]:
		_status["slow"]       = { "duration": duration, "amount": reduced }
		_navigator.move_speed = data.speed * (1.0 - reduced)

func apply_dot(dps: float, duration: float) -> void:
	var reduced_dps: float = dps * (1.0 - data.dot_resistance)
	if reduced_dps <= 0.0:
		return
	if _status.has("dot"):
		var incoming_weight: float = reduced_dps * duration
		var existing_weight: float = _status["dot"]["dps"] * _status["dot"]["duration"]
		if incoming_weight > existing_weight:
			_status["dot"]["dps"]      = reduced_dps
			_status["dot"]["duration"] = duration
	else:
		_status["dot"] = { "duration": duration, "dps": reduced_dps, "_accum": 0.0 }

func apply_knockback(impulse: Vector2) -> void:
	var reduced: Vector2 = impulse * (1.0 - data.knockback_resistance)
	if reduced.length_squared() <= 0.0:
		return
	if _status.has("knockback"):
		_status["knockback"]["velocity"] += reduced
	else:
		_status["knockback"] = { "velocity": reduced }

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
			take_damage(whole)   # DoT has no armor penetration
		if not is_inside_tree():
			return
		if dot["duration"] <= 0.0:
			_status.erase("dot")

	if _status.has("knockback"):
		_status["knockback"]["velocity"] -= _status["knockback"]["velocity"] * KNOCKBACK_DECAY * delta
		if _status["knockback"]["velocity"].length_squared() < 1.0:
			_status.erase("knockback")
