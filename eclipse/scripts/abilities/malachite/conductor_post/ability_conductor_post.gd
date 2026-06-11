# ability_conductor_post.gd
# ---------------------------------------------------------------------------
# Auto-places a ConductorPost at the best enemy-coverage position on cooldown.
# The post pulses slow + DoT to all enemies within its radius for its lifetime.
#
# Hard synergies
#   ← LightningChain : when a chain hop routes through this post,
#                      apply_bolt_bonus() is called on the post, charging it
#                      and granting bonus pierce + AOE to all later hops.
#   ← BallLightning  : when a BallLightning orb drifts within snap range of
#                      this post, it is briefly caught, fires an amplified
#                      pulse using the post's charge state, then continues.
#                      Both sides of this are handled in conductor_post.gd and
#                      ball_lightning.gd respectively.
#
# Soft synergy (StaticField / Gold metal)
#   The post does not spawn StaticFields directly (its damage is a slow tick,
#   not a discrete impact hit).  However, its slow keeps enemies inside the
#   radius of LightningChain and BallLightning, which do spawn fields —
#   the post indirectly densifies the field layer by keeping targets still.
# ---------------------------------------------------------------------------
class_name AbilityConductorPost
extends AbilityData

const ConductorPostScene := preload("res://scenes/abilities/conductor_post.tscn")

func tick(context: Dictionary) -> void:
	super.tick(context)
	var player:    Node2D = context["player"]
	var tilemap:   Node   = context.get("tilemap")
	var orb_index: int    = context.get("orb_index", -1)

	var cast_range: float = get_stat("range") if stats and stats.range > 0.0 else 0.0
	var aoe:        float = get_stat("aoe_radius") if stats else 32.0

	if EnemyManager.living_enemies.is_empty():
		return

	var spawn_pos: Vector2 = _best_placement(player, tilemap, cast_range, aoe)

	var enemies_covered: int = 0
	for enemy: Enemy in EnemyManager.living_enemies:
		if is_instance_valid(enemy) and spawn_pos.distance_to(enemy.global_position) <= aoe:
			enemies_covered += 1
	if enemies_covered == 0:
		return

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
## would cover the most enemies within aoe.  Falls back to player position.
func _best_placement(player: Node2D, tilemap: Node, cast_range: float, aoe: float) -> Vector2:
	if tilemap == null or EnemyManager.living_enemies.is_empty():
		return _safe_position(player, tilemap, player.global_position, cast_range)

	var candidates: Array[Vector2] = []
	var step_count: int = 12
	for i in range(step_count):
		var angle: float = (float(i) / float(step_count)) * TAU
		candidates.append(player.global_position + Vector2(cos(angle), sin(angle)) * cast_range * 0.85)

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


func _safe_position(player: Node2D, tilemap: Node, target: Vector2, cast_range: float) -> Vector2:
	var pos: Vector2 = _clamp_to_range(player.global_position, target, cast_range)
	if tilemap == null or tilemap.is_air(tilemap.world_to_map(pos)):
		return pos

	var to_player: Vector2 = player.global_position - pos
	var dist:      float   = to_player.length()
	if dist < 1.0:
		return pos
	var dir:    Vector2 = to_player / dist
	var step:   float   = 2.0
	var walked: float   = 0.0
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
