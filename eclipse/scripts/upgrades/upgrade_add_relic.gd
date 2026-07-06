class_name UpgradeAddRelic
extends LevelUpUpgrade

var new_relic: RelicData = null

## Returns Array[UpgradeAddRelic] with 3 tiers.
static func build(player: CharacterBody2D, rarity: int = 0) -> Array:
	var run_inv: RunInventory = player.get_node("RunInventory")
	var p_stats: PlayerStats  = player.stats

	if p_stats.relic_max > 0:
		var total: int = 0
		for v: int in run_inv.relics.values(): total += v
		if total >= p_stats.relic_max:
			return []

	var owned_ids: Array[String] = []
	for r: RelicData in run_inv.relics:
		owned_ids.append(r.id)

	var candidates: Array[RelicData] = []
	for r: RelicData in ItemManager._relic_pool:
		if r.id not in owned_ids:
			candidates.append(r)

	if candidates.is_empty():
		return []

	candidates.shuffle()
	var picked: RelicData   = candidates[0]
	var cost_item: ItemData = RelicLevelUpUpgrade._pick_weighted_item(run_inv)
	var base_amount: int    = UpgradeCostTable.new_item_cost(rarity)

	var result: Array = []
	var tier_labels: Array = ["Free", "Enhanced", "Supercharged"]
	for t in 3:
		var u        := UpgradeAddRelic.new()
		u.new_relic   = picked
		u.rarity      = rarity
		u.tier        = t
		u.item_cost   = UpgradeCostTable.build_tiered_cost(cost_item, base_amount, t)
		u.icon        = picked.icon
		u.display_name = "New Relic\n%s" % picked.display_name
		var desc := picked.description if picked.description != "" else "A powerful relic."
		desc += "\n— %s —" % tier_labels[t]
		if u.item_cost.is_empty():
			desc += "\nCost: Free"
		else:
			for item: ItemData in u.item_cost:
				desc += "\nCost: %d %s" % [u.item_cost[item], item.display_name]
		u.description = desc
		result.append(u)

	return result

func apply(player: CharacterBody2D) -> void:
	if new_relic == null:
		return
	player.get_node("RunInventory").add_relic(new_relic, 1)
