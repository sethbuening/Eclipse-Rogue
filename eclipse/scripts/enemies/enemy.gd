# enemy.gd
class_name Enemy
extends CharacterBody2D

@export var data:                     EnemyData
@export var min_spawn_distance_tiles: int = 15

var health:          int
var player:          CharacterBody2D
var tilemap_manager: Node = null

signal died(enemy: Enemy)

var _navigator: Node

# ── lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	health             = data.max_health
	_navigator         = load("res://scripts/pathfinding/enemy_navigator.gd").new()
	_navigator.name    = "EnemyNavigator"
	add_child(_navigator)

func initialize(p: CharacterBody2D, modifier: Util.Modifier = Util.Modifier.NONE) -> void:
	data   = data.duplicate()
	player = p
	_apply_modifier(modifier)
	# set speed after modifier is applied
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
	if NavManager._built:
		velocity = _navigator.navigate_toward(player.global_position, delta)
	else:
		velocity = (player.global_position - global_position).normalized() * data.speed
	move_and_slide()

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
