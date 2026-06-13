# ability_data.gd
class_name AbilityData
extends Resource

@export var id:            String       = ""
@export var display_name:  String       = ""
@export_multiline var description: String = ""
@export var targeting_type: Util.TargetingType = Util.TargetingType.ENEMY_TILE
@export var stats:         AbilityStats = AbilityStats.new()

## Stats listed here are multiplied by orb_potency when accessed via get_stat().
@export var main_stats: Array[String] = []

# ── level-up upgrades ─────────────────────────────────────────────────────────
## Current upgrade level of this ability. Starts at 0 (no upgrades taken yet).
## Incremented by AbilityLevelUpUpgrade.apply().
var level: int = 0

## Ordered list of upgrade entries for this ability.
##
## Each element is an AbilityUpgradeEntry resource. Add entries here to make
## the ability appear as a level-up option — one entry per upgrade level.
## Eight entries → eight possible upgrades. An empty array means the ability
## never appears as a level-up option.
##
## Editor:  Inspector → upgrade_levels → Add Element → AbilityUpgradeEntry
##          → fill in display_name, description, stat_deltas_* per rarity.
## Code:    var e := AbilityUpgradeEntry.new()
##          e.stat_deltas_common = {"power": 4.0}; e.stat_deltas_rare = {"power": 9.0}
##          upgrade_levels.append(e)
@export var upgrade_levels: Array[AbilityUpgradeEntry] = []

## Returns the next upgrade entry as a Dictionary for the given rarity.
## Falls back to a generic stat-boost entry if upgrade_levels is empty or exhausted.
func next_upgrade_entry(rarity: int = 0) -> Dictionary:
	if level < upgrade_levels.size():
		return upgrade_levels[level].to_dict(rarity)
	# Generic fallback: scale power/damage boost by rarity
	var boost: float = 2.0 + rarity * 2.0
	return {
		"display_name": display_name + " +" + str(level + 1),
		"description":  "Increases power by " + str(int(boost)) + ".",
		"icon":         null,
		"stat_deltas":  { "power": boost },
		"main_stats":   [],
	}

## True when at least one more upgrade is available (up to level 8).
func can_upgrade() -> bool:
	return level < 8

# ── runtime ───────────────────────────────────────────────────────────────────

var _orb_potency: float = 1.0

func get_stat(stat_name: String) -> float:
	return stats.get_stat(stat_name, _orb_potency, main_stats)

## Called every frame by the player for every ability, regardless of type.
## Subclasses fire whenever they find a valid target — no input gating.
## Write context["activated"] = true to trigger the orb shatter.
func tick(context: Dictionary) -> void:
	_orb_potency = context.get("potency", 1.0)

## Applies all stat-driven on-hit effects (knockback, stun, slow, DoT)
## to [target] on behalf of [player]. Call this from any ability after damage.
## [hit_origin] is the world position the hit came from for knockback direction;
## leave as default to use the player's position.
func apply_hit_effects(
		target:     Enemy,
		player:     CharacterBody2D,
		is_crit:    bool    = false,
		hit_origin: Vector2 = Vector2.INF
) -> void:
	var origin: Vector2 = player.global_position if hit_origin == Vector2.INF else hit_origin
	if get_stat("knockback") > 0.0:
		var dir: Vector2 = (target.global_position - origin).normalized()
		target.apply_knockback(dir * get_stat("knockback"))
	if get_stat("stun_duration") > 0.0:
		target.apply_stun(get_stat("stun_duration"))
	if get_stat("slow_amount") > 0.0 and get_stat("slow_duration") > 0.0:
		target.apply_slow(get_stat("slow_amount"), get_stat("slow_duration"))
	if get_stat("dot_damage") > 0.0 and get_stat("dot_duration") > 0.0:
		target.apply_dot(get_stat("dot_damage"), get_stat("dot_duration"))
