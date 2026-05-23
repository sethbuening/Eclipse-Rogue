class_name AbilityConductorPost
extends AbilityData

const ConductorPostScene := preload("res://scenes/abilities/conductor_post.tscn")

func activate(context: Dictionary) -> void:
	if not context.get("pressed", false):
		return
	var player:    Node2D = context["player"]
	var tilemap:   Node   = context.get("tilemap")
	var orb_index: int    = context.get("orb_index", -1)

	var aim:        Vector2 = context.get("target_pos", player.get_global_mouse_position())
	var cast_range: float   = get_stat("range") if stats and stats.range > 0.0 else 0.0
	var aoe:        float   = get_stat("aoe_radius") if stats else 32.0

	# Find the best placement within cast_range that covers the most enemies
	# and tiles.  Falls back to the raw cursor position (clamped to cast_range)
	# if nothing is in range to score.
	var spawn_pos: Vector2 = _best_placement(player, tilemap, aim, cast_range, aoe)

	if orb_index >= 0 and orb_index < player.orb_visuals.size():
		player.orb_visuals[orb_index].sprite.global_position = spawn_pos

	var post := ConductorPostScene.instantiate() as ConductorPost
	player.get_parent().add_child(post)
	post.global_position = spawn_pos
	post.setup(stats, context.get("orb_potency", 1.0), main_stats, tilemap)
	context["orb_t"]     = 1.0
	context["activated"] = true
	stats.apply_to_player(player)

func _best_placement(player: Node2D, tilemap: Node, aim: Vector2,
		cast_range: float, _aoe: float) -> Vector2:
	var pos: Vector2 = _clamp_to_range(player.global_position, aim, cast_range)

	if tilemap == null:
		return pos

	if tilemap.is_air(tilemap.world_to_map(pos)):
		return pos

	# Walk from the clamped position toward the player in small steps
	# until we exit the solid tile.
	var to_player: Vector2 = player.global_position - pos
	var dist:      float   = to_player.length()
	if dist < 1.0:
		return pos  # already at player, give up
	var dir:       Vector2 = to_player / dist
	var step:      float   = 2.0  # pixels per step, smaller = more precise

	var walked: float = 0.0
	while walked < dist:
		walked += step
		var candidate: Vector2 = pos + dir * walked
		if tilemap.is_air(tilemap.world_to_map(candidate)):
			return candidate

	return player.global_position


func _clamp_to_range(origin: Vector2, target: Vector2, range: float) -> Vector2:
	if range <= 0.0:
		return target
	var offset: Vector2 = target - origin
	if offset.length() > range:
		return origin + offset.normalized() * range
	return target
