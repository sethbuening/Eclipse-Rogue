# nav_obstacle.gd
extends Node

@export var polygon:          PackedVector2Array = PackedVector2Array()
@export var collision_source: CollisionShape2D   = null
@export var radius:           float              = 16.0
@export var enabled:          bool               = true

var _parent:           Node2D
var _resolved_polygon: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	_parent = get_parent() as Node2D
	if _parent == null:
		push_error("NavObstacle must be a child of a Node2D")
		return

	if collision_source == null:
		for child in _parent.get_children():
			if child is CollisionShape2D:
				collision_source = child
				break

	_resolved_polygon = _extract_polygon_from_collision_source()
	add_to_group("nav_obstacles")
	# NavManager.request_rebake() — disabled

func _exit_tree() -> void:
	remove_from_group("nav_obstacles")
	# NavManager.request_rebake() — disabled

func get_world_outline() -> PackedVector2Array:
	if not enabled:
		return PackedVector2Array()
	var local_poly := _active_polygon()
	if local_poly.size() >= 3:
		return _world_polygon(local_poly)
	var center: Vector2 = _parent.global_position
	var pts := PackedVector2Array()
	for i in 8:
		var angle := TAU * i / 8.0
		pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return pts

func _extract_polygon_from_collision_source() -> PackedVector2Array:
	if collision_source == null or collision_source.shape == null:
		return PackedVector2Array()
	var shape:       Shape2D     = collision_source.shape
	var local_xform: Transform2D = collision_source.transform
	if shape is ConvexPolygonShape2D:
		return _apply_local_xform(shape.points, local_xform)
	elif shape is RectangleShape2D:
		var e := (shape as RectangleShape2D).size * 0.5
		return _apply_local_xform(PackedVector2Array([
			Vector2(-e.x, -e.y),
			Vector2( e.x, -e.y),
			Vector2( e.x,  e.y),
			Vector2(-e.x,  e.y),
		]), local_xform)
	elif shape is CapsuleShape2D:
		return _apply_local_xform(_capsule_polygon(shape as CapsuleShape2D), local_xform)
	elif shape is CircleShape2D:
		return PackedVector2Array()
	return PackedVector2Array()

func _capsule_polygon(c: CapsuleShape2D, segments_per_cap: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var half_h: float = c.height * 0.5
	for i in range(segments_per_cap + 1):
		var angle := PI + (PI * i / segments_per_cap)
		pts.append(Vector2(cos(angle) * c.radius, -half_h + sin(angle) * c.radius))
	for i in range(segments_per_cap + 1):
		var angle := 0.0 + (PI * i / segments_per_cap)
		pts.append(Vector2(cos(angle) * c.radius, half_h + sin(angle) * c.radius))
	return pts

func _apply_local_xform(pts: PackedVector2Array, xform: Transform2D) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(xform * p)
	return out

func _active_polygon() -> PackedVector2Array:
	return polygon if polygon.size() >= 3 else _resolved_polygon

func _world_polygon(local_poly: PackedVector2Array) -> PackedVector2Array:
	var origin: Node2D = collision_source.get_parent() if collision_source != null else _parent
	var xform: Transform2D = origin.global_transform
	var result := PackedVector2Array()
	for v in local_poly:
		result.append(xform * v)
	return result
