# ability_lightning_chain.gd
# ---------------------------------------------------------------------------
# Auto-fires toward the nearest enemy (or ConductorPost) on cooldown.
# Hops between targets, dealing slightly less damage with each hop.
# ---------------------------------------------------------------------------
class_name AbilityLightningChain
extends AbilityData

const LightningChainScene := preload("res://scenes/abilities/lightning_chain.tscn")

func _init() -> void:
	id                    = "lightning_chain"
	ore_type              = "malachite"
	display_name          = "Lightning Chain"
	description           = "Fires a bolt that chains between nearby enemies."

func tick(context: Dictionary) -> void:
	super.tick(context)

	if not is_ready():
		return

	var player: Node2D = context["player"]

	var first_target: Node2D = Targeting.nearest_chain_first_target(
		player.global_position, get_stat("range"), get_stat("aoe_radius")
	)
	if first_target == null:
		return

	# Target found and cooldown elapsed — fire and start cooldown.
	trigger_cooldown()

	var chain:        Array[Node2D] = [first_target]
	var hit_set:      Array[Node2D] = [first_target]
	var from_pos:     Vector2       = first_target.global_position
	var bonus_pierce: int           = 0
	var bonus_aoe:    float         = 0.0

	var total_pierce: int = int(get_stat("chain_length")) + bonus_pierce
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
			total_pierce  = int(get_stat("chain_length")) + bonus_pierce
		elif next is BallLightning:
			(next as BallLightning).receive_chain_boost()

		from_pos = next.global_position

	var arc := LightningChainScene.instantiate() as LightningChain
	player.get_parent().add_child(arc)
	arc.setup(player.global_position, chain, stats, _orb_potency, main_stats, player)

	context["activated"] = true
	stats.apply_to_player(player)
