extends Node

const ZSORT_EFFECTS: int = 0

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
