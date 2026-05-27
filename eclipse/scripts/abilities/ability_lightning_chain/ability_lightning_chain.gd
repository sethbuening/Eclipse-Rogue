class_name AbilityLightningChain
extends AbilityData

const LightningChainScene := preload("res://scenes/abilities/lightning_chain.tscn")

func tick(context: Dictionary) -> void:
	super.tick(context)
	var player:      Node2D = context["player"]
	var orb_potency: float  = context.get("orb_potency", 1.0)

	var chain_range:  float  = get_stat("range")
	# Prefer a post as the first hop if it's closer and has enemies in reach;
	# otherwise go straight for the nearest enemy.
	var first_target: Node2D = Targeting.nearest_chain_first_target(
		player.global_position, chain_range, get_stat("aoe_radius")
	)
	if first_target == null:
		return

	var chain:    Array[Node2D] = [first_target]
	var hit_set:  Array[Node2D] = [first_target]
	var from_pos: Vector2       = first_target.global_position
	var bonus_pierce: int   = 0
	var bonus_aoe:    float = 0.0

	var total_pierce: int = int(get_stat("pierce")) + bonus_pierce
	for _i in range(total_pierce):
		var next: Node2D = Targeting.nearest_chain_target(
			from_pos, get_stat("aoe_radius") + bonus_aoe, hit_set
		)
		if next == null:
			break
		chain.append(next)
		hit_set.append(next)
		if next is ConductorPost:
			(next as ConductorPost).apply_bolt_bonus(context)
			bonus_pierce += context.get("bonus_pierce", 0)
			bonus_aoe    += context.get("bonus_aoe",    0.0)
			total_pierce  = int(get_stat("pierce")) + bonus_pierce
		from_pos = next.global_position

	var arc := LightningChainScene.instantiate() as LightningChain
	player.get_parent().add_child(arc)
	var orb_index: int     = context.get("orb_index", -1)
	var orb_spawn: Vector2 = player.global_position
	if orb_index >= 0 and orb_index < player.orb_visuals.size():
		orb_spawn = player.orb_visuals[orb_index].sprite.global_position
	arc.setup(orb_spawn, chain, stats, orb_potency, main_stats, player)

	context["orb_t"]     = 1.0
	context["activated"] = true
	stats.apply_to_player(player)
