# ability_lightning_chain.gd
class_name AbilityLightningChain
extends AbilityData

const LightningChainScene := preload("res://scenes/abilities/lightning_chain.tscn")

func activate(context: Dictionary) -> void:
	tick_cooldown(context.get("delta", 0.0))
	if not context.get("pressed", false) or not is_ready():
		return

	var player:    Node2D = context["player"]
	var orb_power: float  = context.get("power", 1.0)

	# EnemyManager is an autoload that tracks all living enemies directly —
	# no scene-tree walk needed.
	var all_enemies: Array[Enemy] = EnemyManager.living_enemies

	# ── 1. Find the first target ───────────────────────────────────────────────
	var first_target: Enemy = _find_nearest_enemy(
		player.global_position,
		stats.range * orb_power,
		[],
		all_enemies
	)
	if first_target == null:
		return

	# ── 2. Build the full chain ────────────────────────────────────────────────
	var chain:    Array[Enemy]  = [first_target]
	var hit_set:  Array[Node2D] = [first_target]
	var from_pos: Vector2       = first_target.global_position

	for _i in range(int(stats.pierce * orb_power)):
		var next: Enemy = _find_nearest_enemy(
			from_pos,
			stats.aoe_radius * orb_power,
			hit_set,
			all_enemies
		)
		if next == null:
			break
		chain.append(next)
		hit_set.append(next)
		from_pos = next.global_position

	# ── 3. Spawn the visual / hit-application node ─────────────────────────────
	var arc := LightningChainScene.instantiate() as LightningChain
	player.get_parent().add_child(arc)

	var orb_index: int     = context.get("orb_index", -1)
	var orb_spawn: Vector2 = player.global_position
	if orb_index >= 0 and orb_index < player.orb_visuals.size():
		orb_spawn = player.orb_visuals[orb_index].sprite.global_position

	arc.setup(orb_spawn, chain, stats, orb_power)

	# ── 4. Wrap up ─────────────────────────────────────────────────────────────
	start_cooldown()
	context["orb_t"]   = 1.0
	context["shatter"] = true
	context["spark"]   = false
	stats.apply_to_player(player)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _find_nearest_enemy(
	origin:     Vector2,
	radius:     float,
	exclude:    Array[Node2D],
	candidates: Array[Enemy]
) -> Enemy:
	var best_dist: float = radius * radius
	var best:      Enemy = null

	for enemy: Enemy in candidates:
		if not is_instance_valid(enemy) or enemy in exclude:
			continue
		var d2: float = origin.distance_squared_to(enemy.global_position)
		if d2 <= best_dist:
			best_dist = d2
			best      = enemy

	return best
