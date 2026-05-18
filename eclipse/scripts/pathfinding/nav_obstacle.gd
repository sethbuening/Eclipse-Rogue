# nav_obstacle.gd
# Attach to any Node2D to register it as a dynamic navigation obstacle.
# If polygon has 3+ vertices it is used as the shape, otherwise radius is used.
# Polygon vertices are in LOCAL space and must be in CLOCKWISE order.
extends Node

@export var polygon: PackedVector2Array = PackedVector2Array()
@export var radius:  float = 16.0
@export var enabled: bool  = true:
	set(value):
		enabled = value
		if _obstacle_rid.is_valid():
			NavigationServer2D.obstacle_set_avoidance_enabled(_obstacle_rid, enabled)

var _obstacle_rid: RID
var _parent:       Node2D

func _ready() -> void:
	_parent = get_parent() as Node2D
	if _parent == null:
		push_error("NavObstacle must be a child of a Node2D")
		return
	_register()

func _register() -> void:
	if not NavManager._built:
		await get_tree().create_timer(0.1).timeout
		_register()
		return

	_obstacle_rid = NavigationServer2D.obstacle_create()
	NavigationServer2D.obstacle_set_map(_obstacle_rid, NavManager._map_rid)
	NavigationServer2D.obstacle_set_avoidance_enabled(_obstacle_rid, enabled)

	if polygon.size() >= 3:
		NavigationServer2D.obstacle_set_vertices(_obstacle_rid, _world_polygon())
	else:
		NavigationServer2D.obstacle_set_radius(_obstacle_rid, radius)
		NavigationServer2D.obstacle_set_position(_obstacle_rid, _parent.global_position)

func _physics_process(_delta: float) -> void:
	if not _obstacle_rid.is_valid() or _parent == null:
		return
	if polygon.size() >= 3:
		NavigationServer2D.obstacle_set_vertices(_obstacle_rid, _world_polygon())
	else:
		NavigationServer2D.obstacle_set_position(_obstacle_rid, _parent.global_position)

func _world_polygon() -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	var xform:  Transform2D        = _parent.global_transform
	for v: Vector2 in polygon:
		result.append(xform * v)
	return result

func _exit_tree() -> void:
	if _obstacle_rid.is_valid():
		NavigationServer2D.free_rid(_obstacle_rid)
