# enemy_navigator.gd
class_name EnemyNavigator
extends Node

@export var move_speed:        float = 60.0
@export var path_update_rate:  float = 0.15
@export var arrival_threshold: float = 4.0
@export var stuck_timeout:     float = 0.4

var _last_position: Vector2           = Vector2.ZERO
var _stuck_timer:   float             = 0.0
var _path:          PackedVector2Array = PackedVector2Array()
var _path_index:    int               = 0
var _update_timer:  float             = 0.0
var _parent:        Node2D

func _ready() -> void:
	_parent = get_parent() as Node2D
	if _parent == null:
		push_error("EnemyNavigator must be a child of a Node2D")

# ── public API ────────────────────────────────────────────────────────────────

func navigate_toward(target: Vector2, delta: float) -> Vector2:
	if _parent == null or not NavManager._built:
		return Vector2.ZERO

	_stuck_timer += delta
	if _stuck_timer >= stuck_timeout:
		_stuck_timer = 0.0
		if _parent.global_position.distance_to(_last_position) < 2.0:
			_path = PackedVector2Array()
		_last_position = _parent.global_position

	_update_timer += delta
	if _update_timer >= path_update_rate or _path.is_empty():
		_update_timer = 0.0
		_path         = NavManager.query_path(_parent.global_position, target)
		_path_index   = 1 if _path.size() > 1 else 0

	return _follow_path()

func stop() -> void:
	_path       = PackedVector2Array()
	_path_index = 0

# ── internal ──────────────────────────────────────────────────────────────────

func _follow_path() -> Vector2:
	if _path.is_empty() or _path_index >= _path.size():
		return Vector2.ZERO
	var to_wp: Vector2 = _path[_path_index] - _parent.global_position
	if to_wp.length() < arrival_threshold:
		_path_index += 1
		if _path_index >= _path.size():
			return Vector2.ZERO
		to_wp = _path[_path_index] - _parent.global_position
	return to_wp.normalized() * move_speed
