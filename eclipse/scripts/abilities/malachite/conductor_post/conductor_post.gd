# conductor_post.gd
# ---------------------------------------------------------------------------
# Placed by AbilityConductorPost.  Pulses slow + DoT to nearby enemies.
# Enters a "charged" state when a LightningChain or BallLightning interacts
# with it, scaling up its pulse damage and slow multiplier temporarily.
#
# Hard synergies (inbound)
#   ← LightningChain : apply_bolt_bonus() called by the chain when it hops
#                      through this post.  Charges the post and returns bonus
#                      pierce + AOE to the chain context.
#   ← BallLightning  : BallLightning calls notify_ball_nearby() each frame
#                      while within BALL_SNAP_RADIUS.  The post snaps the ball
#                      to its position for BALL_SNAP_DURATION, fires one
#                      amplified pulse, then releases it.
# ---------------------------------------------------------------------------
class_name ConductorPost
extends Node2D

static var all_posts: Array[ConductorPost] = []

const BASE_TICK_INTERVAL:  float = 0.4
const MINING_TICK_INTERVAL: float = 2.5
const CHARGE_DURATION:     float = 8.0
const CHARGE_PIERCE_BONUS: int   = 3
const CHARGE_AOE_BONUS:    float = 30.0
const CHARGE_EFFECT_SCALE: float = 1.5
const FADE_DURATION:       float = 3.0

# BallLightning snap constants
const BALL_SNAP_RADIUS:   float = 40.0   # how close ball must be to trigger snap
const BALL_SNAP_DURATION: float = 0.35   # how long the ball is held at the post

var _stats:       AbilityStats
var _orb_potency: float
var _main_stats:  Array[String]
var _tilemap:     Node

var _charge:       float = 0.0
var _field_timer:  float = 0.0
var _mining_timer: float = 0.0
var _is_charged:   bool  = false
var _age:          float = 0.0
var _lifetime:     float = 0.0

# BallLightning snap state — only one ball snapped at a time
var _snapped_ball: BallLightning = null
var _snap_timer:   float         = 0.0

var _field_area:   Area2D           = null
var _field_shape:  CollisionShape2D = null
var _anim:         AnimatedSprite2D = null
var _charge_light: PointLight2D     = null

func _ready() -> void:
	set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)
	_field_area  = $FieldArea
	_field_shape = $FieldArea/CollisionShape2D
	_anim        = $AnimatedSprite2D
	if has_node("ChargeLight"):
		_charge_light = $ChargeLight
	add_to_group("conductor_posts")

func setup(
	stats:       AbilityStats,
	orb_potency: float,
	main_stats:  Array[String],
	tilemap:     Node
) -> void:
	_stats       = stats
	_orb_potency = orb_potency
	_main_stats  = main_stats
	_tilemap     = tilemap
	_lifetime    = _stats.get_stat("duration", _orb_potency, _main_stats)

	var shape := CircleShape2D.new()
	shape.radius = _stats.get_stat("aoe_radius", _orb_potency, _main_stats)
	_field_shape.shape = shape

	all_posts.append(self)
	_anim.play("idle")

func _exit_tree() -> void:
	all_posts.erase(self)
	# Release any snapped ball so it doesn't remain frozen.
	if is_instance_valid(_snapped_ball):
		_snapped_ball.release_from_post()
		_snapped_ball = null

func _process(delta: float) -> void:
	_age += delta

	if _age >= _lifetime:
		var fade_progress: float = (_age - _lifetime) / FADE_DURATION
		modulate.a = 1.0 - fade_progress
		if _age >= _lifetime + FADE_DURATION:
			_set_charged(false)
			queue_free()
			return

	if _charge > 0.0:
		_charge -= delta
		if _charge <= 0.0:
			_charge = 0.0
			_set_charged(false)

	_field_timer += delta
	if _field_timer >= BASE_TICK_INTERVAL:
		_field_timer = 0.0
		_pulse_field()

	# Tick snap timer; release ball when it expires.
	if is_instance_valid(_snapped_ball) and _snap_timer > 0.0:
		_snap_timer -= delta
		if _snap_timer <= 0.0:
			_snapped_ball.release_from_post()
			_snapped_ball = null

	if _tilemap != null:
		_mining_timer += delta
		if _mining_timer >= MINING_TICK_INTERVAL:
			_mining_timer = 0.0
			_mine_area()

# ── inbound charge API ────────────────────────────────────────────────────────

func receive_charge(amount: float = CHARGE_DURATION) -> void:
	_charge = minf(_charge + amount, CHARGE_DURATION)
	_set_charged(true)

## Called by LightningChain when it hops through this post.
func apply_bolt_bonus(context: Dictionary) -> void:
	context["bonus_pierce"] = context.get("bonus_pierce", 0) + CHARGE_PIERCE_BONUS
	context["bonus_aoe"]    = context.get("bonus_aoe",    0.0) + CHARGE_AOE_BONUS
	receive_charge(CHARGE_DURATION)

## Called by BallLightning each frame while it is within BALL_SNAP_RADIUS and
## not already snapped to anything.  Returns true when the snap was accepted so
## the ball knows it is now held.
func notify_ball_nearby(ball: BallLightning) -> bool:
	# Only snap one ball at a time; ignore if already snapping one.
	if is_instance_valid(_snapped_ball):
		return false
	_snapped_ball = ball
	_snap_timer   = BALL_SNAP_DURATION
	receive_charge(CHARGE_DURATION)
	# Fire one amplified pulse immediately at the post's position.
	_pulse_field_amplified(CHARGE_EFFECT_SCALE * 1.5)
	return true

# ── static helper ─────────────────────────────────────────────────────────────

static func nearest_in_range(origin: Vector2, radius: float) -> ConductorPost:
	var best_dist: float         = radius * radius
	var best:      ConductorPost = null
	for post: ConductorPost in all_posts:
		if not is_instance_valid(post):
			continue
		var d2: float = origin.distance_squared_to(post.global_position)
		if d2 <= best_dist:
			best_dist = d2
			best      = post
	return best

# ── pulse ─────────────────────────────────────────────────────────────────────

func _pulse_field() -> void:
	var effect_scale: float = CHARGE_EFFECT_SCALE if _is_charged else 1.0
	_pulse_field_amplified(effect_scale)

func _pulse_field_amplified(scale: float) -> void:
	var slow:      float = _stats.get_stat("slow_amount",   _orb_potency, _main_stats) * scale
	var slow_dur:  float = _stats.get_stat("slow_duration", _orb_potency, _main_stats)
	var dot:       float = _stats.get_stat("dot_damage",    _orb_potency, _main_stats) * scale
	var dot_dur:   float = _stats.dot_duration
	var radius:    float = (_field_shape.shape as CircleShape2D).radius
	var radius_sq: float = radius * radius

	for enemy in EnemyManager.living_enemies:
		if not is_instance_valid(enemy):
			continue
		if global_position.distance_squared_to(enemy.global_position) > radius_sq:
			continue
		if slow > 0.0:
			enemy.apply_slow(slow, slow_dur)
		if dot > 0.0:
			enemy.apply_dot(dot, dot_dur)
		ParticleManager.spawn_lightning_spark(enemy.global_position)

# ── mining ────────────────────────────────────────────────────────────────────

func _mine_area() -> void:
	var mining_power: int      = int(_stats.get_stat("mining_power",  _orb_potency, _main_stats))
	var max_ring:     int      = int(_stats.get_stat("mining_radius", _orb_potency, _main_stats))
	var map_center:   Vector2i = _tilemap.world_to_map(global_position)
	var removed:      Array[Vector2i] = []

	for dx in range(-max_ring, max_ring + 1):
		for dy in range(-max_ring, max_ring + 1):
			if dx * dx + dy * dy > max_ring * max_ring:
				continue
			var map_pos: Vector2i = map_center + Vector2i(dx, dy)
			if not _tilemap.tile_exists(map_pos):
				continue
			var died: bool = _tilemap.tile_health.get(map_pos, 1) <= mining_power
			if died:
				removed.append(map_pos)
			_tilemap.damage_tile_silent(map_pos, mining_power)

	if not removed.is_empty():
		_tilemap.flush_removed_tiles(removed)

# ── visuals ───────────────────────────────────────────────────────────────────

func _set_charged(charged: bool) -> void:
	_is_charged = charged
	if charged:
		_anim.play("charged")
		if is_instance_valid(_charge_light):
			_charge_light.enabled = true
	else:
		_anim.play("idle")
		if is_instance_valid(_charge_light):
			_charge_light.enabled = false
