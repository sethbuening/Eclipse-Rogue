# enemy.gd
class_name Enemy
extends CharacterBody2D

@export var data:                     EnemyData
@export var min_spawn_distance_tiles: int = 15

const EnemyNavigatorScript = preload("res://scripts/pathfinding/enemy_navigator.gd")

var health:          int
var player:          CharacterBody2D
var tilemap_manager: Node = null

var _sep_radius:     float      = 64.0
var _nearby_enemies: Dictionary = {}

signal died(enemy: Enemy)

var _navigator: EnemyNavigator

# ── lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	health         = data.max_health
	_navigator     = EnemyNavigatorScript.new()
	_navigator.name = "EnemyNavigator"
	motion_mode    = CharacterBody2D.MOTION_MODE_FLOATING
	collision_mask = collision_mask | 8
	add_child(_navigator)

	var sep_circle    := CircleShape2D.new()
	sep_circle.radius = _sep_radius
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
	var radius: int = 20
	for _attempt in range(40):
		var offset:    Vector2i = Vector2i(randi_range(-radius, radius), randi_range(-radius, radius))
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

	var nav_vel: Vector2
	if NavManager._built:
		nav_vel = _navigator.navigate_toward(player.global_position, delta)
	else:
		nav_vel = (player.global_position - global_position).normalized() * data.speed

	velocity = nav_vel + _separation_velocity()
	move_and_slide()

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
		if dist < 0.001:
			away = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
		else:
			away = away.normalized()
		# Falloff: strong when touching, zero at _sep_radius
		var t: float = 1.0 - clampf(dist / _sep_radius, 0.0, 1.0)
		push += away * t * data.speed
	return push

# ── modifiers ─────────────────────────────────────────────────────────────────

func _apply_modifier(modifier: Util.Modifier) -> void:
	match modifier:
		Util.Modifier.FAST:
			data.speed *= 1.6
		_:
			pass

# ── combat ────────────────────────────────────────────────────────────────────

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		die()

func die() -> void:
	emit_signal("died", self)
	queue_free()

func Log(msg: Variant) -> void:
	print("[Enemy.gd | " + data.id + "] " + str(msg))
