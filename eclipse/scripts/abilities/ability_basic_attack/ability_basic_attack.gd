class_name AbilityBasicAttack
extends AbilityData

func _init() -> void:
	main_stats = ["power", "range", "projectile_speed"]

func activate(context: Dictionary) -> void:
	if not context.get("pressed", false):
		return
	var player: Node2D = context["player"]
	var tilemap: Node  = context["tilemap"]
	# Use the auto-targeted position supplied by the player script.
	# Falls back to mouse position if not provided (e.g. hold-ability path).
	var target: Vector2 = context.get("target_pos", player.get_global_mouse_position())
	var dir:    Vector2 = (target - player.global_position).normalized()
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
