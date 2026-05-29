class_name EnemyNavigator
extends Node

@export var move_speed:     float = 60.0
@export var stuck_timeout:  float = 0.5

var _parent:        Enemy   = null
var _last_position: Vector2 = Vector2.ZERO
var _stuck_timer:   float   = 0.0
var _direct_timer:  float   = 0.0

func _ready() -> void:
	_parent = get_parent() as Enemy
	if _parent == null:
		push_error("EnemyNavigator must be a child of an Enemy")

func navigate_toward(target: Vector2, delta: float, use_flow: bool = true) -> Vector2:
	if _parent == null:
		return Vector2.ZERO

	var pos: Vector2 = _parent.global_position

	_stuck_timer += delta
	if _stuck_timer >= stuck_timeout:
		_stuck_timer = 0.0
		if pos.distance_squared_to(_last_position) < 4.0:
			_direct_timer = 0.35
		_last_position = pos

	if _direct_timer > 0.0:
		_direct_timer -= delta
		return (target - pos).normalized() * move_speed

	if use_flow and FlowField.is_ready():
		var dir: Vector2 = FlowField.get_direction(pos, _parent.ENEMY_RADIUS)
		if dir != Vector2.ZERO:
			return dir * move_speed

	return (target - pos).normalized() * move_speed

func stop() -> void:
	pass
