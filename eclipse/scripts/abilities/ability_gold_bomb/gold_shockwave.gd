class_name GoldShockwave
extends Node2D

const ShockwaveScene  := preload("res://scenes/abilities/gold_shockwave.tscn")
const MAX_RANGE:        float = 90.0
const TILES_PER_FRAME:  int   = 10
const POOL_POSITION  := Vector2(-99999, -99999)
const POOL_SIZE:        int   = 4

static var _pool: Array[GoldShockwave] = []

var _stats:       AbilityStats
var _orb_potency: float
var _main_stats:  Array[String]
var _tilemap:     Node = null
var _active:      bool = false
var _mining:      bool = false
var _player:      CharacterBody2D = null

var _circle: CircleShape2D                 = CircleShape2D.new()
var _query:  PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
var _anim:   AnimatedSprite2D              = null

static func prewarm(count: int, parent: Node) -> void:
	for i in range(count):
		var s := ShockwaveScene.instantiate() as GoldShockwave
		_init_instance(s)
		parent.add_child(s)
		_pool.append(s)

static func acquire(parent: Node) -> GoldShockwave:
	for s in _pool:
		if not s._active:
			return s
	var s := ShockwaveScene.instantiate() as GoldShockwave
	_init_instance(s)
	parent.add_child(s)
	_pool.append(s)
	return s

static func _init_instance(s: GoldShockwave) -> void:
	s.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	s.global_position            = POOL_POSITION
	s._circle.radius             = MAX_RANGE
	s._query.shape               = s._circle
	s._query.collision_mask      = 8

func _ready() -> void:
	if has_node("AnimatedSprite2D"):
		_anim         = $AnimatedSprite2D
		_anim.visible = false
		_anim.frame   = 0

func setup(stats: AbilityStats, orb_potency: float, player: CharacterBody2D, tilemap: Node = null, main_stats: Array[String] = []) -> void:
	_stats       = stats
	_orb_potency = orb_potency
	_main_stats  = main_stats
	_tilemap     = tilemap
	_active      = true
	_mining      = false
	_player      = player

	if _anim != null:
		_anim.frame   = 0
		_anim.visible = true
		_anim.play("travel")
		_anim.animation_finished.connect(_finish, CONNECT_ONE_SHOT)
	else:
		_finish()

	reset_physics_interpolation()
	_apply_hits(global_position)

	if _tilemap != null:
		_mine_tiles_async(global_position)

func _apply_hits(origin: Vector2) -> void:
	_query.transform = Transform2D(0.0, origin)
	var space        := get_world_2d().direct_space_state

	for hit in space.intersect_shape(_query, 32):
		var body := hit["collider"] as Node2D
		if not body is Enemy:
			continue
		var is_crit:      bool  = _stats.roll_crit(_player)
		var scaled_power: float = _stats.get_stat("power", _orb_potency, _main_stats)
		var damage:       float = scaled_power * (_stats.crit_damage if is_crit else 1.0)
		(body as Enemy).take_damage(int(damage), is_crit)

func _mine_tiles_async(origin: Vector2) -> void:
	_mining           = true
	var tile_size:     float         = _tilemap.TILE_SIZE.x
	var map_center:    Vector2i      = _tilemap.world_to_map(origin)
	var outer_tile:    int           = int(MAX_RANGE / tile_size) + 1
	var range_sq:      float         = MAX_RANGE * MAX_RANGE
	var mining_power:  int           = int(_stats.get_stat("mining_power", _orb_potency, _main_stats))
	var ops:           int           = 0
	var removed:       Array[Vector2i] = []

	for dx in range(-outer_tile, outer_tile + 1):
		for dy in range(-outer_tile, outer_tile + 1):
			if dx * dx + dy * dy > outer_tile * outer_tile:
				continue
			var map_pos: Vector2i = map_center + Vector2i(dx, dy)
			if not _tilemap.tile_exists(map_pos):
				continue
			var world_pos: Vector2 = _tilemap.map_to_world(map_pos)
			var diff:      Vector2 = world_pos - origin
			if diff.x * diff.x + diff.y * diff.y > range_sq:
				continue

			ops += 1
			if ops >= TILES_PER_FRAME:
				ops = 0
				await get_tree().process_frame
				if not _active:
					if not removed.is_empty():
						_tilemap.flush_removed_tiles(removed)
					_mining = false
					return

			var died: bool = _tilemap.tile_health.get(map_pos, 1) <= mining_power
			if died:
				removed.append(map_pos)
			_tilemap.damage_tile_silent(map_pos, mining_power)

	_tilemap.flush_removed_tiles(removed)
	_mining = false

func _finish() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	if has_node("PointLight2D"):
		tween.parallel().tween_property($PointLight2D, "energy", 0.0, 0.3)
	tween.tween_callback(_return_to_pool)

func _return_to_pool() -> void:
	_active  = false
	_mining  = false
	if _anim != null:
		_anim.stop()
		_anim.visible = false
		_anim.frame   = 0
	if has_node("PointLight2D"):
		$PointLight2D.energy = 1.0
	modulate.a      = 1.0
	global_position = POOL_POSITION
	reset_physics_interpolation()
