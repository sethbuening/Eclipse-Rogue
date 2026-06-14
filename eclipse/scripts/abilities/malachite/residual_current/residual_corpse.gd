# residual_corpse.gd
# ---------------------------------------------------------------------------
# Short-lived ground node placed by AbilityResidualCurrent when a lightning
# ability kills an enemy.  Fires one chain shock at the next enemy that walks
# within range, then expires.
#
# Spawns a StaticField at the shocked enemy's position (soft gold synergy).
# ---------------------------------------------------------------------------
class_name ResidualCorpse
extends Node2D

static var active_count: int = 0

const LIFETIME:        float = 6.0
const CHECK_INTERVAL:  float = 0.15

var _stats:       AbilityStats
var _orb_potency: float
var _main_stats:  Array[String]

var _age:          float = 0.0
var _check_timer:  float = 0.0
var _fired:        bool  = false

func _ready() -> void:
	set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)
	active_count += 1

func _exit_tree() -> void:
	active_count -= 1

func setup(
	stats:       AbilityStats,
	orb_potency: float,
	main_stats:  Array[String]
) -> void:
	_stats       = stats
	_orb_potency = orb_potency
	_main_stats  = main_stats
	reset_physics_interpolation()

func _process(delta: float) -> void:
	if _fired:
		return

	_age += delta

	# Fade slowly over lifetime.
	modulate.a = clampf(1.0 - (_age / LIFETIME), 0.15, 1.0)

	if _age >= LIFETIME:
		queue_free()
		return

	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = CHECK_INTERVAL

	_check_trigger()

func _check_trigger() -> void:
	var radius:    float = _stats.get_stat("aoe_radius", _orb_potency, _main_stats)
	if radius <= 0.0:
		radius = 40.0
	var radius_sq: float = radius * radius

	for enemy: Enemy in EnemyManager.living_enemies:
		if not is_instance_valid(enemy):
			continue
		if global_position.distance_squared_to(enemy.global_position) > radius_sq:
			continue
		_fire_shock(enemy)
		return

func _fire_shock(target: Enemy) -> void:
	_fired = true

	var power:   float = _stats.get_stat("damage", _orb_potency, _main_stats) * 0.6
	var is_crit: bool  = _stats.roll_crit(null)
	var damage:  float = power * (_stats.crit_damage if is_crit else 1.0)

	target.set_meta("lightning_kill", true)
	target.take_damage(int(damage), _stats.get_armor_pen(), is_crit, Util.DamageType.LIGHTNING)
	RelicOvercharged.add_stack(target)

	if _stats.slow_amount > 0.0 and is_instance_valid(target):
		target.apply_slow(_stats.slow_amount, _stats.slow_duration)

	ParticleManager.spawn_lightning_spark(target.global_position)

	# Soft synergy: extend field layer into areas direct abilities never aimed at.
	StaticField.spawn(target.global_position, power, get_parent())

	# Brief flash then remove.
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(queue_free)
