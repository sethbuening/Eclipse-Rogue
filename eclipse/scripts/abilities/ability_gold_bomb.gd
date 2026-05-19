class_name AbilityGoldBomb
extends AbilityData

const GoldBombScene := preload("res://scenes/abilities/gold_bomb.tscn")

func activate(context: Dictionary) -> void:
	tick_cooldown(context.get("delta", 0.0))
	if not context.get("pressed", false) or not is_ready():
		return
	var player: Node2D  = context["player"]
	var target: Vector2 = player.get_global_mouse_position()
	var bomb := GoldBombScene.instantiate() as GoldBomb
	if bomb.has_node("AnimatedSprite2D"):
		bomb.get_node("AnimatedSprite2D").visible = false
	player.get_parent().add_child(bomb)
	# find the orb visual sprite's global position
	var orb_index: int     = context.get("orb_index", -1)
	var orb_spawn: Vector2 = player.global_position
	if orb_index >= 0 and orb_index < player.orb_visuals.size():
		orb_spawn = player.orb_visuals[orb_index].sprite.global_position
	bomb.global_position = orb_spawn
	bomb.setup(target, stats, context.get("power", 1.0))
	start_cooldown()
	context["orb_t"]      = 1.0
	context["shatter"]    = true
	context["spark"]      = false
	stats.apply_to_player(context["player"])
