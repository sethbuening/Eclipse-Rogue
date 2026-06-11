# arc_overload.gd
# ---------------------------------------------------------------------------
# Sustained beam node instantiated by AbilityArcOverload.
# Tracks the target enemy for its duration, dealing damage each tick and
# updating the beam arc to follow them.
# ---------------------------------------------------------------------------
class_name ArcOverload
extends Node2D

const JITTER_STEPS:  int   = 10
const JITTER_AMOUNT: float = 8.0
const TICK_INTERVAL: float = 0.12   # seconds between damage applications

var _stats:       AbilityStats
var _orb_potency: float
var _main_stats:  Array[String]
var _player:      CharacterBody2D
var _target:      Enemy
var _origin:      Vector2

var _lifetime:    float
var _elapsed:     float = 0.0
var _tick_timer:  float = 0.0

# Visuals — rebuilt each frame so the beam tracks the moving target.
var _outer_line: Line2D = null
var _core_line:  Line2D = null

func _ready() -> void:
	set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)
	_outer_line = _make_beam_line(4.0, Color(0.3, 0.6, 1.0, 0.85))
	_core_line  = _make_beam_line(1.5, Color(0.85, 0.95, 1.0, 1.0))
	add_child(_outer_line)
	add_child(_core_line)

func setup(
	origin:        Vector2,
	target:        Enemy,
	ability_stats: AbilityStats,
	orb_potency:   float,
	main_stats:    Array[String],
	player:        CharacterBody2D
) -> void:
	_stats       = ability_stats
	_orb_potency = orb_potency
	_main_stats  = main_stats
	_player      = player
	_target      = target
	_origin      = origin
	_lifetime    = _stats.get_stat("duration", _orb_potency, _main_stats)
	if _lifetime <= 0.0:
		_lifetime = 1.2

	global_position = Vector2.ZERO
	reset_physics_interpolation()

	# Apply an immediate first tick so the beam feels responsive on spawn.
	_apply_damage_tick()

func _process(delta: float) -> void:
	_elapsed += delta

	# If the target died mid-beam, fade out early.
	if not is_instance_valid(_target):
		_fade_out()
		return

	# Fade alpha near end of lifetime.
	var fade_start: float = _lifetime * 0.75
	if _elapsed >= fade_start:
		modulate.a = 1.0 - (_elapsed - fade_start) / (_lifetime - fade_start)

	if _elapsed >= _lifetime:
		queue_free()
		return

	# Damage tick.
	_tick_timer += delta
	if _tick_timer >= TICK_INTERVAL:
		_tick_timer = 0.0
		_apply_damage_tick()

	# Rebuild arc each frame to track the moving target.
	_rebuild_beam(_origin, _target.global_position)

func _apply_damage_tick() -> void:
	if not is_instance_valid(_target):
		return

	var stacks:     int   = _target.get_meta("arc_stacks", 0)
	var base_power: float = _stats.get_stat("power", _orb_potency, _main_stats)

	# Scale damage with stacks — each stack adds STACK_DAMAGE_MULT * base_power.
	var stack_bonus: float = float(stacks) * AbilityArcOverload.STACK_DAMAGE_MULT * base_power
	var total_power: float = base_power + stack_bonus

	var is_crit: bool  = _stats.roll_crit(_player)
	var damage:  float = total_power * (_stats.crit_damage if is_crit else 1.0)

	_target.take_damage(int(damage), _stats.get_armor_pen(), is_crit, Util.DamageType.LIGHTNING)
	RelicOvercharged.add_stack(_target)

	# Spend stacks — relic wrote them, we consume them gradually.
	if stacks > 0:
		var remaining: int = maxi(0, stacks - AbilityArcOverload.STACKS_SPENT_PER_HIT)
		_target.set_meta("arc_stacks", remaining)

	# Apply hit effects from stats (slow, stun, DoT, knockback).
	# Knockback is intentionally suppressed on beam — it would push the target
	# out of beam range immediately.
	if _stats.stun_duration > 0.0 and is_instance_valid(_target):
		_target.apply_stun(_stats.stun_duration)
	if _stats.slow_amount > 0.0 and is_instance_valid(_target):
		_target.apply_slow(_stats.slow_amount, _stats.slow_duration)
	if _stats.dot_damage > 0.0 and is_instance_valid(_target):
		_target.apply_dot(_stats.dot_damage, _stats.dot_duration)

	ParticleManager.spawn_lightning_spark(_target.global_position)

	# Soft synergy: dense StaticField seeding at one position.
	StaticField.spawn(_target.global_position, base_power, get_parent())

# ── visuals ───────────────────────────────────────────────────────────────────

func _rebuild_beam(from: Vector2, to: Vector2) -> void:
	var pts: PackedVector2Array = _jitter_points(from, to)
	_outer_line.points = pts
	_core_line.points  = pts

func _jitter_points(a: Vector2, b: Vector2) -> PackedVector2Array:
	var pts:  PackedVector2Array = PackedVector2Array()
	var perp: Vector2            = (b - a).rotated(PI / 2.0).normalized()
	for step in range(JITTER_STEPS + 1):
		var t:   float   = float(step) / float(JITTER_STEPS)
		var pos: Vector2 = a.lerp(b, t)
		if step > 0 and step < JITTER_STEPS:
			pos += perp * randf_range(-JITTER_AMOUNT, JITTER_AMOUNT)
		pts.append(pos)
	return pts

func _make_beam_line(width: float, color: Color) -> Line2D:
	var line: Line2D    = Line2D.new()
	line.width          = width
	line.default_color  = color
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode   = Line2D.LINE_CAP_ROUND
	return line

func _fade_out() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.tween_callback(queue_free)
