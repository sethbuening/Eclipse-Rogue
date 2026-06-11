# ability_thunderclap.gd
# ---------------------------------------------------------------------------
# Does NOT run on a standard fixed cooldown.  The cooldown only ticks down
# while at least one enemy is within MELEE_THRESHOLD of the player.  When the
# timer fills, it fires an instant full-circle shockwave: heavy damage,
# knockback, and a brief stun on everything in range.
#
# Hard synergies
#   → ResidualCurrent : any enemy killed by the shockwave is flagged as a
#                       lightning kill before die() is called.  ResidualCurrent
#                       listens on EnemyManager.enemy_died and places a corpse
#                       node at each flagged death position.  Because Thunderclap
#                       kills in a ring, a ring of corpses can appear at once.
#   ← Capacitor       : Capacitor fires when damage absorbed crosses a
#                       threshold, which only happens when enemies are close
#                       enough to hit the player — the same condition that
#                       charges Thunderclap.  No coupling; timing emerges from
#                       shared proximity triggers.
#
# Soft synergy (StaticField / Gold metal)
#   Every enemy hit (not just killed) spawns a StaticField at their position,
#   producing a ring of fields around the player after each clap.
# ---------------------------------------------------------------------------
class_name AbilityThunderclap
extends AbilityData

# How close an enemy must be for the cooldown to tick.
const MELEE_THRESHOLD: float = 64.0

var _cooldown_accum: float = 0.0

func tick(context: Dictionary) -> void:
	super.tick(context)
	var player: Node2D = context["player"]
	var delta:  float  = context.get("delta", 0.0)

	# Cooldown only advances when enemies are within melee range.
	var enemies_close: Array[Node2D] = Targeting.enemies_in_radius(
		player.global_position, MELEE_THRESHOLD
	)
	if enemies_close.size() > 0:
		_cooldown_accum += delta

	var cooldown: float = get_stat("cooldown")
	if cooldown <= 0.0:
		cooldown = 4.0
	if _cooldown_accum < cooldown:
		return

	_cooldown_accum = 0.0
	_fire(player, context)

func _fire(player: Node2D, context: Dictionary) -> void:
	var orb_potency: float = context.get("orb_potency", 1.0)
	var radius:      float = get_stat("aoe_radius")
	if radius <= 0.0:
		radius = 80.0
	var power:       float = stats.get_stat("power",        orb_potency, main_stats)
	var stun_dur:    float = stats.get_stat("stun_duration", orb_potency, main_stats)
	var knockback:   float = stats.get_stat("knockback",    orb_potency, main_stats)
	var radius_sq:   float = radius * radius

	for enemy: Enemy in EnemyManager.living_enemies.duplicate():
		if not is_instance_valid(enemy):
			continue
		var diff: Vector2 = enemy.global_position - player.global_position
		if diff.length_squared() > radius_sq:
			continue

		var is_crit: bool  = stats.roll_crit(player)
		var damage:  float = power * (stats.crit_damage if is_crit else 1.0)

		# Flag as lightning kill so ResidualCurrent can place a corpse node.
		enemy.set_meta("lightning_kill", true)

		enemy.take_damage(int(damage), stats.get_armor_pen(), is_crit, Util.DamageType.LIGHTNING)
		RelicOvercharged.add_stack(enemy)

		if is_instance_valid(enemy):
			if stun_dur > 0.0:
				enemy.apply_stun(stun_dur)
			if knockback > 0.0:
				var dir: Vector2 = diff.normalized() if diff.length_squared() > 0.01 else Vector2.RIGHT
				enemy.apply_knockback(dir * knockback)

		ParticleManager.spawn_lightning_spark(enemy.global_position)

		# Soft synergy: StaticField ring around player.
		StaticField.spawn(enemy.global_position, power, player.get_parent())

	context["orb_t"]     = 1.0
	context["activated"] = true
	stats.apply_to_player(player)
