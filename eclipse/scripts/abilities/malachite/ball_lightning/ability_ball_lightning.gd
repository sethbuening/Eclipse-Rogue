# ability_ball_lightning.gd
# ---------------------------------------------------------------------------
# Auto-spawns a BallLightning orb at the player's position on cooldown.
# The orb drifts toward the nearest enemy, pulsing damage as it moves.
#
# Hard synergies
#   → ConductorPost  : while drifting, the ball checks for nearby posts each
#                      frame.  If within BALL_SNAP_RADIUS of an unchained post,
#                      it calls post.notify_ball_nearby(); the post snaps the
#                      ball, fires an amplified pulse, then releases it.
#   ← LightningChain : the chain treats live BallLightning nodes as valid hop
#                      targets via Targeting.nearest_chain_target().  When
#                      hopped through, receive_chain_boost() is called, causing
#                      a brief amplified pulse burst at the orb's position.
#
# Soft synergy (StaticField / Gold metal)
#   Each pulse tick calls StaticField.spawn() at the pulse position, seeding
#   a moving trail of fields through the enemy group.
# ---------------------------------------------------------------------------
class_name AbilityBallLightning
extends AbilityData

const BallLightningScene := preload("res://scenes/abilities/ball_lightning.tscn")

func tick(context: Dictionary) -> void:
	super.tick(context)
	var player:      Node2D = context["player"]
	var orb_potency: float  = context.get("orb_potency", 1.0)

	# Don't spawn if no enemies are present — the ball would drift aimlessly.
	if EnemyManager.living_enemies.is_empty():
		return

	var orb_index: int     = context.get("orb_index", -1)
	var orb_spawn: Vector2 = player.global_position
	if orb_index >= 0 and orb_index < player.orb_visuals.size():
		orb_spawn = player.orb_visuals[orb_index].sprite.global_position

	var count: int = maxi(1, int(get_stat("projectile_count")))
	for _i in range(count):
		var ball := BallLightningScene.instantiate() as BallLightning
		player.get_parent().add_child(ball)
		ball.global_position = orb_spawn
		ball.setup(stats, orb_potency, main_stats)

	context["orb_t"]     = 1.0
	context["activated"] = true
	stats.apply_to_player(player)
