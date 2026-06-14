# lightning_chain.gd
# ---------------------------------------------------------------------------
# Visual + damage node instantiated by AbilityLightningChain.
# Spawns a StaticField at every enemy hit position (soft gold synergy).
# See ability_lightning_chain.gd for full synergy notes.
# ---------------------------------------------------------------------------
class_name LightningChain
extends Node2D

const JITTER_STEPS:  int   = 6
const JITTER_AMOUNT: float = 32.0  # was 20.0 — wider zigzags read better at larger widths

# One zigzag kink per this many world units; clamped to [1, JITTER_STEPS].
const JITTER_STEP_DIST: float = 24.0

# Derived at spawn time from the camera zoom so lightning pixels match world pixels exactly.
var _pixel_size: float = 1.0

var _stats:       AbilityStats
var _orb_potency: float
var _main_stats:  Array[String]
var _chain:       Array[Node2D]
var _lifetime:    float
var _elapsed:     float = 0.0
var _lines:       Array[Line2D]

func setup(
	origin:        Vector2,
	chain:         Array[Node2D],
	ability_stats: AbilityStats,
	orb_potency:   float,
	main_stats:    Array[String],
	player:        CharacterBody2D
) -> void:
	_stats        = ability_stats
	_orb_potency  = orb_potency
	_main_stats   = main_stats
	_chain        = chain
	_lifetime     = _stats.duration if _stats.duration > 0.0 else 0.25
	global_position = Vector2.ZERO

	# Derive world-pixel size from the camera zoom so our snapping grid
	# matches the actual pixel art grid — 1 world unit / zoom.x = 1 screen pixel.
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam:
		_pixel_size = 1.0 / cam.zoom.x

	var previous_was_crit: bool = false
	var hop_from:          Vector2 = origin

	for target: Node in _chain:
		# Non-enemy hop nodes (posts, ball lightning) are skipped for damage
		# but still contribute to the arc visuals built below.
		if target is ConductorPost or target is BallLightning:
			previous_was_crit = false
			hop_from          = target.global_position
			continue

		var enemy:        Enemy = target as Enemy
		var is_crit:      bool  = _stats.roll_crit(player)
		var scaled_power: float = _stats.get_stat("damage", _orb_potency, _main_stats)
		var damage:       float = scaled_power * (_stats.crit_damage if is_crit else 1.0)
		if previous_was_crit:
			damage *= 1.15

		_apply_hit(enemy, damage, is_crit, hop_from)

		# Soft synergy: StaticField — gold crits can detonate these later.
		StaticField.spawn(enemy.global_position, scaled_power, get_parent())

		previous_was_crit = is_crit
		hop_from          = enemy.global_position

	_build_arcs(origin)

func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = _elapsed / _lifetime
	for line: Line2D in _lines:
		if is_instance_valid(line):
			line.modulate.a = (1.0 - t) * randf_range(0.6, 1.0)
	if _elapsed >= _lifetime:
		queue_free()

func _build_arcs(origin: Vector2) -> void:
	var points: Array[Vector2] = [_snap(origin)]
	for target: Node2D in _chain:
		points.append(_snap(target.global_position))
	for i: int in range(points.size() - 1):
		# Build the zigzag once; both outer and core share the same path
		var bolt_pts: PackedVector2Array = _build_bolt_points(points[i], points[i + 1])
		var line: Line2D = _make_arc(points[i], points[i + 1], 5.0 * _pixel_size, Color(0.4, 0.7, 1.0, 1.0), bolt_pts)
		add_child(line)
		_lines.append(line)
		var core: Line2D = _make_arc(points[i], points[i + 1], 2.0 * _pixel_size, Color(1, 1, 1, 0.9), bolt_pts)
		add_child(core)
		_lines.append(core)

func _build_bolt_points(a: Vector2, b: Vector2) -> PackedVector2Array:
	# Build a zigzag lightning path between a and b.
	# Each interior point alternates side with a large perpendicular offset,
	# producing the sharp jagged shape of real lightning.
	# Scale steps with distance so short hops don't get over-jagged.
	var dist:  float              = a.distance_to(b)
	var steps: int                = clamp(int(dist / JITTER_STEP_DIST), 1, JITTER_STEPS)
	var pts:   PackedVector2Array = PackedVector2Array()
	var perp:  Vector2            = (b - a).rotated(PI / 2.0).normalized()
	var side:  float              = 1.0
	pts.append(_snap(a))
	for step: int in range(1, steps):
		var t:      float   = float(step) / float(steps)
		# Bias t slightly toward the start so the first kink is sharper
		var pos:    Vector2 = a.lerp(b, t)
		# Alternate sides with a large offset — true lightning zigzags hard
		var offset: float   = side * randf_range(JITTER_AMOUNT * 0.5, JITTER_AMOUNT)
		pos += perp * offset
		pts.append(_snap(pos))
		side = -side
	pts.append(_snap(b))
	return pts

func _snap(pos: Vector2) -> Vector2:
	return (pos / _pixel_size).round() * _pixel_size

func _make_arc(
	a:      Vector2,
	b:      Vector2,
	width:  float = 5.0,
	color:  Color = Color(0.4, 0.7, 1.0, 1.0),
	pts:    PackedVector2Array = PackedVector2Array()
) -> Line2D:
	var line: Line2D        = Line2D.new()
	line.width              = width
	line.default_color      = color
	# Pixelated: sharp corners, no rounded caps
	line.begin_cap_mode     = Line2D.LINE_CAP_NONE
	line.end_cap_mode       = Line2D.LINE_CAP_NONE
	line.joint_mode         = Line2D.LINE_JOINT_SHARP
	line.points             = pts
	return line

func _apply_hit(target: Enemy, damage: float, is_crit: bool, from_pos: Vector2) -> void:
	target.take_damage(int(damage), _stats.get_armor_pen(), is_crit, Util.DamageType.LIGHTNING)
	RelicOvercharged.add_stack(target)
	if _stats.knockback > 0.0:
		var dir: Vector2 = (target.global_position - from_pos).normalized()
		if target.has_method("apply_knockback"):
			target.apply_knockback(dir * _stats.knockback)
	if _stats.stun_duration > 0.0 and target.has_method("apply_stun"):
		target.apply_stun(_stats.stun_duration)
	if _stats.slow_amount > 0.0 and target.has_method("apply_slow"):
		target.apply_slow(_stats.slow_amount, _stats.slow_duration)
	if _stats.dot_damage > 0.0 and target.has_method("apply_dot"):
		target.apply_dot(_stats.dot_damage, _stats.dot_duration)
	ParticleManager.spawn_lightning_spark(target.global_position)
