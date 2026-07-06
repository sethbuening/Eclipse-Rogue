class_name DroppedItem
extends Sprite2D

enum DropType { XP, ITEM }

var drop_type: DropType = DropType.XP
var item:      ItemData = null

var pos:   Vector2 = Vector2.ZERO
var vel:   Vector2 = Vector2.ZERO
var z:     float   = 0.0
var z_vel: float   = 0.0

const GRAVITY: float = 300.0
const BOUNCE:  float = 0.3
const RADIUS:  float = 4.0

# ── collect animation ─────────────────────────────────────────────────────────
enum CollectPhase { NONE, ARC }

var collecting:    CollectPhase = CollectPhase.NONE
var collect_timer: float        = 0.0
var _arc_start:    Vector2      = Vector2.ZERO
var _arc_control:  Vector2      = Vector2.ZERO
var _arc_end:      Vector2      = Vector2.ZERO

const COLLECT_DURATION: float = 0.8
const CONTROL_AWAY:     float = 64.0
const CONTROL_UP:       float = 32.0
const Z_DELAY:          float = 0.2

func _ready() -> void:
	match drop_type:
		DropType.XP:
			var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
			img.set_pixel(0, 0, Color.WHITE)
			texture  = ImageTexture.create_from_image(img)
			scale    = Vector2(3.0, 3.0)
			modulate = Color(1.163, 1.627, 1.881, 1.0)
		DropType.ITEM:
			if item != null and item.icon != null:
				texture = item.icon

func begin_collect(player_pos: Vector2) -> void:
	collecting    = CollectPhase.ARC
	collect_timer = 0.0
	_arc_start    = pos
	_arc_end      = player_pos
	var away: Vector2 = (pos - player_pos).normalized()
	_arc_control = pos + away * CONTROL_AWAY + Vector2(0, -CONTROL_UP)

func tick_arc(player_pos: Vector2, delta: float) -> void:
	collect_timer += delta
	_arc_end       = player_pos
	var raw_t: float = minf(collect_timer / COLLECT_DURATION, 1.0)
	var t: float = raw_t * raw_t * (3.0 - 2.0 * raw_t)
	var inv: float = 1.0 - t
	pos = inv * inv * _arc_start \
		+ 2.0 * inv * t * _arc_control \
		+ t * t * _arc_end
	var z_t: float = clampf((raw_t - Z_DELAY) / (1.0 - Z_DELAY), 0.0, 1.0)
	z = CONTROL_UP * sin(z_t * PI)
	global_position = pos + Vector2(0, -z)
