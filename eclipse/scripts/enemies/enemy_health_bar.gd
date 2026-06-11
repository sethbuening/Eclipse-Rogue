class_name EnemyHealthBar
extends Node2D

# ── tunables ──────────────────────────────────────────────────────────────────

## Enemies with max_health below this threshold get no health bar.
const MIN_HEALTH_FOR_BAR: int   = 100

const BAR_WIDTH:    float = 28.0
const BAR_HEIGHT:   float = 3.0
const Y_OFFSET:     float = -18.0   # pixels above the enemy origin
const CORNER_RADIUS: float = 1.0

## How long after taking damage the bar stays visible before fading.
const LINGER_SECS:  float = 2.5
## Fade-out duration in seconds.
const FADE_SECS:    float = 0.5

## Delay before the ghost (orange) bar starts chasing the red bar.
const GHOST_DELAY:  float = 0.55
## Speed at which the ghost bar catches up (lerp factor per second).
const GHOST_SPEED:  float = 4.0

# ── colors ────────────────────────────────────────────────────────────────────

const COLOR_BG:     Color = Color(0.08, 0.08, 0.10, 0.85)
const COLOR_FILL:   Color = Color(0.20, 0.80, 0.25, 1.0)   # healthy green
const COLOR_LOW:    Color = Color(0.90, 0.25, 0.15, 1.0)   # critical red
const COLOR_GHOST:  Color = Color(0.95, 0.60, 0.10, 1.0)   # orange ghost
const COLOR_BORDER: Color = Color(0.0,  0.0,  0.0,  0.55)

# ── state ─────────────────────────────────────────────────────────────────────

var _max_health:    int   = 1
var _cur_health:    int   = 1
var _ghost_health:  float = 1.0
var _ghost_timer:   float = 0.0

# ── public API ────────────────────────────────────────────────────────────────

## Call once after the enemy's data is set.  Returns false if no bar is needed.
func init(max_hp: int) -> bool:
	if max_hp < MIN_HEALTH_FOR_BAR:
		queue_free()
		return false
	_max_health   = max_hp
	_cur_health   = max_hp
	_ghost_health = float(max_hp)
	visible       = true
	return true

func on_damage(new_health: int) -> void:
	_cur_health  = new_health
	_ghost_timer = GHOST_DELAY
	queue_redraw()


# ── process ───────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not visible:
		return
	# Ghost bar lag
	if _ghost_timer > 0.0:
		_ghost_timer -= _delta
	else:
		_ghost_health = lerpf(_ghost_health, float(_cur_health), GHOST_SPEED * _delta)
		if abs(_ghost_health - float(_cur_health)) < 0.5:
			_ghost_health = float(_cur_health)
	queue_redraw()

# ── drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	var origin := Vector2(-BAR_WIDTH * 0.5, Y_OFFSET)

	var fill_ratio:  float = clampf(float(_cur_health) / float(_max_health), 0.0, 1.0)
	var ghost_ratio: float = clampf(_ghost_health      / float(_max_health), 0.0, 1.0)

	# Background
	_draw_rounded_rect(origin, Vector2(BAR_WIDTH, BAR_HEIGHT), COLOR_BG)

	# Ghost (orange) bar — behind fill
	if ghost_ratio > fill_ratio:
		_draw_rounded_rect(origin, Vector2(BAR_WIDTH * ghost_ratio, BAR_HEIGHT), COLOR_GHOST)

	# Fill bar — color shifts green → red as health drops
	var fill_col: Color = COLOR_FILL.lerp(COLOR_LOW, 1.0 - fill_ratio)
	_draw_rounded_rect(origin, Vector2(BAR_WIDTH * fill_ratio, BAR_HEIGHT), fill_col)

	# Border
	draw_rect(Rect2(origin, Vector2(BAR_WIDTH, BAR_HEIGHT)), COLOR_BORDER, false, 0.75)

func _draw_rounded_rect(pos: Vector2, size: Vector2, color: Color) -> void:
	# Godot 4 draw_rect doesn't support corner radii, so approximate with
	# a center rect + two edge rects + four corner circles.
	if size.x <= 0.0:
		return
	var r: float = minf(CORNER_RADIUS, minf(size.x * 0.5, size.y * 0.5))
	# Main body
	draw_rect(Rect2(pos + Vector2(r, 0), size - Vector2(r * 2, 0)), color)
	draw_rect(Rect2(pos + Vector2(0, r), size - Vector2(0, r * 2)), color)
	# Corners
	for cx in [pos.x + r, pos.x + size.x - r]:
		for cy in [pos.y + r, pos.y + size.y - r]:
			draw_circle(Vector2(cx, cy), r, color)
