extends Node

enum tile {
	AIR,
	STONE,
	ROCK,
	GOLD,
	IRON,
	COPPER,
	TIN,
	CRYSTAL
}

enum dir {
	UP,
	RIGHT,
	LEFT,
	DOWN
}

# ── wave modifiers ────────────────────────────────────────────────────────────
enum Modifier {
	NONE,
	FAST,
	ALERTED,
	CLUSTERED,
	TRICKLE
}

func nearest_direction(v: Vector2) -> Vector2i:
	if abs(v.x) >= abs(v.y):
		return Vector2i.RIGHT if v.x >= 0 else Vector2i.LEFT
	else:
		return Vector2i.DOWN if v.y >= 0 else Vector2i.UP

# in Util.gd
func load_resources(path: String) -> Array[Resource]:
	var results: Array[Resource] = []
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		push_error("Util.load_resources: could not open path: " + path)
		return results
	dir.list_dir_begin()
	var filename: String = dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".tres"):
			var res: Resource = load(path + filename)
			if res != null:
				results.append(res)
			else:
				push_warning("Util.load_resources: failed to load: " + filename)
		filename = dir.get_next()
	dir.list_dir_end()
	return results

# ── debug draw ────────────────────────────────────────────────────────────────
static func draw_debug_circle(parent: Node2D, radius: float, color: Color = Color(1, 0, 0, 0.4), duration: float = 0.5) -> void:
	var circle := _DebugCircle.new()
	circle.radius   = radius
	circle.color    = color
	circle.duration = duration
	parent.get_tree().get_root().add_child(circle)
	circle.global_position = parent.global_position

class _DebugCircle extends Node2D:
	var radius:   float = 32.0
	var color:    Color = Color(1, 0, 0, 0.4)
	var duration: float = 0.5
	var _age:     float = 0.0

	func _process(delta: float) -> void:
		_age += delta
		modulate.a = 1.0 - (_age / duration)
		if _age >= duration:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		draw_arc(Vector2.ZERO, radius, 0, TAU, 48, color, 2.0)
