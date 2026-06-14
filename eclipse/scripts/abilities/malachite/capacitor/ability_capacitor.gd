# ability_capacitor.gd
# ---------------------------------------------------------------------------
# Passive ability.  Tracks damage absorbed by the player since last
# discharge.  When accumulated damage crosses the threshold (stored in
# stats.damage), fires a lightning explosion centered on the player and resets.
#
# There is no fixed cooldown.  The "cooldown" is the damage threshold — it
# fires faster under heavy punishment, slower when the player is healthy.
#
# Hard synergies
#   → LightningChain : on detonation, increments player.guaranteed_crits.
#                      The next Chain fired while that flag is > 0 will crit
#                      every hop.  Feedback loop: absorb a punishing wave →
#                      Capacitor pops → supercharged Chain tears through the
#                      grouped enemies that caused the punishment.
#   → Thunderclap    : emergent — both abilities charge from the same
#                      proximity condition (enemies close enough to hit the
#                      player).  No explicit coupling; the two abilities
#                      naturally discharge within moments of each other.
#
# Soft synergy (StaticField / Gold metal)
#   The explosion spawns StaticFields at every enemy position in the blast
#   radius.  Fields are seeded densely in exactly the area gold abilities will
#   be targeting immediately after the discharge burst.
# ---------------------------------------------------------------------------
class_name AbilityCapacitor
extends AbilityData

# How many guaranteed crits to grant after discharge (for Chain synergy).
const CRITS_ON_DISCHARGE: int = 5

var _damage_accum: float = 0.0
var _last_health:  int   = -1

func tick(context: Dictionary) -> void:
	super.tick(context)
	var player: CharacterBody2D = context["player"]
	var delta:  float           = context.get("delta", 0.0)

	# Initialise health tracking on first tick.
	if _last_health < 0:
		_last_health = player.health

	# Measure damage taken this frame.
	var damage_this_frame: int = _last_health - player.health
	_last_health = player.health
	if damage_this_frame > 0:
		_damage_accum += float(damage_this_frame)

	# Threshold is stored in the power stat so it benefits from orb upgrades.
	var threshold: float = get_stat("damage")
	if threshold <= 0.0:
		threshold = 50.0

	# Drive orb glow proportionally to how charged the capacitor is.
	context["orb_t"] = clampf(_damage_accum / threshold, 0.0, 1.0)

	if _damage_accum < threshold:
		return

	_damage_accum = 0.0
	_discharge(player, context)

func _discharge(player: CharacterBody2D, context: Dictionary) -> void:
	var orb_potency: float = context.get("orb_potency", 1.0)
	var radius:      float = stats.get_stat("aoe_radius", orb_potency, main_stats)
	if radius <= 0.0:
		radius = 100.0
	var power:       float = stats.get_stat("damage", orb_potency, main_stats)
	var radius_sq:   float = radius * radius

	for enemy: Enemy in EnemyManager.living_enemies.duplicate():
		if not is_instance_valid(enemy):
			continue
		if player.global_position.distance_squared_to(enemy.global_position) > radius_sq:
			continue

		var is_crit: bool  = stats.roll_crit(player)
		var damage:  float = power * (stats.crit_damage if is_crit else 1.0)
		enemy.take_damage(int(damage), stats.get_armor_pen(), is_crit, Util.DamageType.LIGHTNING)
		RelicOvercharged.add_stack(enemy)
		ParticleManager.spawn_lightning_spark(enemy.global_position)

		# Soft synergy: seed StaticFields densely at discharge point.
		StaticField.spawn(enemy.global_position, power, player.get_parent())

	# Hard synergy → LightningChain: next chain crits every hop.
	player.guaranteed_crits += CRITS_ON_DISCHARGE

	context["activated"] = true
	stats.apply_to_player(player)
