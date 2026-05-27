class_name AbilityConductorPost
extends AbilityData

const ConductorPostScene := preload("res://scenes/abilities/conductor_post.tscn")

func activate(context: Dictionary) -> void:
	if not context.get("pressed", false):
		return
	var player:    Node2D = context["player"]
	var tilemap:   Node   = context.get("tilemap")
	var orb_index: int    = context.get("orb_index", -1)

	var cast_range: float = get_stat("range") if stats and stats.range > 0.0 else 0.0
	var aoe:        float = get_stat("aoe_radius") if stats else 32.0

	# Auto-place: find the best open position that covers the most enemies,
	# radiating from the player — no cursor or aim input needed.
	var spawn_pos: Vector2 = _best_placement(player, tilemap, cast_range, aoe)

	if orb_index >= 0 and orb_index < player.orb_visuals.size():
		player.orb_visuals[orb_index].sprite.global_position = spawn_pos

	var post := ConductorPostScene.instantiate() as ConductorPost
	player.get_parent().add_child(post)
	post.global_position = spawn_pos
	post.setup(stats, context.get("orb_potency", 1.0), main_stats, tilemap)
	context["orb_t"]     = 1.0
	context["activated"] = true
	stats.apply_to_player(player)


## Find the best open air-tile position within cast_range of the player that
## would cover the most enemies within aoe.  Falls back to the player's
## position if nothing better is found.
func _best_placement(player: Node2D, tilemap: Node, cast_range: float, aoe: float) -> Vector2:
	if tilemap == null or EnemyManager.living_enemies.is_empty():
		return _safe_position(player, tilemap, player.global_position, cast_range)

	# Score candidate positions by how many enemies fall within aoe.
	# Candidates: a ring of points at cast_range around the player, plus the
	# centroid of nearby enemies (which tends to be the sweet spot).
	var candidates: Array[Vector2] = []
	var step_count: int = 12
	for i in range(step_count):
		var angle: float = (float(i) / float(step_count)) * TAU
		candidates.append(player.global_position + Vector2(cos(angle), sin(angle)) * cast_range * 0.85)

	# Add centroid of enemies within 2× cast_range as a bonus candidate.
	var centroid := Vector2.ZERO
	var count:     int = 0
	for enemy: Enemy in EnemyManager.living_enemies:
		if not is_instance_valid(enemy):
			continue
		if player.global_position.distance_to(enemy.global_position) <= cast_range * 2.0:
			centroid += enemy.global_position
			count    += 1
	if count > 0:
		candidates.append(_clamp_to_range(player.global_position, centroid / float(count), cast_range))

	var best_pos:   Vector2 = player.global_position
	var best_score: int     = -1
	for candidate: Vector2 in candidates:
		var safe: Vector2 = _safe_position(player, tilemap, candidate, cast_range)
		var score: int    = 0
		for enemy: Enemy in EnemyManager.living_enemies:
			if is_instance_valid(enemy) and safe.distance_to(enemy.global_position) <= aoe:
				score += 1
		if score > best_score:
			best_score = score
			best_pos   = safe

	return best_pos


## Walk from `target` toward the player until we reach an open air tile,
## clamped to cast_range.
func _safe_position(player: Node2D, tilemap: Node, target: Vector2, cast_range: float) -> Vector2:
	var pos: Vector2 = _clamp_to_range(player.global_position, target, cast_range)
	if tilemap == null or tilemap.is_air(tilemap.world_to_map(pos)):
		return pos

	var to_player: Vector2 = player.global_position - pos
	var dist:      float   = to_player.length()
	if dist < 1.0:
		return pos
	var dir:  Vector2 = to_player / dist
	var step: float   = 2.0
	var walked: float = 0.0
	while walked < dist:
		walked   += step
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
