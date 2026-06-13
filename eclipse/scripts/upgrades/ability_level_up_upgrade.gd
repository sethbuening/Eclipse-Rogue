# ability_level_up_upgrade.gd
# ---------------------------------------------------------------------------
# A LevelUpUpgrade that upgrades one specific ability on one specific orb.
#
# Upgrades are strictly ordered: the upgrade offered is always for the ability's
# CURRENT level (ability.level), which advances it to level+1.  There is only
# ever one possible upgrade per ability per level-up — the next entry in
# upgrade_levels[ability.level].
#
# display_name format:
#   "<Orb Name> · <Ability Name> (Slot <N>) → Level <M>"
# This makes it unambiguous even when two orbs share the same ability, or one
# orb has the same ability twice in different slots.
# ---------------------------------------------------------------------------
class_name AbilityLevelUpUpgrade
extends LevelUpUpgrade

# Multipliers applied to all stat deltas based on rolled rarity.
# Index matches Util.Rarity: 0=Common, 1=Uncommon, 2=Rare, 3=Epic, 4=Legendary.
const RARITY_MULTIPLIERS: Array[float] = [1.0, 1.5, 2.0, 3.0, 5.0]

var target_orb:      Orb         = null
var target_ability:  AbilityData = null
var ability_slot:    int         = -1   # 1-based slot index within the orb

# The upgrade entry dict pulled from target_ability.upgrade_levels[level].
var _upgrade_entry: Dictionary  = {}

static func build(
	orb:          Orb,
	ability:      AbilityData,
	ability_index: int,   # 0-based index of ability in orb.abilities
	rarity:       int
) -> AbilityLevelUpUpgrade:
	# Ensure upgrade_levels are populated from JSON (only on first build).
	if ability.upgrade_levels.is_empty():
		DataLoader.apply_ability_data(ability)

	# Strictly use the entry at the ability's CURRENT level — no skipping.
	var entry: Dictionary = ability.next_upgrade_entry(rarity)
	if entry.is_empty():
		return null

	var u := AbilityLevelUpUpgrade.new()
	u.target_orb    = orb
	u.target_ability = ability
	u.ability_slot  = ability_index + 1  # convert to 1-based
	u._upgrade_entry = entry
	u.rarity         = rarity

	# Scale all stat deltas by the rarity multiplier.
	var mult: float = RARITY_MULTIPLIERS[clampi(rarity, 0, RARITY_MULTIPLIERS.size() - 1)]
	var raw_deltas: Dictionary = entry.get("stat_deltas", {})
	var scaled_deltas: Dictionary = {}
	for stat: String in raw_deltas.keys():
		scaled_deltas[stat] = raw_deltas[stat] * mult
	u._upgrade_entry = entry.duplicate()
	u._upgrade_entry["stat_deltas"] = scaled_deltas

	# Display name: two lines — "<Orb> (Slot N)" on line 1, entry display_name on line 2.
	u.display_name = "%s (Slot %d)\n%s" % [
		orb.display_name,
		u.ability_slot,
		entry.get("display_name", ability.display_name),
	]

	# Description: list each scaled stat delta on its own line.
	var lines: Array[String] = []
	for stat: String in scaled_deltas.keys():
		var val: float = scaled_deltas[stat]
		var label: String = DataLoader.STAT_LABELS.get(stat, stat.replace("_", " ").capitalize())
		var sign: String = "+" if val >= 0 else ""
		var val_str: String
		if float(int(val)) == val:
			val_str = "%s%d" % [sign, int(val)]
		else:
			val_str = "%s%.2f" % [sign, val]
			if "." in val_str:
				val_str = val_str.rstrip("0").rstrip(".")
		lines.append("%s: %s" % [label, val_str])
	u.description = "\n".join(lines)

	u.icon = ability.icon if "icon" in ability else null

	return u

func apply(_player: CharacterBody2D) -> void:
	if target_ability == null:
		return

	# Apply stat deltas.
	var stat_deltas: Dictionary = _upgrade_entry.get("stat_deltas", {})
	for stat_name: String in stat_deltas:
		var current = target_ability.stats.get(stat_name)
		if current == null:
			push_warning("AbilityLevelUpUpgrade: stat '%s' not found on %s" % [stat_name, target_ability.display_name])
			continue
		# If the stat is at its default "unused" sentinel (-1), treat it as
		# 0 before adding so the delta becomes the initial value.
		var base: float = current if current != -1 else 0.0
		target_ability.stats.set(stat_name, base + float(stat_deltas[stat_name]))

	# Promote any new main_stats.
	var new_main: Array = _upgrade_entry.get("main_stats", [])
	for s: String in new_main:
		if s not in target_ability.main_stats:
			target_ability.main_stats.append(s)

	# Advance the ability's level counter.
	target_ability.level += 1
