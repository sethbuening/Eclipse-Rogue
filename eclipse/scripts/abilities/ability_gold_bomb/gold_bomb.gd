class_name GoldBomb
extends Node2D

const TRAVEL_SPEED: float = 400.0

var _target:     Vector2
var _stats:      AbilityStats
var _orb_potency: float
var _tilemap:    Node
var _main_stats: Array[String]
var _active:     bool              = false
var _anim:       AnimatedSprite2D  = null
var _player:     CharacterBody2D   = null

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_physics_process(false)
	if has_node("AnimatedSprite2D"):
		_anim         = $AnimatedSprite2D
		_anim.visible = false
		_anim.sprite_frames.set_animation_loop("explode", false)

func launch(spawn: Vector2, target: Vector2, stats: AbilityStats, orb_potency: float, tilemap: Node, main_stats: Array[String], player: CharacterBody2D) -> void:
	global_position = spawn
	_target      = target
	_stats       = stats
	_orb_potency = orb_potency
	_tilemap     = tilemap
	_main_stats  = main_stats
	_active      = true
	_player      = player
	reset_physics_interpolation()
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	var to_target: Vector2 = _target - global_position
	var dist:      float   = to_target.length()
	var step:      float   = TRAVEL_SPEED * delta
	ParticleManager.spawn_gold_bomb_trail(global_position)
	if dist <= step:
		global_position = _target
		set_physics_process(false)
		_explode()
	else:
		global_position += to_target.normalized() * step

func _explode() -> void:
	var pulse := GoldShockwave.acquire(get_parent())
	pulse.global_position = global_position
	pulse.reset_physics_interpolation()
	pulse.setup(_stats, _orb_potency, _player, _tilemap, _main_stats)
	if _anim != null:
		_anim.visible = true
		_anim.play("explode")
		_anim.animation_finished.connect(_finish, CONNECT_ONE_SHOT)
		if has_node("PointLight2D"):
			var duration: float = _anim.sprite_frames.get_frame_count("explode") / _anim.sprite_frames.get_animation_speed("explode")
			create_tween().tween_property($PointLight2D, "energy", 0.0, duration)
	else:
		_finish()

func _finish() -> void:
	queue_free()
