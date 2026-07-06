# ability_data.gd
class_name AbilityData
extends Resource

@export var id:            String       = ""
@export var display_name:  String       = ""
@export_multiline var description: String = ""
@export var icon:          Texture2D    = null
## Ore/metal type folder this ability's icon lives under
## (res://art/abilities/<ore_type>/<id>.png), e.g. "gold", "malachite".
@export var ore_type:      String       = ""
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
##          e.stat_deltas_common = {"damage": 4.0}; e.stat_deltas_rare = {"damage": 9.0}
##          upgrade_levels.append(e)
@export var upgrade_levels: Array[AbilityUpgradeEntry] = []

## Returns the next upgrade entry as a Dictionary for the given rarity.
## Falls back to a generic stat-boost entry if upgrade_levels is empty or exhausted.
func next_upgrade_entry(rarity: int = 0) -> Dictionary:
	_ensure_loaded()
	if level < upgrade_levels.size():
		return upgrade_levels[level].to_dict(rarity)
	# Generic fallback: scale power/damage boost by rarity
	var boost: float = 2.0 + rarity * 2.0
	return {
		"display_name": display_name + " +" + str(level + 1),
		"description":  "Increases damage by " + str(int(boost)) + ".",
		"icon":         null,
		"stat_deltas":  { "damage": boost },
		"main_stats":   [],
	}

## True when at least one more upgrade is available (up to level 8).
func can_upgrade() -> bool:
	return level < 8

# ── automatic data loading ──────────────────────────────────────────────────

## True once base stats / icon / upgrade_levels have been loaded for this
## instance. Guards against repeated work on duplicates and resource reloads.
var _data_loaded: bool = false

## Public entry point — loads base stats, upgrade_levels, and icon from data
## files if not already done. Call this once [id]/[ore_type] are set (e.g.
## from Inventory.add_ability) so the ability is fully configured before use.
## Safe to call multiple times — only runs once per instance.
func ensure_loaded() -> void:
	_ensure_loaded()

func _ensure_loaded() -> void:
	if _data_loaded:
		return
	if not _has_data_loader():
		return  # retry next call — DataLoader autoload not in tree yet
	_data_loaded = true
	DataLoader.apply_ability_data(self)
	_load_icon()

## Returns true if the DataLoader autoload is available in the scene tree.
func _has_data_loader() -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	return tree.root.has_node("DataLoader")

## Loads the ability's icon from res://art/abilities/<ore_type>/<id>.png
## if [icon] hasn't already been set manually.
func _load_icon() -> void:
	if icon != null:
		return
	if ore_type.is_empty() or id.is_empty():
		return
	var file_name: String = id.strip_edges().to_lower().replace(" ", "_")
	var path: String = "res://art/abilities/%s/%s.png" % [ore_type.strip_edges().to_lower(), file_name]
	if ResourceLoader.exists(path):
		icon = load(path)

# ── runtime ───────────────────────────────────────────────────────────────────

var _orb_potency:      float = 1.0
var _cooldown_elapsed: float = INF  # starts ready; resets to 0 on activation

## True when the ability's cooldown has fully elapsed (or no cooldown is set).
func is_ready() -> bool:
	_ensure_loaded()
	var cd: float = stats.cooldown if stats.cooldown > 0.0 else 0.0
	return _cooldown_elapsed >= cd

## Call after a successful activation to restart the cooldown.
func trigger_cooldown() -> void:
	_cooldown_elapsed = 0.0

## Advance the cooldown timer. Call once per frame from tick().
func tick_cooldown(delta: float) -> void:
	var cd: float = stats.cooldown if stats.cooldown > 0.0 else 0.0
	if cd > 0.0 and _cooldown_elapsed < cd:
		_cooldown_elapsed = minf(_cooldown_elapsed + delta, cd)

func get_stat(stat_name: String) -> float:
	_ensure_loaded()
	return stats.get_stat(stat_name, _orb_potency, main_stats)

## Called every frame by the player for every ability, regardless of type.
## Subclasses fire whenever they find a valid target — no input gating.
## Write context["activated"] = true to trigger the orb shatter.
func tick(context: Dictionary) -> void:
	_ensure_loaded()
	_orb_potency = context.get("potency", 1.0)
	tick_cooldown(context.get("delta", 0.0))

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
