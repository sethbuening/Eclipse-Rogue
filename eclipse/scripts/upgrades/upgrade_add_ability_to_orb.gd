# upgrade_add_ability_to_orb.gd
# ---------------------------------------------------------------------------
# A LevelUpUpgrade that adds a new ability to an orb that has an empty slot.
#
# The ability's metal type is chosen by weighted probability using the exact
# percentage breakdown of metals forged into the orb (orb.metal_composition).
# A random ability from that metal's pool is then selected.
#
# display_name format:
#   "New Ability: <Ability Name> → <Orb Name> (Slot <N>)"
# where N is the slot the new ability will occupy (abilities.size() + 1).
# ---------------------------------------------------------------------------
class_name UpgradeAddAbilityToOrb
extends LevelUpUpgrade

var target_orb:  Orb         = null
var new_ability: AbilityData = null

static func build(orb: Orb, fallback_metals: Dictionary = {}, all_abilities: Array[AbilityData] = [], rarity: int = 0) -> UpgradeAddAbilityToOrb:
	if orb == null or not orb.has_empty_ability_slot():
		return null

	# Use orb's own composition, or fall back to the provided metal pool.
	var composition: Dictionary = orb.metal_composition
	if composition.is_empty():
		composition = fallback_metals

	var existing_ids: Array[String] = []
	for a: AbilityData in orb.abilities:
		existing_ids.append(_ability_id(a))

	var candidates: Array[AbilityData] = []

	if not composition.is_empty():
		var chosen_metal: MetalData = _pick_weighted_metal(composition)
		if chosen_metal != null and not chosen_metal.ability_pool.is_empty():
			for a: AbilityData in chosen_metal.ability_pool:
				if _ability_id(a) not in existing_ids:
					candidates.append(a)
			if candidates.is_empty():
				candidates = chosen_metal.ability_pool.duplicate()

	# Final fallback: use abilities already present on other orbs
	if candidates.is_empty():
		for a: AbilityData in all_abilities:
			if _ability_id(a) not in existing_ids:
				candidates.append(a)
		if candidates.is_empty():
			candidates = all_abilities.duplicate()

	if candidates.is_empty():
		return null

	candidates.shuffle()
	var picked: AbilityData = candidates[0].duplicate(true)

	var new_slot: int = orb.abilities.size() + 1  # 1-based slot it will land in

	var u := UpgradeAddAbilityToOrb.new()
	u.target_orb  = orb
	u.new_ability = picked
	u.rarity      = rarity

	var free_levels: int = rarity  # Common=0, Uncommon=1, Rare=2, Epic=3, Legendary=4

	# Display name: two lines — "<Orb> (Slot N)" on line 1, "Add: <Ability>" on line 2.
	u.display_name = "%s (Slot %d)\nAdd: %s" % [
		orb.display_name,
		new_slot,
		picked.display_name,
	]

	var desc: String = "Adds %s to slot %d of %s.\n(%d / %d slots filled)" % [
		picked.display_name,
		new_slot,
		orb.display_name,
		orb.abilities.size() + 1,
		orb.ability_max
	]
	if free_levels > 0:
		desc += "\nStarts at Level %d." % free_levels
	u.description = desc
	u.icon = picked.icon if "icon" in picked else null

	return u

func apply(_player: CharacterBody2D) -> void:
	if target_orb == null or new_ability == null:
		return
	if not target_orb.has_empty_ability_slot():
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
	target_orb.abilities.append(ability)
	target_orb.cooldown = 0.0
	target_orb._compute_cooldown()

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
