# ability_gilded_shot.gd
# ---------------------------------------------------------------------------
# Auto-fires toward the nearest enemy on cooldown. High base crit chance.
# The backbone of the Gold kit — reliable crit generation that works with
# or without Fortune.
#
# Overshoot mechanic
#   The projectile continues past its primary target by a fixed distance,
#   hitting nearby enemies at reduced crit chance during the overshoot.
#
# Fortune bonus (optional — requires King's Treasury)
#   When context["gold"] is present, any hit against the marked enemy
#   generates bonus Fortune. Crits against the mark generate extra Fortune
#   and apply the mark's crit damage bonus.
#
# Synergies
#   → King's Treasury : crits call GoldManager.on_gold_crit() → treasury fill
#   → Midas Curse     : bonus Fortune and crit damage on marked-enemy hits
#   → Fortune Engine  : failed crits increment engine_stacks
# ---------------------------------------------------------------------------
class_name AbilityGildedShot
extends AbilityData

const GildedShotScene := preload("res://scenes/abilities/gilded_shot.tscn")

func tick(context: Dictionary) -> void:
	super.tick(context)
	var player:      Node2D = context["player"]
	var orb_potency: float  = context.get("orb_potency", 1.0)

	var result: Util.TargetingResult = Targeting.nearest_enemy(player, get_stat("range"))
	if not result.found:
		return

	var orb_index: int     = context.get("orb_index", -1)
	var orb_spawn: Vector2 = player.global_position
	if orb_index >= 0 and orb_index < player.orb_visuals.size():
		orb_spawn = player.orb_visuals[orb_index].sprite.global_position

	var gold: GoldManager = context.get("gold", null)

	var shot := GildedShotScene.instantiate() as GildedShot
	player.get_parent().add_child(shot)
	shot.global_position = orb_spawn
	shot.launch(result.targets[0] as Enemy, stats, orb_potency, main_stats, player, gold)

	context["orb_t"]     = 1.0
	context["activated"] = true
	stats.apply_to_player(player)
