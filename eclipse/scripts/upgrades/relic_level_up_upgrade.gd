# relic_level_up_upgrade.gd
# ---------------------------------------------------------------------------
# A LevelUpUpgrade that upgrades one specific relic already in the player's
# inventory. Mirrors AbilityLevelUpUpgrade exactly.
#
# Upgrades are strictly sequential: the upgrade offered is always for the
# relic's CURRENT level, which advances it to level+1.
# ---------------------------------------------------------------------------
class_name RelicLevelUpUpgrade
extends LevelUpUpgrade

var target_relic: RelicData = null

# The upgrade entry dict pulled from target_relic.upgrade_levels[level].
var _upgrade_entry: Dictionary = {}

static func build(relic: RelicData, rarity: int) -> RelicLevelUpUpgrade:
	# Populate upgrade_levels from JSON if not already loaded.
	if relic.upgrade_levels.is_empty():
		DataLoader.apply_relic_data(relic)

	var entry: Dictionary = relic.next_upgrade_entry(rarity)
	if entry.is_empty():
		return null

	var u := RelicLevelUpUpgrade.new()
	u.target_relic   = relic
	u._upgrade_entry = entry.duplicate()
	u.rarity         = rarity

	u.display_name = "%s\n%s" % [
		relic.display_name,
		entry.get("display_name", "Upgrade"),
	]

	# Build description from stat deltas.
	var stat_deltas: Dictionary = entry.get("stat_deltas", {})
	if stat_deltas.is_empty():
		u.description = entry.get("description", "")
	else:
		var lines: Array[String] = []
		for stat: String in stat_deltas.keys():
			var val: float = stat_deltas[stat]
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

	u.icon = entry.get("icon", null)
	if u.icon == null:
		u.icon = relic.icon

	return u

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
