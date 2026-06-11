# relic_overcharged.gd
# "Overcharged"
# ---------------------------------------------------------------------------
# Boss-tier relic.  Every time a lightning ability hits an enemy it gains one
# arc_stack (up to MAX_STACKS).  Stacks decay slowly when that enemy is not
# being hit.  Arc Overload reads these stacks to scale its beam damage and
# spends them gradually over its duration.
#
# Without this relic, Arc Overload still functions — it just deals base damage
# with no stack bonus, targeting the nearest enemy instead of the most-stacked
# one.  The relic unlocks the intended high-skill loop without gating the
# ability behind it.
#
# Hooks used:
#   on_equip  : connect to EnemyManager.enemy_died to clean up meta on death.
#   tick      : decay stacks on all living enemies each frame.
#
# Stack writing is done in a static helper so any lightning ability can call
# it with one line:  RelicOvercharged.add_stack(enemy)
# The helper silently does nothing if the relic is not in the player's
# inventory, so lightning abilities never need to check for it themselves.
# ---------------------------------------------------------------------------
class_name RelicOvercharged
extends RelicData

# How many stacks each lightning hit adds.
const STACKS_PER_HIT: int   = 1
# Maximum stacks an enemy can hold.
const MAX_STACKS:     int    = AbilityArcOverload.MAX_STACKS
# Seconds before one stack is removed if the enemy hasn't been hit.
const DECAY_INTERVAL: float  = 1.2
# How long after the last lightning hit before decay starts.
const DECAY_DELAY:    float  = 2.0

# Static reference so add_stack() can check for the relic without a direct
# reference to the player.  Set on equip, cleared on removal.
static var _active_relic: RelicOvercharged = null
static var _player_ref:   CharacterBody2D  = null

# Per-enemy timers stored outside the enemy node to keep enemy.gd clean.
# Key: Enemy instance ID.  Value: { "decay_timer": float, "delay_timer": float }
var _timers: Dictionary = {}

# ── lifecycle ─────────────────────────────────────────────────────────────────

func on_equip(player: CharacterBody2D) -> void:
	RelicOvercharged._active_relic = self
	RelicOvercharged._player_ref   = player
	EnemyManager.enemy_died.connect(_on_enemy_died)

# Called if the relic is ever removed (future-proofing).
func on_remove(player: CharacterBody2D) -> void:
	RelicOvercharged._active_relic = null
	RelicOvercharged._player_ref   = null
	if EnemyManager.enemy_died.is_connected(_on_enemy_died):
		EnemyManager.enemy_died.disconnect(_on_enemy_died)
	# Clear all stacks from living enemies.
	for enemy: Enemy in EnemyManager.living_enemies:
		if is_instance_valid(enemy):
			enemy.remove_meta("arc_stacks")
	_timers.clear()

func tick(delta: float, _player: CharacterBody2D) -> void:
	# Tick decay timers for every living enemy that has stacks.
	var dead_keys: Array = []
	for key in _timers.keys():
		var enemy: Enemy = instance_from_id(key)
		if not is_instance_valid(enemy):
			dead_keys.append(key)
			continue

		var stacks: int = enemy.get_meta("arc_stacks", 0)
		if stacks <= 0:
			dead_keys.append(key)
			continue

		var t: Dictionary = _timers[key]

		# Count down the grace period before decay starts.
		if t["delay_timer"] > 0.0:
			t["delay_timer"] -= delta
			continue

		# Decay one stack per DECAY_INTERVAL.
		t["decay_timer"] -= delta
		if t["decay_timer"] <= 0.0:
			t["decay_timer"] = DECAY_INTERVAL
			var new_stacks: int = maxi(0, stacks - 1)
			enemy.set_meta("arc_stacks", new_stacks)
			if new_stacks == 0:
				dead_keys.append(key)

	for key in dead_keys:
		_timers.erase(key)

# ── static API ────────────────────────────────────────────────────────────────

## Call this from any lightning ability after dealing damage.
## Does nothing if Overcharged is not equipped.
static func add_stack(enemy: Enemy) -> void:
	if _active_relic == null or not is_instance_valid(enemy):
		return
	var current: int = enemy.get_meta("arc_stacks", 0)
	if current >= MAX_STACKS:
		return
	enemy.set_meta("arc_stacks", current + STACKS_PER_HIT)

	# Reset decay timers — the enemy was just hit, delay restarts.
	var key: int = enemy.get_instance_id()
	_active_relic._timers[key] = {
		"decay_timer": DECAY_INTERVAL,
		"delay_timer": DECAY_DELAY,
	}

# ── signal handlers ───────────────────────────────────────────────────────────

func _on_enemy_died(enemy: Enemy) -> void:
	var key: int = enemy.get_instance_id()
	_timers.erase(key)
	# Meta is cleaned up automatically when the enemy node is freed.
