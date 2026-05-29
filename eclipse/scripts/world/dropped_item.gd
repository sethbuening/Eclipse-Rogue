# dropped_item.gd
class_name DroppedItem
extends Sprite2D

enum DropType { XP, METAL }

var drop_type: DropType  = DropType.XP
var metal:     MetalData = null

var pos:   Vector2 = Vector2.ZERO
var vel:   Vector2 = Vector2.ZERO
var z:     float   = 0.0
var z_vel: float   = 0.0
const GRAVITY: float = 300.0
const BOUNCE:  float = 0.3
const RADIUS:  float = 4.0

# ── collect animation ─────────────────────────────────────────────────────────
# Quadratic bezier: P0 (orb) → P1 (control point) → P2 (player)
# The control point sits behind and above the orb (opposite the player),
# so the arc floats out and up before smoothly curving back in.
#
# Z_DELAY controls how far through the arc (0–1) before the orb starts rising.
# e.g. 0.3 means the orb travels outward for 30% of the duration flat,
# then the Z hump plays over the remaining 70%.

enum CollectPhase { NONE, ARC }
var collecting:    CollectPhase = CollectPhase.NONE
var collect_timer: float        = 0.0
var _arc_start:    Vector2      = Vector2.ZERO
var _arc_control:  Vector2      = Vector2.ZERO
var _arc_end:      Vector2      = Vector2.ZERO

const COLLECT_DURATION: float = 0.6    # slow, readable arc
const CONTROL_AWAY:     float = 64.0   # outward fling distance
const CONTROL_UP:       float = 32.0   # upward loft height
const SHRINK_START:     float = 1   # begins shrinking past the apex
const Z_DELAY:          float = 0.2    # fraction of arc to travel flat before rising

func _ready() -> void:
	match drop_type:
		DropType.XP:
			var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
			img.set_pixel(0, 0, Color.WHITE)
			texture  = ImageTexture.create_from_image(img)
			scale    = Vector2(3.0, 3.0)
			modulate = Color(1.163, 1.627, 1.881, 1.0)
		DropType.METAL:
			if metal != null and metal.sprite_texture != null:
				texture = metal.sprite_texture

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
	# Smooth-step ease: gradual start and end — reads as a natural float.
	var t: float = raw_t * raw_t * (3.0 - 2.0 * raw_t)

	# Quadratic bezier: B(t) = (1-t)²·P0 + 2(1-t)t·P1 + t²·P2
	var inv: float = 1.0 - t
	pos = inv * inv * _arc_start \
		+ 2.0 * inv * t * _arc_control \
		+ t * t * _arc_end

	# Z hump is delayed: flat for the first Z_DELAY fraction, then a full
	# sine hump over the remainder so the orb goes out before going up.
	var z_t: float = clampf((raw_t - Z_DELAY) / (1.0 - Z_DELAY), 0.0, 1.0)
	z = CONTROL_UP * sin(z_t * PI)

	# Shrink to nothing over the tail of the arc.
	var shrink_t: float = clampf((raw_t - SHRINK_START) / (1.0 - SHRINK_START), 0.0, 1.0)
	scale = Vector2.ONE * (3.0 * (1.0 - shrink_t))

	global_position = pos + Vector2(0, -z)
