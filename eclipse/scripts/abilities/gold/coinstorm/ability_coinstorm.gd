# ability_coinstorm.gd
# ---------------------------------------------------------------------------
# Auto-fires a radial spray of spinning coins outward in all directions.
# Strong against crowds.
#
# Without King's Treasury (no Fortune)
#   Fires at its base aoe_radius every cooldown. Fully functional.
#
# Fortune bonus (requires King's Treasury)
#   Spends a fraction of current Fortune on each volley to expand the spray
#   radius. More Fortune → wider spray → more hits → more Fortune.
#   At zero Fortune the radius is just the base; at max it covers nearly
#   the full screen. The loop is self-reinforcing but never mandatory.
#
# Synergies
#   → Fortune Engine : many independent crit rolls per volley fill stacks fast
#   → King's Treasury: dense crowds can fill Treasury in one volley
#   ← Jackpot Wheel  : EXTRA_COINSTORM doubles projectile_count this volley
# ---------------------------------------------------------------------------
class_name AbilityCoinstorm
extends AbilityData

const CoinScene := preload("res://scenes/abilities/gold_coin.tscn")

# Fraction of current Fortune spent per volley to expand radius.
const FORTUNE_SPEND_FRACTION: float = 0.15
# Radius added per 100 Fortune spent.
const RADIUS_PER_FORTUNE:     float = 0.8

func tick(context: Dictionary) -> void:
	super.tick(context)
	var player:      Node2D = context["player"]
	var orb_potency: float  = context.get("orb_potency", 1.0)
	var gold:        GoldManager = context.get("gold", null)

	if EnemyManager.living_enemies.is_empty():
		return

	var orb_index: int     = context.get("orb_index", -1)
	var orb_spawn: Vector2 = player.global_position
	if orb_index >= 0 and orb_index < player.orb_visuals.size():
		orb_spawn = player.orb_visuals[orb_index].sprite.global_position

	var base_radius: float = get_stat("aoe_radius")
	if base_radius <= 0.0:
		base_radius = 40.0

	# Expand radius by spending Fortune (no-op if gold is null or fortune is 0).
	var spread_radius: float = base_radius
	if gold != null and gold.fortune > 0.0:
		var fortune_to_spend: float = gold.fortune * FORTUNE_SPEND_FRACTION
		var spent:            float = gold.spend_fortune(fortune_to_spend)
		spread_radius += spent * RADIUS_PER_FORTUNE

	# Jackpot Wheel: EXTRA_COINSTORM doubles count for this volley.
	var count: int = maxi(1, int(get_stat("projectile_count")))
	if gold != null and gold.wheel_ready and gold.wheel_outcome == GoldManager.WheelOutcome.EXTRA_COINSTORM:
		gold.consume_wheel_outcome()
		count *= 2

	var angle_step: float = TAU / float(count)
	for i: int in range(count):
		var angle: float  = angle_step * i + randf_range(-0.05, 0.05)
		var dir:   Vector2 = Vector2.RIGHT.rotated(angle)
		var coin := CoinScene.instantiate() as GoldCoin
		player.get_parent().add_child(coin)
		coin.global_position = orb_spawn
		coin.launch(dir, spread_radius, stats, orb_potency, main_stats, player, gold)

	# Orb glow from Fortune level; falls back to 0 if no manager.
	context["orb_t"]     = gold.fortune_fill() if gold != null else 0.0
	context["activated"] = true
	stats.apply_to_player(player)
