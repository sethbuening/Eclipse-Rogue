class_name GoldBomb
extends Node2D
const ShockwaveScene = preload("res://scenes/abilities/gold_shockwave.tscn")
const TRAVEL_SPEED: float = 400.0
const ECHO_COUNT:   int   = 12
var _target:  Vector2
var _stats:   AbilityStats
var _power:   float
var _arrived: bool = false

func setup(target: Vector2, stats: AbilityStats, power: float) -> void:
	_target = target
	_stats  = stats
	_power  = power
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _physics_process(delta: float) -> void:
	if _arrived:
		return
	var to_target: Vector2 = _target - global_position
	var dist:      float   = to_target.length()
	var step:      float   = TRAVEL_SPEED * delta
	ParticleManager.spawn_gold_bomb_trail(global_position)
	if dist <= step:
		global_position = _target
		_arrived = true
		_explode()
	else:
		global_position += to_target.normalized() * step

func _explode() -> void:
	_apply_hits(global_position, _stats.aoe_radius, _stats.crit_chance)
	var pulse := ShockwaveScene.instantiate() as GoldShockwave
	get_parent().add_child(pulse)
	pulse.global_position = global_position
	pulse.setup(_stats, _power, _stats.crit_chance)
	if has_node("AnimatedSprite2D"):
		var anim := $AnimatedSprite2D as AnimatedSprite2D
		anim.visible = true
		anim.sprite_frames.set_animation_loop("explode", false)
		anim.play("explode")
		anim.animation_finished.connect(queue_free)
		if has_node("PointLight2D"):
			var duration: float = anim.sprite_frames.get_frame_count("explode") / anim.sprite_frames.get_animation_speed("explode")
			var tween := create_tween()
			tween.tween_property($PointLight2D, "energy", 0.0, duration)
	else:
		if has_node("PointLight2D"):
			$PointLight2D.energy = 0.0
		queue_free()

func _apply_hits(origin: Vector2, radius: float, crit_chance: float) -> void:
	var space := get_world_2d().direct_space_state
	var query  := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius        = radius
	query.shape          = circle
	query.transform      = Transform2D(0.0, origin)
	query.collision_mask = 8
	for hit in space.intersect_shape(query, 32):
		var body := hit["collider"] as Node2D
		if not body is Enemy:
			continue
		var is_crit: bool  = _stats.roll_crit()
		var damage:  float = _stats.get_power(is_crit) * _power
		(body as Enemy).take_damage(int(damage))
