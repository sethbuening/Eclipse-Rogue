class_name AbilityConductorPost
extends AbilityData

const ConductorPostScene := preload("res://scenes/abilities/conductor_post.tscn")

func activate(context: Dictionary) -> void:
	if not context.get("pressed", false):
		return
	var player:    Node2D = context["player"]
	var tilemap:   Node   = context.get("tilemap")
	var spawn_pos: Vector2 = context.get("target_pos", player.get_global_mouse_position())
	var orb_index: int = context.get("orb_index", -1)
	if orb_index >= 0 and orb_index < player.orb_visuals.size():
		player.orb_visuals[orb_index].sprite.global_position = spawn_pos
	var post := ConductorPostScene.instantiate() as ConductorPost
	player.get_parent().add_child(post)
	post.global_position = spawn_pos
	post.setup(stats, context.get("orb_potency", 1.0), main_stats, tilemap)
	context["orb_t"] = 1.0
	context["activated"] = true
	stats.apply_to_player(player)
