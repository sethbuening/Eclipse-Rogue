# gold_coin.gd
# ---------------------------------------------------------------------------
# Single coin projectile spawned by AbilityCoinstorm.
# Travels outward in a fixed direction, spinning visually.
# Deals damage (with independent crit roll) to each enemy it passes through
# up to its pierce count.
#
# gold_manager may be null if King's Treasury is not equipped. All calls
# through it are null-guarded.
# ---------------------------------------------------------------------------
class_name GoldCoin
extends Node2D

var _stats:       AbilityStats
var _orb_potency: float
var _main_stats:  Array[String]
var _player:      CharacterBody2D
var _gold:        GoldManager   # may be null

var _direction:   Vector2      = Vector2.RIGHT
var _max_range:   float        = 80.0
var _travelled:   float        = 0.0
var _hit:         Array[Enemy] = []
var _pierce_left: int          = 0

const TRAVEL_SPEED: float = 320.0
const HIT_RADIUS:   float = 8.0

func _ready() -> void:
	set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)

func launch(
	direction:     Vector2,
	max_range:     float,
	ability_stats: AbilityStats,
	orb_potency:   float,
	main_stats:    Array[String],
	player:        CharacterBody2D,
	gold:          GoldManager
) -> void:
	_stats       = ability_stats
	_orb_potency = orb_potency
	_main_stats  = main_stats
	_player      = player
	_gold        = gold
	_direction   = direction.normalized()
	_max_range   = max_range
	_pierce_left = maxi(0, int(_stats.pierce)) if _stats.pierce > 0 else 0
	reset_physics_interpolation()

func _process(delta: float) -> void:
	var step: float = TRAVEL_SPEED * delta
	global_position += _direction * step
	_travelled      += step

	if has_node("Sprite2D"):
		$Sprite2D.rotation += delta * 12.0

	var r2: float = HIT_RADIUS * HIT_RADIUS
	for enemy: Enemy in EnemyManager.living_enemies:
		if not is_instance_valid(enemy) or enemy in _hit:
			continue
		if global_position.distance_squared_to(enemy.global_position) > r2:
			continue

		_hit.append(enemy)
		_deal_hit(enemy)

		if _pierce_left <= 0:
			queue_free()
			return
		_pierce_left -= 1

	if _travelled >= _max_range:
		queue_free()

func _deal_hit(enemy: Enemy) -> void:
	var power:   float = _stats.get_stat("power", _orb_potency, _main_stats)
	var is_crit: bool  = _stats.roll_crit(_player)

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

	ParticleManager.spawn_gold_bomb_trail(enemy.global_position)
