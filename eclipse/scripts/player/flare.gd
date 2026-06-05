# flare.gd
# Scene: res://scenes/flare.tscn
#   Flare  (Node2D)
#     ├─ Sprite2D
#     └─ PointLight2D   (soft radial gradient texture, e.g. 128×128 white radial)
#
# No RigidBody2D, no CollisionShape2D — physics are manual, matching ParticleManager.
# Add "flare" action to InputMap.
# Add look_left / look_right / look_up / look_down axes for right-stick aiming.
class_name Flare
extends Node2D

# ── tunables ─────────────────────────────────────────────────────────────────

const GRAVITY:         float = 400.0
const BOUNCE_COEFF:    float = 0.45   # fraction of z-velocity kept on floor bounce
const WALL_BOUNCE:     float = 0.55   # fraction of 2D velocity kept on wall bounce
const SETTLE_Z_VEL:    float = 8.0    # z_vel below which the flare stops bouncing
const LIFETIME:        float = 18.0
const FLICKER_SPEED:   float = 6.0
const FLICKER_AMOUNT:  float = 0.08

# ── state ─────────────────────────────────────────────────────────────────────

var _pos:          Vector2 = Vector2.ZERO   # world-space XY position
var _vel:          Vector2 = Vector2.ZERO   # horizontal velocity (px/s)
var _z:            float   = 0.0            # vertical height above ground plane
var _z_vel:        float   = 0.0            # vertical velocity (px/s)
var _age:          float   = 0.0
var _landed:       bool    = false
var _base_energy:  float   = 1.0
var _base_radius:  float   = 80.0
var _time:         float   = 0.0

@onready var _light: PointLight2D = $PointLight2D


# ── public API ────────────────────────────────────────────────────────────────

## Called by player.gd immediately after add_child() + global_position is set.
func launch(direction: Vector2, speed: float, light_level: float, radius: float) -> void:
	_pos         = global_position
	_base_energy = light_level
	_base_radius = radius
	_vel         = direction * speed
	_z_vel       = speed * 0.35   # arc upward proportional to throw speed
	_z           = 2.0            # start just above ground so first frame doesn't bounce

	if _light:
		_light.energy        = light_level
		_light.texture_scale = radius / 64.0


# ── lifecycle ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_time += delta
	_age  += delta

	if _age >= LIFETIME:
		queue_free()
		return

	var tilemap: Node = _get_tilemap()

	if not _landed:
		# ── horizontal movement + wall bounce ─────────────────────────────────
		var next_pos: Vector2 = _pos + _vel * delta

		if tilemap != null:
			var map_pos: Vector2i = tilemap.world_to_map(next_pos)
			if tilemap.tile_exists(map_pos):
				var tile_center: Vector2 = tilemap.map_to_world(map_pos)
				var diff: Vector2        = _pos - tile_center
				if abs(diff.x) > abs(diff.y):
					_vel.x *= -WALL_BOUNCE
				else:
					_vel.y *= -WALL_BOUNCE
				if _z <= 0.0:
					_vel *= 0.7
			else:
				_pos = next_pos
		else:
			_pos = next_pos

		# ── vertical arc + floor bounce — flat z=0 plane, no tile height ─────
		_z_vel -= GRAVITY * delta
		_z     += _z_vel * delta

		if _z < 0.0:
			_z     = 0.0
			_z_vel = -_z_vel * BOUNCE_COEFF
			_vel  *= 0.8
			if absf(_z_vel) < SETTLE_Z_VEL:
				_z_vel  = 0.0
				_landed = true
				_vel    = Vector2.ZERO

	# No z-offset — flare sits flat on the 2D plane
	global_position = _pos

	# ── light flicker + lifetime fade ────────────────────────────────────────
	if _light:
		var life_ratio: float = 1.0 - clampf(_age / LIFETIME, 0.0, 1.0)
		var flicker:    float = sin(_time * FLICKER_SPEED) * FLICKER_AMOUNT
		_light.energy        = maxf(0.0, _base_energy * life_ratio + flicker)
		_light.texture_scale = (_base_radius / 64.0) * (0.9 + life_ratio * 0.1)


# ── helpers ───────────────────────────────────────────────────────────────────

func _get_tilemap() -> Node:
	# TilemapManager is a scene-unique node; walk up to find it.
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return root.find_child("TilemapManager", true, false)
