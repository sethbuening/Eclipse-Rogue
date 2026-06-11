# lightning_javelin.gd
# ---------------------------------------------------------------------------
# Fast piercing projectile launched by AbilityLightningJavelin.
# Flags each killed enemy as a lightning kill for ResidualCurrent.
# Spawns StaticFields at every hit position for gold synergy.
# ---------------------------------------------------------------------------
class_name LightningJavelin
extends Node2D

const JITTER_STEPS:  int   = 6
const JITTER_AMOUNT: float = 6.0

var _direction:   Vector2
var _stats:       AbilityStats
var _orb_potency: float
var _main_stats:  Array[String]
var _player:      CharacterBody2D

var _speed:        float
var _range:        float
var _travelled:    float = 0.0
var _hit_set:      Array[Enemy] = []

# Visual trail
var _trail_points: PackedVector2Array = PackedVector2Array()
var _trail_line:   Line2D = null
var _trail_core:   Line2D = null
const TRAIL_LENGTH: int   = 12

func _ready() -> void:
	set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)

func launch(
	direction:   Vector2,
	stats:       AbilityStats,
	orb_potency: float,
	main_stats:  Array[String],
	player:      CharacterBody2D
) -> void:
	_direction   = direction
	_stats       = stats
	_orb_potency = orb_potency
	_main_stats  = main_stats
	_player      = player
	_speed       = _stats.get_stat("projectile_speed", _orb_potency, _main_stats)
	if _speed <= 0.0:
		_speed = 500.0
	_range = _stats.get_stat("range", _orb_potency, _main_stats)
	if _range <= 0.0:
		_range = 400.0

	_trail_line = _make_trail_line(3.0, Color(0.4, 0.7, 1.0, 0.9))
	_trail_core = _make_trail_line(1.5, Color(1.0, 1.0, 1.0, 0.9))
	add_child(_trail_line)
	add_child(_trail_core)

	reset_physics_interpolation()

func _process(delta: float) -> void:
	var step: float = _speed * delta
	_travelled   += step
	global_position += _direction * step

	# Record trail
	_trail_points.append(global_position)
	if _trail_points.size() > TRAIL_LENGTH:
		_trail_points.remove_at(0)
	if _trail_points.size() >= 2:
		_trail_line.points = _trail_points
		_trail_core.points = _trail_points

	# Hit detection
	var hit_radius:   float = _stats.get_stat("aoe_radius", _orb_potency, _main_stats)
	if hit_radius <= 0.0:
		hit_radius = 8.0
	var hit_radius_sq: float = hit_radius * hit_radius

	for enemy: Enemy in EnemyManager.living_enemies.duplicate():
		if not is_instance_valid(enemy) or enemy in _hit_set:
			continue
		if global_position.distance_squared_to(enemy.global_position) > hit_radius_sq:
			continue
		_hit_set.append(enemy)
		_apply_hit(enemy)

	if _travelled >= _range:
		queue_free()

func _apply_hit(enemy: Enemy) -> void:
	var is_crit: bool  = _stats.roll_crit(_player)
	var power:   float = _stats.get_stat("power", _orb_potency, _main_stats)
	var damage:  float = power * (_stats.crit_damage if is_crit else 1.0)

	# Flag as lightning kill so ResidualCurrent can respond.
	enemy.set_meta("lightning_kill", true)

	enemy.take_damage(int(damage), _stats.get_armor_pen(), is_crit, Util.DamageType.LIGHTNING)
	RelicOvercharged.add_stack(enemy)

	if is_instance_valid(enemy):
		if _stats.knockback > 0.0:
			var dir: Vector2 = (enemy.global_position - global_position).normalized()
			enemy.apply_knockback(dir * _stats.knockback)
		if _stats.slow_amount > 0.0:
			enemy.apply_slow(_stats.slow_amount, _stats.slow_duration)

	ParticleManager.spawn_lightning_spark(enemy.global_position)

	# Soft synergy: StaticField row along the firing axis.
	StaticField.spawn(enemy.global_position, power, get_parent())

func _make_trail_line(width: float, color: Color) -> Line2D:
	var line: Line2D       = Line2D.new()
	line.width             = width
	line.default_color     = color
	line.begin_cap_mode    = Line2D.LINE_CAP_ROUND
	line.end_cap_mode      = Line2D.LINE_CAP_ROUND
	return line
