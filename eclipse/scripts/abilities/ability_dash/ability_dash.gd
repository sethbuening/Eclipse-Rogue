class_name AbilityDash
extends AbilityData

func _init() -> void:
	main_stats = ["range"]

func activate(context: Dictionary) -> void:
	if not context.get("pressed", false):
		return
	var player: CharacterBody2D = context["player"]
	# Use aim direction: right joystick if controller, else mouse cursor.
	# Falls back to the player's facing direction if neither provides input.
	var target_pos: Vector2 = context.get("target_pos", Vector2.ZERO)
	var dir: Vector2
	if target_pos != Vector2.ZERO:
		dir = (target_pos - player.global_position).normalized()
	else:
		# Fallback: right joystick or movement direction
		var joy: Vector2 = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
		if joy.length() > 0.2:
			dir = joy.normalized()
		else:
			var move: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
			dir = move.normalized() if move != Vector2.ZERO else Vector2(player.direction)
	@warning_ignore("shadowed_global_identifier")
	var range: float   = get_stat("range")

	# step along the dash in small increments, stopping before any collision
	var space:    PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var params:   PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		player.global_position,
		player.global_position + dir * range
	)
	params.exclude        = [player.get_rid()]
	params.collision_mask = player.collision_mask

	var result: Dictionary = space.intersect_ray(params)
	if result:
		# land just before the collision point
		var safe_pos: Vector2 = result["position"] - dir * 5.0
		player.global_position = safe_pos
	else:
		player.global_position += dir * range

	player.reset_physics_interpolation()
	context["orb_t"]     = 1.0
	context["activated"] = true
	stats.apply_to_player(player)
