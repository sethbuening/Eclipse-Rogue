# gold_crown.gd
# ---------------------------------------------------------------------------
# Crown projectile spawned by AbilityRainOfCrowns.
# Falls from above after a delay, then impacts: deals AOE damage and leaves
# a persistent GoldCrater.
#
# gold_manager may be null if King's Treasury is not equipped. All calls
# through it are null-guarded.
# ---------------------------------------------------------------------------
class_name GoldCrown
extends Node2D

# Time between targeting reticle and impact — internal to the projectile,
# no need to expose this in ability_stats.
const DEFAULT_DROP_DELAY: float = 0.6

var _stats:          AbilityStats
var _orb_potency:    float
var _main_stats:     Array[String]
var _player:         CharacterBody2D
var _gold:           GoldManager   # may be null
var _target:         Vector2
var _delay:          float
var _override_power: float
var _crater_radius:  float

var _elapsed: float = 0.0
var _dropped: bool  = false
var _start_y: float = 0.0

func _ready() -> void:
	set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)

func setup(
	target:         Vector2,
	delay:          float,
	ability_stats:  AbilityStats,
	orb_potency:    float,
	main_stats:     Array[String],
	player:         CharacterBody2D,
	override_power: float,
	crater_radius:  float,
	gold:           GoldManager
) -> void:
	_target         = target
	_delay          = delay if delay > 0.0 else DEFAULT_DROP_DELAY
	_stats          = ability_stats
	_orb_potency    = orb_potency
	_main_stats     = main_stats
	_player         = player
	_override_power = override_power
	_crater_radius  = crater_radius
	_gold           = gold
	_start_y        = global_position.y
	reset_physics_interpolation()

func _process(delta: float) -> void:
	_elapsed += delta

	if _elapsed < _delay:
		var t:     float = _elapsed / _delay
		var eased: float = t * t
		global_position.y = lerp(_start_y, _target.y, eased)
		global_position.x = _target.x
		return

	if not _dropped:
		_dropped = true
		_impact()

func _impact() -> void:
	global_position = _target
	reset_physics_interpolation()

	var radius:    float = _crater_radius
	var radius_sq: float = radius * radius
	var power:     float = _override_power

	# Auto-crit if marked enemy is within impact radius.
	var midas_auto_crit: bool = false
	if _gold != null and is_instance_valid(_gold.marked_enemy):
		if _target.distance_squared_to(_gold.marked_enemy.global_position) <= radius_sq:
			midas_auto_crit = true

	for enemy: Enemy in EnemyManager.living_enemies.duplicate():
		if not is_instance_valid(enemy):
			continue
		if _target.distance_squared_to(enemy.global_position) > radius_sq:
			continue

		var is_crit: bool = midas_auto_crit or _stats.roll_crit(_player)

		if is_crit:
			var crit_mult: float = _stats.crit_damage
			var damage:    float = power * crit_mult
			if _gold != null:
				var eng: float = _gold.on_gold_crit(
					enemy.global_position, crit_mult, StaticField.TRIGGER_RADIUS, _player
				)
				damage *= eng
			enemy.take_damage(int(damage), _stats.get_armor_pen(), true, Util.DamageType.PHYSICAL)
		else:
			if _gold != null:
				_gold.engine_stacks = mini(_gold.engine_stacks + 1, _gold.engine_stack_cap)
			enemy.take_damage(int(power), _stats.get_armor_pen(), false, Util.DamageType.PHYSICAL)

		if _stats.knockback > 0.0:
			var dir: Vector2 = (enemy.global_position - _target).normalized()
			if enemy.has_method("apply_knockback"):
				enemy.apply_knockback(dir * _stats.knockback)

		ParticleManager.spawn_gold_bomb_trail(enemy.global_position)

	var crater := GoldCrater.new()
	crater.global_position = _target
	get_parent().add_child(crater)
	crater.activate(_crater_radius, _override_power)

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)
