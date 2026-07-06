class_name AbilityLevelUpUpgrade
extends LevelUpUpgrade

const RARITY_MULTIPLIERS: Array[float] = [1.0, 1.5, 2.0, 3.0, 5.0]
## Extra stat multiplier per spending tier on top of rarity scaling.
const TIER_MULTIPLIERS: Array[float] = [1.0, 1.5, 2.5]

var target_ability: AbilityData = null
var _upgrade_entry: Dictionary  = {}

## Returns Array[AbilityLevelUpUpgrade] with 3 tiers (free / 1× cost / 2× cost).
## Caller should present all three as a grouped choice.
static func build(ability: AbilityData, rarity: int) -> Array:
	if ability.upgrade_levels.is_empty():
		DataLoader.apply_ability_data(ability)
	var entry: Dictionary = ability.next_upgrade_entry(rarity)
	if entry.is_empty():
		return []

	var rarity_mult: float = RARITY_MULTIPLIERS[clampi(rarity, 0, RARITY_MULTIPLIERS.size() - 1)]
	var raw_deltas: Dictionary = entry.get("stat_deltas", {})

	# Resolve cost item from ability's ore_type id.
	var cost_item: ItemData = ItemManager.get_item_by_id(ability.ore_type) if ability.get("ore_type") else null
	var base_amount: int = ability.stats.cost if ability.stats.cost >= 0 else UpgradeCostTable.upgrade_cost(rarity)
	base_amount = maxi(1, roundi(base_amount * rarity_mult))

	var result: Array = []
	for t in 3:
		var tier_mult: float = TIER_MULTIPLIERS[t]
		var scaled_deltas: Dictionary = {}
		for stat: String in raw_deltas:
			scaled_deltas[stat] = raw_deltas[stat] * rarity_mult * tier_mult

		var u := AbilityLevelUpUpgrade.new()
		u.target_ability = ability
		u._upgrade_entry = entry.duplicate()
		u._upgrade_entry["stat_deltas"] = scaled_deltas
		u.rarity     = rarity
		u.tier       = t
		u.item_cost  = UpgradeCostTable.build_tiered_cost(cost_item, base_amount, t)
		u.icon       = ability.icon if "icon" in ability else null
		u.display_name = "%s\n%s" % [ability.display_name, entry.get("display_name", ability.display_name)]
		u.description  = _build_desc(scaled_deltas, t, u.item_cost)
		result.append(u)

	return result

func apply(_player: CharacterBody2D) -> void:
	if target_ability == null:
		return
	var stat_deltas: Dictionary = _upgrade_entry.get("stat_deltas", {})
	for stat_name: String in stat_deltas:
		var current = target_ability.stats.get(stat_name)
		if current == null:
			push_warning("AbilityLevelUpUpgrade: stat '%s' not found on %s" % [stat_name, target_ability.display_name])
			continue
		var base: float = current if current != -1 else 0.0
		target_ability.stats.set(stat_name, base + float(stat_deltas[stat_name]))
	var new_main: Array = _upgrade_entry.get("main_stats", [])
	for s: String in new_main:
		if s not in target_ability.main_stats:
			target_ability.main_stats.append(s)
	target_ability.level += 1

static func _build_desc(deltas: Dictionary, tier: int, cost: Dictionary) -> String:
	var lines: Array[String] = []
	for stat: String in deltas:
		var val: float = deltas[stat]
		var label: String = DataLoader.STAT_LABELS.get(stat, stat.replace("_", " ").capitalize())
		var sign: String = "+" if val >= 0 else ""
		var vs: String = ("%s%d" % [sign, int(val)]) if float(int(val)) == val \
			else ("%s%.2f" % [sign, val]).rstrip("0").rstrip(".")
		lines.append("%s: %s" % [label, vs])
	var tier_labels: Array = ["Free", "Enhanced", "Supercharged"]
	lines.append("— %s —" % tier_labels[tier])
	if cost.is_empty():
		lines.append("Cost: Free")
	else:
		for item: ItemData in cost:
			lines.append("Cost: %d %s" % [cost[item], item.display_name])
	return "\n".join(lines)
