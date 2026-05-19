class_name GoldShockwave
extends Node2D

const ShockwaveScene := preload("res://scenes/abilities/gold_shockwave.tscn")

const SPEED:           float = 250.0
const MAX_RANGE:       float = 200.0
const MAX_MINI_SPAWNS: int   = 3

var _stats:        AbilityStats
var _power:        float
var _crit_chance:  float
var _is_mini:      bool       = false
var _radius:       float      = 0.0
var _hit_enemies:  Dictionary = {}
var _mini_spawned: int        = 0

func setup(stats: AbilityStats, power: float, crit_chance: float, is_mini: bool = false) -> void:
	_stats       = stats
	_power       = power
	_crit_chance = crit_chance
	_is_mini     = is_mini
	if has_node("AnimatedSprite2D"):
		$AnimatedSprite2D.play("travel")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _physics_process(delta: float) -> void:
	var prev_radius: float = _radius
	_radius += SPEED * delta

	# check a thin ring between prev and current radius
	var space := get_world_2d().direct_space_state
	var query  := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius        = _radius
	query.shape          = circle
	query.transform      = Transform2D(0.0, global_position)
	query.collision_mask = 8

	for hit in space.intersect_shape(query, 32):
		var body := hit["collider"] as Node2D
		if not body is Enemy:
			continue
		var id := body.get_instance_id()
		if _hit_enemies.has(id):
			continue
		# only hit enemies that are within the ring (outside prev radius)
		if body.global_position.distance_to(global_position) < prev_radius:
			continue
		_hit_enemies[id] = true
		var is_crit: bool  = _stats.roll_crit()
		var damage:  float = _stats.get_power(is_crit) * _power
		(body as Enemy).take_damage(int(damage))
		if not _is_mini and _mini_spawned < MAX_MINI_SPAWNS:
			_mini_spawned += 1
			_spawn_mini_shockwave(body.global_position)

	# scale the sprite to match expanding radius
	if has_node("AnimatedSprite2D"):
		var scale_t: float = _radius / MAX_RANGE
		$AnimatedSprite2D.scale = Vector2.ONE * scale_t

	if _radius >= MAX_RANGE:
		_finish()

func _spawn_mini_shockwave(origin: Vector2) -> void:
	var mini := ShockwaveScene.instantiate() as GoldShockwave
	get_parent().add_child(mini)
	mini.global_position = origin
	mini.setup(_stats, _power * 0.4, _crit_chance * 0.5, true)

func _finish() -> void:
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	if has_node("PointLight2D"):
		tween.parallel().tween_property($PointLight2D, "energy", 0.0, 0.3)
	tween.tween_callback(queue_free)
