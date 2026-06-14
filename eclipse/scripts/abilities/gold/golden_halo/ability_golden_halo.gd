# ability_golden_halo.gd
# ---------------------------------------------------------------------------
# A ring of golden coins orbits the player, damaging enemies on contact.
# High hit frequency — excellent for close-range play.
#
# Without King's Treasury (no Fortune)
#   Ring is fixed at halo_min_radius. Fully functional — it just doesn't
#   expand. Good for close-range builds that don't run Treasury.
#
# Fortune bonus (requires King's Treasury)
#   Ring radius scales linearly from halo_min_radius to halo_max_radius
#   based on Fortune fill. During Royal Wealth it locks to max radius.
#   Low Fortune → tight ring (builds Fortune fast by forcing close range).
#   High Fortune → wide ring (sustains Fortune by intercepting at range).
#
# Synergies
#   → Fortune Engine  : rapid contact hits generate failed-crit stacks
#   → King's Treasury : high hit frequency while surrounded charges Treasury
# ---------------------------------------------------------------------------
class_name AbilityGoldenHalo
extends AbilityData

const HIT_INTERVAL: float = 0.12

var _hit_timer: float = 0.0

func tick(context: Dictionary) -> void:
	super.tick(context)
	var player:      Node2D      = context["player"]
	var orb_potency: float       = context.get("orb_potency", 1.0)
	var delta:       float       = context.get("delta", 0.0)
	var gold:        GoldManager = context.get("gold", null)

	_hit_timer += delta
	if _hit_timer < HIT_INTERVAL:
		context["orb_t"] = _hit_timer / HIT_INTERVAL
		return

	_hit_timer = 0.0

	var min_r: float = get_stat("halo_min_radius")
	var max_r: float = get_stat("halo_max_radius")
	if min_r <= 0.0: min_r = 28.0
	if max_r <= 0.0: max_r = 96.0

	# Without Fortune: fixed at min radius. With Fortune: interpolate.
	var radius: float
	if gold == null:
		radius = min_r
	elif gold.royal_wealth_active:
		radius = max_r
	else:
		radius = lerp(min_r, max_r, gold.fortune_fill())

	var r2:    float = radius * radius
	var power: float = stats.get_stat("damage", orb_potency, main_stats)

	for enemy: Enemy in EnemyManager.living_enemies:
		if not is_instance_valid(enemy):
			continue
		if player.global_position.distance_squared_to(enemy.global_position) > r2:
			continue

		var is_crit: bool = stats.roll_crit(player)

		if is_crit:
			var crit_mult: float = stats.crit_damage
			var damage:    float = power * crit_mult
			if gold != null:
				var engine_bonus: float = gold.on_gold_crit(
					enemy.global_position, crit_mult, StaticField.TRIGGER_RADIUS, player
				)
				damage *= engine_bonus
			enemy.take_damage(int(damage), stats.get_armor_pen(), true, Util.DamageType.PHYSICAL)
		else:
			if gold != null:
				gold.engine_stacks = mini(gold.engine_stacks + 1, gold.engine_stack_cap)
			enemy.take_damage(int(power), stats.get_armor_pen(), false, Util.DamageType.PHYSICAL)

		ParticleManager.spawn_gold_bomb_trail(enemy.global_position)

	# Orb glow: Fortune fill if present, else 0.
	context["orb_t"] = gold.fortune_fill() if gold != null else 0.0
