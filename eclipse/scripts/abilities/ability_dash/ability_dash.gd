class_name AbilityDash
extends AbilityData

func _init() -> void:
	main_stats = ["range"]

func activate(context: Dictionary) -> void:
	if not context.get("pressed", false):
		return
	var player: CharacterBody2D = context["player"]

	# Dash toward the nearest enemy, falling back to movement / facing direction.
	var dir: Vector2 = Targeting.dash_direction(player)

	# If there is a nearby enemy, prefer dashing toward it instead.
	@warning_ignore("shadowed_global_identifier")
	var range: float  = get_stat("range")
	var nearest: Util.TargetingResult = Targeting.nearest_enemy(player, range * 2.0)
	if nearest.found:
		dir = (nearest.position - player.global_position).normalized()

	# Step along the dash, stopping before any collision.
	var space:  PhysicsDirectSpaceState2D  = player.get_world_2d().direct_space_state
	var params: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		player.global_position,
		player.global_position + dir * range
	)
	params.exclude        = [player.get_rid()]
	params.collision_mask = player.collision_mask

	var result: Dictionary = space.intersect_ray(params)
	if result:
		player.global_position = result["position"] - dir * 5.0
	else:
		player.global_position += dir * range

	player.reset_physics_interpolation()
	context["orb_t"]     = 1.0
	context["activated"] = true
	stats.apply_to_player(player)
