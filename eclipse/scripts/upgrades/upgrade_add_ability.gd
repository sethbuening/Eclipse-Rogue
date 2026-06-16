# upgrade_add_ability.gd
# ---------------------------------------------------------------------------
# A LevelUpUpgrade that adds a new ability directly to the player's inventory.
#
# The ability's metal type is chosen by weighted probability using the overall
# metal composition from the player's inventory metals.
# A random ability from that metal's pool is then selected.
#
# display_name format:
#   "New Ability"  (line 1)
#   "<Ability Name>"  (line 2)
# ---------------------------------------------------------------------------
class_name UpgradeAddAbility
extends LevelUpUpgrade

var new_ability: AbilityData = null

static func build(inventory_metals: Dictionary, all_abilities: Array[AbilityData], rarity: int = 0) -> UpgradeAddAbility:
	var existing_ids: Array[String] = []
	# Collect ability IDs already in the inventory so we don't duplicate.
	# (all_abilities is passed in as the current inventory abilities array.)
	for a: AbilityData in all_abilities:
		existing_ids.append(_ability_id(a))

	var candidates: Array[AbilityData] = []

	if not inventory_metals.is_empty():
		var chosen_metal: MetalData = _pick_weighted_metal(inventory_metals)
		if chosen_metal != null and not chosen_metal.ability_pool.is_empty():
			for a: AbilityData in chosen_metal.ability_pool:
				if _ability_id(a) not in existing_ids:
					candidates.append(a)
			if candidates.is_empty():
				candidates = chosen_metal.ability_pool.duplicate()

	# Final fallback: offer any ability not already owned.
	if candidates.is_empty():
		candidates = all_abilities.duplicate()

	if candidates.is_empty():
		return null

	candidates.shuffle()
	var picked: AbilityData = candidates[0].duplicate(true)

	var u := UpgradeAddAbility.new()
	u.new_ability = picked
	u.rarity      = rarity

	var free_levels: int = rarity  # Common=0 … Legendary=4

	u.display_name = "New Ability\n%s" % picked.display_name

	var desc: String = "Adds %s to your abilities." % picked.display_name
	if free_levels > 0:
		desc += "\nStarts at Level %d." % free_levels
	u.description = desc
	u.icon = picked.icon if "icon" in picked else null

	# ── ore cost ──────────────────────────────────────────────────────────────
	var cost_metal: MetalData = ItemManager.get_metal_by_id(picked.ore_type)
	if cost_metal == null:
		cost_metal = _pick_weighted_metal(inventory_metals)
	u.metal_cost = UpgradeCostTable.build_cost(cost_metal, UpgradeCostTable.new_item_cost(rarity))

	return u

func apply(player: CharacterBody2D) -> void:
	if new_ability == null:
		return
	var ability: AbilityData = new_ability.duplicate(true)
	# Apply free head-start levels (rarity: Common=0 … Legendary=4)
	var free_levels: int = rarity
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
					var base: float = current if current != -1 else 0.0
					ability.stats.set(stat, base + float(deltas[stat]))
			ability.level += 1
	player.get_node("Inventory").add_ability(ability)

# ── private helpers ────────────────────────────────────────────────────────────

static func _pick_weighted_metal(composition: Dictionary) -> MetalData:
	var total: int = 0
	for m: MetalData in composition:
		total += composition[m]
	if total <= 0:
		return null
	var roll: int = randi() % total
	var cumulative: int = 0
	for m: MetalData in composition:
		cumulative += composition[m]
		if roll < cumulative:
			return m
	return null

static func _ability_id(a: AbilityData) -> String:
	return a.get_script().get_path() if a.get_script() else a.display_name
