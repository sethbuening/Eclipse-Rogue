class_name EnemyNavigator
extends Node

@export var move_speed:        float = 60.0
@export var arrival_threshold: float = 4.0
@export var stuck_timeout:     float = 0.5

var _last_position: Vector2 = Vector2.ZERO
var _stuck_timer:   float   = 0.0
var _direct_timer:  float   = 0.0

var _parent: Node2D

func _ready() -> void:
	_parent = get_parent() as Node2D
	if _parent == null:
		push_error("EnemyNavigator must be a child of a Node2D")

func navigate_toward(target: Vector2, delta: float, use_flow: bool = true) -> Vector2:
	if _parent == null:
		return Vector2.ZERO

	_stuck_timer += delta
	if _stuck_timer >= stuck_timeout:
		_stuck_timer = 0.0
		if _parent.global_position.distance_squared_to(_last_position) < 4.0:
			_direct_timer = 0.35
		_last_position = _parent.global_position

	if _direct_timer > 0.0:
		_direct_timer -= delta
		return (target - _parent.global_position).normalized() * move_speed

	if use_flow and FlowField.is_ready():
		var dir: Vector2 = FlowField.get_direction(_parent.global_position)
		if dir != Vector2.ZERO:
			return dir * move_speed

	# direct fallback — no NavManager
	return (target - _parent.global_position).normalized() * move_speed

func stop() -> void:
	pass
