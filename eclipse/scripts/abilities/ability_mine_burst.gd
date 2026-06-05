# ability_mine_burst.gd
class_name AbilityMineBurst
extends AbilityData

func tick(context: Dictionary) -> void:
	super.tick(context)
	var player: Node = context.get("player")
	if player == null:
		return
	var is_crit: bool = stats.roll_crit(player)
	var radius:  int  = stats.mining_radius + (1 if is_crit else 0)
	player.mine_around(player.global_position, radius)
	ParticleManager.spawn_focus_spark(player.global_position)
