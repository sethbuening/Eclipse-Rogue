# ability_arc_overload.gd
# ---------------------------------------------------------------------------
# Fires a sustained beam of electricity at the enemy carrying the most
# charged stacks.  Stacks are written to enemies by the "Overcharged" relic
# — without the relic this ability targets the nearest enemy and deals base
# damage only.  With the relic, every other lightning ability hitting an enemy
# increments that enemy's stack counter, and Arc Overload reads and partially
# spends those stacks on each hit, scaling its damage accordingly.
#
# The beam fires automatically on cooldown like every other ability; the
# player's job is positioning to keep a priority target inside range.
#
# Hard synergies
#   ← All other lightning abilities (via relic) : each hit from Chain,
#     Javelin, Thunderclap, Ball Lightning, Capacitor, or a Residual corpse
#     increments the target's "arc_stacks" meta.  The more sustained
#     lightning pressure has been applied to a target, the harder this beam
#     hits when it fires.
#
# Soft synergy (StaticField / Gold metal)
#   Each tick of beam damage spawns a StaticField at the target's position.
#   Because the beam fires repeatedly at the same enemy, it can densely seed
#   that single position with fields — concentrated rather than spread.
# ---------------------------------------------------------------------------
class_name AbilityArcOverload
extends AbilityData

const ArcOverloadScene := preload("res://scenes/abilities/arc_overload.tscn")

# Stack constants — also referenced by the relic.
# Kept here as the canonical source so the relic can read them.
const MAX_STACKS:       int   = 10
const STACK_DAMAGE_MULT: float = 0.25  # bonus damage per stack as fraction of base power
const STACKS_SPENT_PER_HIT: int = 1   # stacks consumed each time beam deals damage

func tick(context: Dictionary) -> void:
	super.tick(context)
	var player:      Node2D = context["player"]
	var orb_potency: float  = context.get("orb_potency", 1.0)

	if EnemyManager.living_enemies.is_empty():
		return

	var orb_index: int     = context.get("orb_index", -1)
	var orb_spawn: Vector2 = player.global_position
	if orb_index >= 0 and orb_index < player.orb_visuals.size():
		orb_spawn = player.orb_visuals[orb_index].sprite.global_position

	var beam_count: int = maxi(1, int(get_stat("chain_length")))
	var already_targeted: Array[Enemy] = []
	for _b in range(beam_count):
		var target: Enemy = _best_target(player.global_position, get_stat("range"), already_targeted)
		if target == null:
			break
		already_targeted.append(target)

		var beam := ArcOverloadScene.instantiate() as ArcOverload
		player.get_parent().add_child(beam)
		beam.setup(orb_spawn, target, stats, orb_potency, main_stats, player)

	context["orb_t"]     = 1.0
	context["activated"] = true
	stats.apply_to_player(player)


## Returns the enemy with the most arc_stacks within range.
## Falls back to nearest enemy if no enemy has any stacks (relic not active).
## Enemies in [exclude] are skipped so multiple beams target different enemies.
func _best_target(origin: Vector2, fire_range: float, exclude: Array[Enemy] = []) -> Enemy:
	var range_sq:    float = fire_range * fire_range if fire_range > 0.0 else INF
	var best:        Enemy = null
	var best_stacks: int   = -1
	var best_dist:   float = INF

	for enemy: Enemy in EnemyManager.living_enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy in exclude:
			continue
		var d2: float = origin.distance_squared_to(enemy.global_position)
		if d2 > range_sq:
			continue

		var stacks: int = enemy.get_meta("arc_stacks", 0)
		# Prefer highest stacks; use distance as tiebreaker.
		if stacks > best_stacks or (stacks == best_stacks and d2 < best_dist):
			best        = enemy
			best_stacks = stacks
			best_dist   = d2

	return best
