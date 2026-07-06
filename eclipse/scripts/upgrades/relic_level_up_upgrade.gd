class_name RelicLevelUpUpgrade
extends LevelUpUpgrade

const TIER_MULTIPLIERS: Array[float] = [1.0, 1.5, 2.5]

var target_relic:  RelicData   = null
var _upgrade_entry: Dictionary = {}

## Returns Array[RelicLevelUpUpgrade] with 3 tiers.
static func build(relic: RelicData, rarity: int, run_inv: RunInventory) -> Array:
	if relic.upgrade_levels.is_empty():
		DataLoader.apply_relic_data(relic)
	var entry: Dictionary = relic.next_upgrade_entry(rarity)
	if entry.is_empty():
		return []

	# Pick a cost item weighted by what the player is actually carrying.
	var cost_item: ItemData = _pick_weighted_item(run_inv)
	var base_amount: int = UpgradeCostTable.upgrade_cost(rarity)

	var result: Array = []
	for t in 3:
		var tier_mult: float = TIER_MULTIPLIERS[t]
		var raw_deltas: Dictionary = entry.get("stat_deltas", {})
		var scaled_deltas: Dictionary = {}
		for stat: String in raw_deltas:
			scaled_deltas[stat] = raw_deltas[stat] * tier_mult

		var u := RelicLevelUpUpgrade.new()
		u.target_relic   = relic
		u._upgrade_entry = entry.duplicate()
		u._upgrade_entry["stat_deltas"] = scaled_deltas
		u.rarity     = rarity
		u.tier       = t
		u.item_cost  = UpgradeCostTable.build_tiered_cost(cost_item, base_amount, t)
		u.icon       = entry.get("icon", relic.icon)
		u.display_name = "%s\n%s" % [relic.display_name, entry.get("display_name", "Upgrade")]
		u.description  = _build_desc(scaled_deltas, t, u.item_cost)
		result.append(u)

	return result

func apply(_player: CharacterBody2D) -> void:
	if target_relic == null:
		return
	var stat_deltas: Dictionary = _upgrade_entry.get("stat_deltas", {})
	for stat_name: String in stat_deltas:
		var current = target_relic.get(stat_name)
		if current == null:
			push_warning("RelicLevelUpUpgrade: stat '%s' not found on %s" % [stat_name, target_relic.display_name])
			continue
		var base: float = current if current != -1 else 0.0
		target_relic.set(stat_name, base + float(stat_deltas[stat_name]))
	target_relic.level += 1

## Picks an ItemData weighted by quantity from what the player is carrying.
static func _pick_weighted_item(run_inv: RunInventory) -> ItemData:
	var ids: Array = run_inv.get_all_item_ids()
	var total: int = 0
	for id in ids:
		total += run_inv.get_quantity_by_id(id)
	if total <= 0:
		return null
	var roll: int = randi() % total
	var cumulative: int = 0
	for id in ids:
		cumulative += run_inv.get_quantity_by_id(id)
		if roll < cumulative:
			return run_inv.get_item_data(id)
	return null

static func _build_desc(deltas: Dictionary, tier: int, cost: Dictionary) -> String:
	var lines: Array[String] = []
	var stat_labels: Dictionary = DataLoader.STAT_LABELS
	for stat: String in deltas:
		var val: float = deltas[stat]
		var label: String = stat_labels.get(stat, stat.replace("_", " ").capitalize())
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
