# ability_lightning_javelin.gd
# ---------------------------------------------------------------------------
# Auto-fires on cooldown in the direction of the densest enemy cluster.
# A fast projectile that pierces every enemy in a straight line.
#
# Hard synergies
#   → ResidualCurrent : enemies killed by the bolt are flagged as lightning
#                       kills before die() is called.  ResidualCurrent places
#                       a corpse node at each death position.  Because Javelin
#                       kills along a line, a corridor of corpses seeds the
#                       path enemies continue to walk through.
#
# Soft synergy (StaticField / Gold metal)
#   Every enemy pierced spawns a StaticField at their position — a row of
#   fields along the firing axis.  Enemies that survive the bolt stand on
#   their own gold-triggerable fields.
# ---------------------------------------------------------------------------
class_name AbilityLightningJavelin
extends AbilityData

const JavelinScene := preload("res://scenes/abilities/lightning_javelin.tscn")

# How many direction samples to take when finding the densest cluster axis.
const AXIS_SAMPLES: int   = 16
# Half-width of the rectangle used to count enemies along each axis.
const AXIS_HALF_WIDTH: float = 16.0

func tick(context: Dictionary) -> void:
	super.tick(context)
	var player:      Node2D = context["player"]
	var orb_potency: float  = context.get("orb_potency", 1.0)

	if EnemyManager.living_enemies.is_empty():
		return

	var fire_dir: Vector2 = _best_axis(player.global_position, get_stat("range"))
	if fire_dir == Vector2.ZERO:
		return

	var orb_index: int     = context.get("orb_index", -1)
	var orb_spawn: Vector2 = player.global_position
	if orb_index >= 0 and orb_index < player.orb_visuals.size():
		orb_spawn = player.orb_visuals[orb_index].sprite.global_position

	var count: int = maxi(1, int(get_stat("projectile_count")))
	# Additional javelins fan out symmetrically around the main axis.
	# Spread angle grows with count so javelins don't overlap.
	var spread_deg: float = 15.0
	for i in range(count):
		var offset_deg: float = 0.0
		if count > 1:
			offset_deg = lerpf(-spread_deg * 0.5 * (count - 1),
			                    spread_deg * 0.5 * (count - 1),
			                    float(i) / float(count - 1))
		var dir: Vector2 = fire_dir.rotated(deg_to_rad(offset_deg))
		var javelin := JavelinScene.instantiate() as LightningJavelin
		player.get_parent().add_child(javelin)
		javelin.global_position = orb_spawn
		javelin.launch(dir, stats, orb_potency, main_stats, player)

	context["orb_t"]     = 1.0
	context["activated"] = true
	stats.apply_to_player(player)


## Sample AXIS_SAMPLES directions from the player; return the one whose thin
## rectangle covers the most enemies.
func _best_axis(origin: Vector2, fire_range: float) -> Vector2:
	var best_dir:   Vector2 = Vector2.ZERO
	var best_count: int     = 0

	for i in range(AXIS_SAMPLES):
		var angle: float   = (float(i) / float(AXIS_SAMPLES)) * PI  # 0..PI covers all axes
		var dir:   Vector2 = Vector2(cos(angle), sin(angle))
		var count: int     = _count_enemies_along(origin, dir, fire_range)
		if count > best_count:
			best_count = count
			best_dir   = dir

	# Need at least one enemy on the best axis to bother firing.
	if best_count == 0:
		return Vector2.ZERO
	return best_dir


func _count_enemies_along(origin: Vector2, dir: Vector2, length: float) -> int:
	var perp:  Vector2 = dir.rotated(PI / 2.0)
	var count: int     = 0
	for enemy: Enemy in EnemyManager.living_enemies:
		if not is_instance_valid(enemy):
			continue
		var to_enemy:    Vector2 = enemy.global_position - origin
		var proj_along:  float   = to_enemy.dot(dir)
		var proj_lateral: float  = abs(to_enemy.dot(perp))
		if proj_along >= 0.0 and proj_along <= length and proj_lateral <= AXIS_HALF_WIDTH:
			count += 1
	return count
