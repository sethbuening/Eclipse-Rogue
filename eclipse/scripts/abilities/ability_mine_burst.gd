# ability_mine_burst.gd
class_name AbilityMineBurst
extends AbilityData

func activate(context: Dictionary) -> void:
	var player: Node = context.get("player")
	if player == null:
		return
	var is_crit: bool = stats.roll_crit()
	var radius:  int  = stats.mining_radius + (1 if is_crit else 0)
	player.mine_around(player.global_position, radius)
	ParticleManager.spawn_focus_spark(player.global_position)
	if stats.light_on_hit > 0.0:
		context["light_gained"] = context.get("light_gained", 0.0) + stats.light_on_hit
	if is_crit and stats.light_on_crit > 0.0:
		context["light_gained"] = context.get("light_gained", 0.0) + stats.light_on_crit
