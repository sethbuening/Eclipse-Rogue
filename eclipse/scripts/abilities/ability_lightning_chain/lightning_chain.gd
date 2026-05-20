# lightning_chain.gd
# Attach to the root node of res://scenes/abilities/lightning_chain.tscn
#
# Scene tree (suggested):
#   LightningChain  (Node2D, this script)
#   └─ Line2D       (name: "Arc")   ← one reused Line2D; we draw segments via code
#
# You can replace the Line2D approach with a custom _draw() if you prefer.
class_name LightningChain
extends Node2D

# How many sub-segments to jitter per arc segment (visual only).
const JITTER_STEPS:  int   = 8
const JITTER_AMOUNT: float = 12.0   # pixels of random sideways offset

var _stats:     AbilityStats
var _orb_power: float
var _chain:     Array[Enemy]    # ordered list of targets
var _lifetime:  float           # driven by stats.duration
var _elapsed:   float = 0.0
var _lines:     Array[Line2D]   # one Line2D per arc segment

# Called by AbilityLightningChain right after instantiation.
func setup(
	origin:    Vector2,
	chain:     Array[Enemy],
	ability_stats: AbilityStats,
	orb_power: float
) -> void:
	_stats     = ability_stats
	_orb_power = orb_power
	_chain     = chain
	_lifetime  = _stats.duration if _stats.duration > 0.0 else 0.25   # fallback 0.25 s

	global_position = Vector2.ZERO   # we work in world space

	# ── Apply hits immediately (lightning is instant) ─────────────────────────
	var previous_was_crit: bool = false
	var hop_from: Vector2       = origin

	for i: int in range(_chain.size()):
		var target: Enemy = _chain[i]

		# Each hop rolls its own crit independently.
		var is_crit: bool  = _stats.roll_crit()
		var damage:  float = _stats.get_power(is_crit) * _orb_power

		# If the *previous* hop was a crit the chain "surged" – deal a small
		# bonus to this target too (flavor; optional to remove).
		if previous_was_crit:
			damage *= 1.15

		_apply_hit(target, damage, is_crit, hop_from)
		previous_was_crit = is_crit
		hop_from          = target.global_position

	# ── Build visuals ─────────────────────────────────────────────────────────
	_build_arcs(origin)


func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = _elapsed / _lifetime

	# Fade and flicker each arc line.
	for line: Line2D in _lines:
		if is_instance_valid(line):
			var alpha: float = (1.0 - t) * randf_range(0.6, 1.0)   # flicker
			line.modulate.a  = alpha

	if _elapsed >= _lifetime:
		queue_free()


# ── Visual helpers ─────────────────────────────────────────────────────────────

func _build_arcs(origin: Vector2) -> void:
	var points: Array[Vector2] = [origin]
	for target: Enemy in _chain:
		points.append(target.global_position)

	# One Line2D per segment so colours/widths can differ later.
	for i: int in range(points.size() - 1):
		var line: Line2D = _make_arc(points[i], points[i + 1])
		add_child(line)
		_lines.append(line)

		# Thinner, brighter core line on top.
		var core: Line2D = _make_arc(points[i], points[i + 1], 1.5, Color(1, 1, 1, 0.9), false)
		add_child(core)
		_lines.append(core)


func _make_arc(
	a:        Vector2,
	b:        Vector2,
	width:    float = 3.0,
	color:    Color = Color(0.4, 0.7, 1.0, 1.0),
	jitter:   bool  = true
) -> Line2D:
	var line: Line2D  = Line2D.new()
	line.width        = width
	line.default_color = color
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode   = Line2D.LINE_CAP_ROUND

	if jitter:
		var pts: PackedVector2Array = PackedVector2Array()
		var perp: Vector2           = (b - a).rotated(PI / 2.0).normalized()
		for step: int in range(JITTER_STEPS + 1):
			var t:   float   = float(step) / float(JITTER_STEPS)
			var pos: Vector2 = a.lerp(b, t)
			if step > 0 and step < JITTER_STEPS:
				pos += perp * randf_range(-JITTER_AMOUNT, JITTER_AMOUNT)
			pts.append(pos)
		line.points = pts
	else:
		line.points = PackedVector2Array([a, b])

	return line


# ── Hit application ────────────────────────────────────────────────────────────

func _apply_hit(target: Enemy, damage: float, is_crit: bool, from_pos: Vector2) -> void:
	target.take_damage(int(damage))

	# Knockback
	if _stats.knockback > 0.0:
		var dir: Vector2 = (target.global_position - from_pos).normalized()
		if target.has_method("apply_knockback"):
			target.apply_knockback(dir * _stats.knockback)

	# Stun
	if _stats.stun_duration > 0.0 and target.has_method("apply_stun"):
		target.apply_stun(_stats.stun_duration)

	# Slow
	if _stats.slow_amount > 0.0 and target.has_method("apply_slow"):
		target.apply_slow(_stats.slow_amount, _stats.slow_duration)

	# DoT (damage over time)
	if _stats.dot_damage > 0.0 and target.has_method("apply_dot"):
		target.apply_dot(_stats.dot_damage, _stats.dot_duration)

	# Light resource gain
	# We reach the player through the scene tree; adjust the path if needed.
	var player: Node = get_tree().get_first_node_in_group("player")
	if player:
		if is_crit and _stats.light_on_crit != 0.0:
			player.light += _stats.light_on_crit
		elif _stats.light_on_hit != 0.0:
			player.light += _stats.light_on_hit

	# Spawn lightning sparks at each hit point.
	ParticleManager.spawn_lightning_spark(target.global_position)
