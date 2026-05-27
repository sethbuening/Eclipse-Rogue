class_name AbilityBasicAttack
extends AbilityData

func _init() -> void:
	main_stats = ["power", "range", "projectile_speed"]

func activate(context: Dictionary) -> void:
	if not context.get("pressed", false):
		return
	var player: Node2D = context["player"]
	var tilemap: Node  = context["tilemap"]

	# Auto-target: nearest enemy, fall back to nearest tile — no aiming required.
	var result: Util.TargetingResult = Targeting.nearest_enemy_or_tile(
		player, tilemap, get_stat("range")
	)
	if not result.found:
		return

	var dir: Vector2 = (result.position - player.global_position).normalized()
	var traveller := BasicAttackTraveller.new()
	traveller.init(
		player.global_position,
		dir,
		get_stat("power"),
		get_stat("range"),
		get_stat("projectile_speed"),
		tilemap,
		player,
		get_stat("mining_power")
	)
	player.get_parent().add_child(traveller)
	context["activated"] = true
	stats.apply_to_player(player)
