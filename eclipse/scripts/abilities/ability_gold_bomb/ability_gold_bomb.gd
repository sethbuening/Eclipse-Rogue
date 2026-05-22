class_name AbilityGoldBomb
extends AbilityData

const GoldBombScene := preload("res://scenes/abilities/gold_bomb.tscn")

func activate(context: Dictionary) -> void:
	if not context.get("pressed", false):
		return
	var player:    Node2D  = context["player"]
	var target:    Vector2 = context.get("target_pos", player.get_global_mouse_position())
	var orb_index: int     = context.get("orb_index", -1)
	var orb_spawn: Vector2 = player.global_position
	if orb_index >= 0 and orb_index < player.orb_visuals.size():
		orb_spawn = player.orb_visuals[orb_index].sprite.global_position
	var bomb := GoldBombScene.instantiate() as GoldBomb
	player.get_parent().add_child(bomb)
	bomb.launch(orb_spawn, target, stats, context.get("orb_potency", 1.0), context["tilemap"], main_stats, player)
	context["orb_t"] = 1.0
	context["activated"] = true
	stats.apply_to_player(player)
