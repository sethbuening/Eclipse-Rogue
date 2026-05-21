class_name BasicAttackTraveller
extends Node

var _pos:          Vector2
var _dir:          Vector2
var _power:        float
var _mining_power: float
var _range:        float
var _speed:        float
var _tilemap:      Node
var _player:       Node
var _travelled:    float = 0.0

func init(pos: Vector2, dir: Vector2, power: float, range: float, speed: float, tilemap: Node, player: Node, mining_power: float) -> void:
	_pos          = pos
	_dir          = dir
	_power        = power
	_range        = range
	_speed        = speed
	_tilemap      = tilemap
	_player       = player
	_mining_power = mining_power

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	var step: float = _speed * delta
	_pos       += _dir * step
	_travelled += step

	ParticleManager.spawn_basic_attack_trail(_pos, _dir, _speed)

	var tile: Vector2i = _tilemap.world_to_map(_pos)
	if _tilemap.tile_exists(tile):
		_hit_tile(tile)
		return

	for hit in _get_bodies_at(_pos):
		var body: Object = hit["collider"]
		if body.has_method("take_damage"):
			body.take_damage(_power)
			_explode()
			return

	if _travelled >= _range:
		_explode()

func _hit_tile(tile: Vector2i) -> void:
	var died: bool = _tilemap.tile_health.get(tile, 1) <= int(_mining_power)
	_tilemap.damage_tile_silent(tile, int(_mining_power))
	var removed: Array[Vector2i] = []
	if died:
		removed.append(tile)
	_tilemap.flush_removed_tiles(removed)
	_explode()

func _explode() -> void:
	ParticleManager.spawn_basic_attack_explode(_pos)
	queue_free()

func _get_bodies_at(pos: Vector2) -> Array:
	var space:  PhysicsDirectSpaceState2D     = _player.get_world_2d().direct_space_state
	var shape:  CircleShape2D                 = CircleShape2D.new()
	shape.radius                              = 4.0
	var params: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	params.shape          = shape
	params.transform      = Transform2D(0.0, pos)
	params.exclude        = [_player.get_rid()]
	params.collision_mask = _player.collision_mask
	return space.intersect_shape(params)
