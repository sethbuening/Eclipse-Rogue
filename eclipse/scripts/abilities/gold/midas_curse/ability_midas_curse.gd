# ability_midas_curse.gd
# ---------------------------------------------------------------------------
# Periodically marks the highest-health enemy. Marked enemies take increased
# crit chance and crit damage from Gold abilities.
#
# Without King's Treasury
#   Fully functional. Mark placement and migration work normally. The only
#   thing that doesn't fire is the Fortune-burst-on-non-crit-death, since
#   there's no Fortune system to pay into.
#
# Mark migration
#   When the marked enemy dies, the mark leaps instantly to the next
#   highest-health enemy. The mark is never wasted.
#
# Cursed death bonus (requires King's Treasury)
#   If the marked enemy is killed without a crit, Midas Curse generates a
#   Fortune burst — a cross-metal incentive for Lightning to finish marked
#   enemies you couldn't crit.
#
# Synergies
#   → Gilded Shot   : marked enemies grant bonus Fortune on any hit
#   → Rain of Crowns: Crowns prioritize and auto-crit the marked enemy
#   ← Jackpot Wheel : BONUS_MARK creates a second temporary mark
# ---------------------------------------------------------------------------
class_name AbilityMidasCurse
extends AbilityData

var _cooldown_accum: float = 0.0
var _connected:      bool  = false

func tick(context: Dictionary) -> void:
	super.tick(context)
	var player: CharacterBody2D = context["player"]
	var delta:  float           = context.get("delta", 0.0)
	var gold:   GoldManager     = context.get("gold", null)

	# Connect to enemy death signal once.
	if not _connected:
		_connected = true
		if not EnemyManager.enemy_died.is_connected(_on_enemy_died.bind(gold)):
			EnemyManager.enemy_died.connect(_on_enemy_died.bind(gold))

	var has_mark: bool = gold != null and is_instance_valid(gold.marked_enemy)

	if has_mark:
		# Refresh mark meta on the enemy each tick.
		var enemy: Enemy = gold.marked_enemy
		var crit_chance_bonus: float = get_stat("curse_crit_chance_bonus")
		var crit_dmg_bonus:    float = get_stat("curse_crit_damage_bonus")
		enemy.set_meta("midas_marked", true)
		enemy.set_meta("midas_crit_chance_bonus", crit_chance_bonus if crit_chance_bonus > 0.0 else 0.25)
		enemy.set_meta("midas_crit_damage_bonus", crit_dmg_bonus    if crit_dmg_bonus    > 0.0 else 0.5)
	else:
		_cooldown_accum += delta

	var cooldown: float = get_stat("curse_mark_interval")
	if cooldown <= 0.0:
		cooldown = 5.0

	if _cooldown_accum < cooldown:
		context["orb_t"] = _cooldown_accum / cooldown
		return

	_cooldown_accum = 0.0
	_place_new_mark(gold)

	# Jackpot Wheel: BONUS_MARK gives a second temporary mark.
	if gold != null and gold.wheel_ready and gold.wheel_outcome == GoldManager.WheelOutcome.BONUS_MARK:
		gold.consume_wheel_outcome()
		gold.bonus_mark_active  = true
		gold._bonus_mark_timer  = GoldManager.BONUS_MARK_DURATION

	context["orb_t"]     = 1.0
	context["activated"] = true
	stats.apply_to_player(player)

func _place_new_mark(gold: GoldManager) -> void:
	var best:        Enemy = null
	var best_health: int   = -1
	for enemy: Enemy in EnemyManager.living_enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.health > best_health:
			best_health = enemy.health
			best        = enemy
	if best == null:
		return

	# Clear old mark meta.
	if gold != null and is_instance_valid(gold.marked_enemy):
		_clear_mark_meta(gold.marked_enemy)

	if gold != null:
		gold.place_mark(best)
	ParticleManager.spawn_gold_bomb_trail(best.global_position)

func _on_enemy_died(enemy: Enemy, gold: GoldManager) -> void:
	if gold == null or enemy != gold.marked_enemy:
		return

	# Cursed death bonus: Fortune burst when mark dies without a crit.
	if gold != null and not enemy.has_meta("killed_by_crit"):
		var player: CharacterBody2D = EnemyManager.player
		if player != null:
			var power: float = stats.get_stat("power", _orb_potency, [])
			gold.add_fortune(power * 0.5, player)

	_clear_mark_meta(enemy)
	_place_new_mark(gold)

func _clear_mark_meta(enemy: Enemy) -> void:
	if not is_instance_valid(enemy):
		return
	for key in ["midas_marked", "midas_crit_chance_bonus", "midas_crit_damage_bonus"]:
		if enemy.has_meta(key):
			enemy.remove_meta(key)
