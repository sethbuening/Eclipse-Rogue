# gilded_shot.gd
# ---------------------------------------------------------------------------
# Projectile for AbilityGildedShot.
# Phase 1: travels to primary target, deals a normal (possibly critting) hit.
# Phase 2 (overshoot): continues past the primary along the same axis,
#   hitting nearby enemies at reduced crit chance until range is exhausted.
#
# gold_manager may be null if King's Treasury is not equipped. All calls
# through it are null-guarded; the projectile works fully without it.
# ---------------------------------------------------------------------------
class_name GildedShot
extends Node2D

const TRAVEL_SPEED:         float = 480.0
const OVERSHOOT_DISTANCE:   float = 80.0
const OVERSHOOT_HIT_RADIUS: float = 14.0
const OVERSHOOT_CRIT_SCALE: float = 0.4

var _stats:       AbilityStats
var _orb_potency: float
var _main_stats:  Array[String]
var _player:      CharacterBody2D
var _gold:        GoldManager   # may be null

var _primary:       Enemy        = null
var _primary_hit:   bool         = false
var _direction:     Vector2      = Vector2.RIGHT
var _overshoot_end: Vector2      = Vector2.ZERO
var _overshoot_hit: Array[Enemy] = []

func _ready() -> void:
	set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)

func launch(
	primary:       Enemy,
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
	_primary     = primary
	_direction   = (primary.global_position - global_position).normalized()
	_overshoot_end = primary.global_position + _direction * OVERSHOOT_DISTANCE
	reset_physics_interpolation()

func _process(delta: float) -> void:
	var step: float = TRAVEL_SPEED * delta
	global_position += _direction * step

	if not _primary_hit:
		var target_pos: Vector2 = _primary.global_position if is_instance_valid(_primary) else _overshoot_end
		if global_position.distance_to(target_pos) <= step + 2.0:
			if is_instance_valid(_primary):
				_deal_hit(_primary, _stats.crit_chance)
			_primary_hit = true
	else:
		var r2: float = OVERSHOOT_HIT_RADIUS * OVERSHOOT_HIT_RADIUS
		for enemy: Enemy in EnemyManager.living_enemies:
			if not is_instance_valid(enemy) or enemy == _primary or enemy in _overshoot_hit:
				continue
			if global_position.distance_squared_to(enemy.global_position) <= r2:
				_overshoot_hit.append(enemy)
				_deal_hit(enemy, _stats.crit_chance * OVERSHOOT_CRIT_SCALE)

		if global_position.distance_to(_overshoot_end) <= step + 2.0:
			queue_free()

func _deal_hit(enemy: Enemy, effective_crit_chance: float) -> void:
	var power: float = _stats.get_stat("power", _orb_potency, _main_stats)

	var is_crit: bool = false
	if _player != null and _player.guaranteed_crits > 0:
		_player.guaranteed_crits -= 1
		is_crit = true
	else:
		is_crit = randf() < effective_crit_chance

	# Fortune bonus for hitting a marked enemy (only when gold is present).
	var is_marked: bool = _gold != null and is_instance_valid(_gold.marked_enemy) and enemy == _gold.marked_enemy
	if is_marked:
		_gold.add_fortune(power * 0.08, _player)

	if is_crit:
		var crit_mult: float = _resolve_crit_mult()

		if is_marked:
			crit_mult *= 1.0 + _stats.get_stat("curse_crit_damage_bonus", _orb_potency, _main_stats)
			_gold.add_fortune(power * 0.12, _player)

		var damage: float = power * crit_mult
		if _gold != null:
			var engine_bonus: float = _gold.on_gold_crit(
				enemy.global_position, crit_mult, StaticField.TRIGGER_RADIUS, _player
			)
			damage *= engine_bonus
		enemy.take_damage(int(damage), _stats.get_armor_pen(), true, Util.DamageType.PHYSICAL)
	else:
		# Failed crit: increment engine stacks if manager is present.
		if _gold != null:
			_gold.engine_stacks = mini(_gold.engine_stacks + 1, _gold.engine_stack_cap)
		enemy.take_damage(int(power), _stats.get_armor_pen(), false, Util.DamageType.PHYSICAL)

	apply_hit_effects(enemy, _player, is_crit, global_position)
	ParticleManager.spawn_gold_bomb_trail(enemy.global_position)

## Resolve a crit multiplier, consuming a Wheel outcome if one is ready.
## Outcomes that Gilded Shot can't use are put back for the next ability.
func _resolve_crit_mult() -> float:
	if _gold == null or not _gold.wheel_ready:
		return _stats.crit_damage

	var outcome: GoldManager.WheelOutcome = _gold.consume_wheel_outcome()
	match outcome:
		GoldManager.WheelOutcome.DOUBLE_CRIT:
			return _stats.crit_damage * 2.0
		GoldManager.WheelOutcome.TRIPLE_CRIT:
			return _stats.crit_damage * 3.0
		GoldManager.WheelOutcome.FORTUNE_BURST:
			_gold.add_fortune(60.0, _player)
			return _stats.crit_damage
		GoldManager.WheelOutcome.GUARANTEED_CRITS:
			if _player != null:
				_player.guaranteed_crits += 4
			return _stats.crit_damage
		_:
			# Not for this ability — put back.
			_gold.wheel_outcome = outcome
			_gold.wheel_ready   = true
			return _stats.crit_damage

func apply_hit_effects(enemy: Enemy, player: CharacterBody2D, _is_crit: bool, hit_origin: Vector2) -> void:
	if not is_instance_valid(enemy):
		return
	if _stats.knockback > 0.0:
		var dir: Vector2 = (enemy.global_position - hit_origin).normalized()
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(dir * _stats.knockback)
	if _stats.stun_duration > 0.0 and enemy.has_method("apply_stun"):
		enemy.apply_stun(_stats.stun_duration)
	if _stats.slow_amount > 0.0 and enemy.has_method("apply_slow"):
		enemy.apply_slow(_stats.slow_amount, _stats.slow_duration)
