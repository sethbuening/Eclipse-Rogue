# lightning_chain.gd
# ---------------------------------------------------------------------------
# Visual + damage node instantiated by AbilityLightningChain.
# Spawns a StaticField at every enemy hit position (soft gold synergy).
# See ability_lightning_chain.gd for full synergy notes.
# ---------------------------------------------------------------------------
class_name LightningChain
extends Node2D

const JITTER_STEPS:  int   = 8
const JITTER_AMOUNT: float = 12.0

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
		var scaled_power: float = _stats.get_stat("power", _orb_potency, _main_stats)
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
	var points: Array[Vector2] = [origin]
	for target: Node2D in _chain:
		points.append(target.global_position)
	for i: int in range(points.size() - 1):
		var line: Line2D = _make_arc(points[i], points[i + 1])
		add_child(line)
		_lines.append(line)
		var core: Line2D = _make_arc(points[i], points[i + 1], 1.5, Color(1, 1, 1, 0.9), false)
		add_child(core)
		_lines.append(core)

func _make_arc(
	a:      Vector2,
	b:      Vector2,
	width:  float = 3.0,
	color:  Color = Color(0.4, 0.7, 1.0, 1.0),
	jitter: bool  = true
) -> Line2D:
	var line: Line2D        = Line2D.new()
	line.width              = width
	line.default_color      = color
	line.begin_cap_mode     = Line2D.LINE_CAP_ROUND
	line.end_cap_mode       = Line2D.LINE_CAP_ROUND
	if jitter:
		var pts:  PackedVector2Array = PackedVector2Array()
		var perp: Vector2            = (b - a).rotated(PI / 2.0).normalized()
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
