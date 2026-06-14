# ability_rain_of_crowns.gd
# ---------------------------------------------------------------------------
# Drops volleys of massive crowns that deal AOE damage and leave persistent
# craters (GoldCraters) — large triggerable zones where Gold crits cause
# bonus detonations.
#
# Without King's Treasury (no Fortune)
#   Falls back to a fixed cooldown using the ability's base cooldown stat.
#   Targets the densest cluster in range. Fully functional.
#
# Fortune bonus (requires King's Treasury)
#   Charges from Fortune spent by any Gold ability via crowns_charge in
#   GoldManager. When the charge threshold is met, fires a volley without
#   consuming a cooldown. Treasury activation also grants a free immediate
#   Crown volley via free_crown_pending. The more Fortune-heavy the build,
#   the more frequently Crowns fire.
#
# Synergies
#   ← Midas Curse     : Crowns prioritize marked enemy; auto-crit on impact
#   ← Fortune Engine  : engine_stacks consumed on impact for bonus damage
#                       and larger crater radius
#   ← King's Treasury : free_crown_pending triggers an immediate volley
# ---------------------------------------------------------------------------
class_name AbilityRainOfCrowns
extends AbilityData

const CrownScene: PackedScene = preload("res://scenes/abilities/gold_crown.tscn")
const CROWNS_PER_VOLLEY: int  = 3

func tick(context: Dictionary) -> void:
	super.tick(context)
	var player:      Node2D      = context["player"]
	var orb_potency: float       = context.get("orb_potency", 1.0)
	var gold:        GoldManager = context.get("gold", null)

	var should_fire: bool = false

	if gold != null:
		# Fortune-charge path.
		var charge_cost: float = get_stat("crowns_charge_cost")
		if charge_cost <= 0.0:
			charge_cost = 150.0

		context["orb_t"] = clampf(gold.crowns_charge / charge_cost, 0.0, 1.0)

		if gold.crowns_charge >= charge_cost:
			gold.crowns_charge = maxf(0.0, gold.crowns_charge - charge_cost)
			should_fire = true
		elif gold.free_crown_pending:
			gold.free_crown_pending = false
			should_fire = true
	else:
		# No Fortune: use standard cooldown (handled by base tick / super.tick).
		# super.tick returns true via context["cooldown_ready"] when ready.
		context["orb_t"] = context.get("cooldown_t", 0.0)
		should_fire = context.get("cooldown_ready", false)

	if not should_fire:
		return

	_fire_volley(player, orb_potency, gold)
	context["activated"] = true
	stats.apply_to_player(player)

func _fire_volley(player: Node2D, orb_potency: float, gold: GoldManager) -> void:
	var target_pos: Vector2 = _find_target_position(player, gold)

	var crown_drop_delay: float = get_stat("crown_drop_delay")
	if crown_drop_delay <= 0.0:
		crown_drop_delay = 0.6

	var power:    float = stats.get_stat("damage",              orb_potency, main_stats)
	var crater_r: float = stats.get_stat("crown_crater_radius", orb_potency, main_stats)
	if crater_r <= 0.0:
		crater_r = 72.0

	# Consume engine stacks for bonus damage and crater size this volley.
	var engine_stacks: int = gold.engine_stacks if gold != null else 0
	if gold != null:
		gold.engine_stacks = 0
	var engine_damage_bonus: float = 1.0 + engine_stacks * 0.08
	var engine_crater_bonus: float = engine_stacks * 2.0

	for i: int in range(CROWNS_PER_VOLLEY):
		var offset: Vector2 = Vector2(
			randf_range(-24.0, 24.0),
			randf_range(-24.0, 24.0)
		) if i > 0 else Vector2.ZERO

		var crown := CrownScene.instantiate() as GoldCrown
		player.get_parent().add_child(crown)
		crown.global_position = target_pos + offset + Vector2(0, -200)
		crown.setup(
			target_pos + offset,
			crown_drop_delay + i * 0.08,
			stats,
			orb_potency,
			main_stats,
			player,
			power * engine_damage_bonus,
			crater_r + engine_crater_bonus,
			gold
		)

func _find_target_position(player: Node2D, gold: GoldManager) -> Vector2:
	# Prefer marked enemy.
	if gold != null and is_instance_valid(gold.marked_enemy):
		return gold.marked_enemy.global_position

	if EnemyManager.living_enemies.is_empty():
		return player.global_position

	var fire_range: float = get_stat("range")
	if fire_range <= 0.0:
		fire_range = 300.0

	var best_pos:   Vector2 = player.global_position
	var best_count: int     = 0
	const CLUSTER_R:  float = 40.0
	const CLUSTER_R2: float = CLUSTER_R * CLUSTER_R

	for candidate: Enemy in EnemyManager.living_enemies:
		if not is_instance_valid(candidate):
			continue
		if player.global_position.distance_to(candidate.global_position) > fire_range:
			continue
		var count: int = 0
		for other: Enemy in EnemyManager.living_enemies:
			if is_instance_valid(other) and candidate.global_position.distance_squared_to(other.global_position) <= CLUSTER_R2:
				count += 1
		if count > best_count:
			best_count = count
			best_pos   = candidate.global_position

	return best_pos
