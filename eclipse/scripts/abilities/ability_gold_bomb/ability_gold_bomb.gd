class_name AbilityGoldBomb
extends AbilityData

const GoldBombScene := preload("res://scenes/abilities/gold_bomb.tscn")

func activate(context: Dictionary) -> void:
	if not context.get("pressed", false):
		return
	var player:    Node2D  = context["player"]
	var orb_index: int     = context.get("orb_index", -1)
	var orb_spawn: Vector2 = player.global_position
	if orb_index >= 0 and orb_index < player.orb_visuals.size():
		orb_spawn = player.orb_visuals[orb_index].sprite.global_position

	# Auto-target: nearest enemy, fall back to nearest tile — no aiming needed.
	var result: Util.TargetingResult = Targeting.nearest_enemy_or_tile(
		player, context.get("tilemap"), get_stat("range")
	)
	if not result.found:
		return

	var bomb := GoldBombScene.instantiate() as GoldBomb
	player.get_parent().add_child(bomb)
	bomb.launch(orb_spawn, result.position, stats, context.get("orb_potency", 1.0), context["tilemap"], main_stats, player)
	context["orb_t"]     = 1.0
	context["activated"] = true
	stats.apply_to_player(player)
