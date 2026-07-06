class_name UpgradeAddAbility
extends LevelUpUpgrade

const TIER_MULTIPLIERS: Array[float] = [1.0, 1.5, 2.5]

var new_ability: AbilityData = null

## Returns Array[UpgradeAddAbility] with 3 tiers (free levels: 0 / rarity / rarity*2).
static func build(run_inv: RunInventory, all_abilities: Array[AbilityData], rarity: int = 0) -> Array:
	var existing_ids: Array[String] = []
	for a: AbilityData in all_abilities:
		existing_ids.append(_ability_id(a))

	# Pick from any ability not already owned.
	var candidates: Array[AbilityData] = []
	for a: AbilityData in DataLoader.get_all_abilities():
		if _ability_id(a) not in existing_ids:
			candidates.append(a)

	if candidates.is_empty():
		return []

	candidates.shuffle()
	var picked: AbilityData = candidates[0]

	var cost_item: ItemData = RelicLevelUpUpgrade._pick_weighted_item(run_inv)
	var base_amount: int    = UpgradeCostTable.new_item_cost(rarity)

	var result: Array = []
	for t in 3:
		var free_levels: int = rarity * t   # 0 / rarity / rarity*2

		var u         := UpgradeAddAbility.new()
		u.new_ability  = picked
		u.rarity       = rarity
		u.tier         = t
		u.item_cost    = UpgradeCostTable.build_tiered_cost(cost_item, base_amount, t)
		u.icon         = picked.icon if "icon" in picked else null
		u.display_name = "New Ability\n%s" % picked.display_name

		var desc := "Adds %s to your abilities." % picked.display_name
		if free_levels > 0:
			desc += "\nStarts at Level %d." % free_levels
		var tier_labels: Array = ["Free", "Enhanced", "Supercharged"]
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
	if new_ability == null:
		return
	var ability: AbilityData = new_ability.duplicate(true)
	var free_levels: int = rarity * tier
	if free_levels > 0:
		if ability.upgrade_levels.is_empty():
			DataLoader.apply_ability_data(ability)
		for _i in range(free_levels):
			if not ability.can_upgrade():
				break
			var entry: Dictionary = ability.next_upgrade_entry(0)
			if entry.is_empty():
				break
			var deltas: Dictionary = entry.get("stat_deltas", {})
			for stat: String in deltas:
				var current = ability.stats.get(stat)
				if current != null:
					ability.stats.set(stat, (current if current != -1 else 0.0) + float(deltas[stat]))
			ability.level += 1
	player.get_node("RunInventory").add_ability(ability)

static func _ability_id(a: AbilityData) -> String:
	return a.get_script().get_path() if a.get_script() else a.display_name
