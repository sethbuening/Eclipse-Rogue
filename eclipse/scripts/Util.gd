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
