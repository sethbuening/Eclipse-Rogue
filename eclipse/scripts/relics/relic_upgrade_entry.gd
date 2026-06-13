# relic_upgrade_entry.gd
# ---------------------------------------------------------------------------
# A single upgrade entry for a relic, mirroring AbilityUpgradeEntry.
#
# Each entry represents one upgrade level for a relic. The stat_deltas_*
# dictionaries map RelicData property name → additive float delta, one per
# rarity tier. get_stat_deltas() falls back up the rarity ladder to the
# nearest populated tier.
#
# JSON columns (relics.json, one row per stat per level):
#   "value_common"    → Common delta
#   "value_uncommon"  → Uncommon delta
#   "value_rare"      → Rare delta
#   "value_epic"      → Epic delta
#   "value_legendary" → Legendary delta
#   "value"           → fallback for all tiers with no explicit value
# ---------------------------------------------------------------------------
class_name RelicUpgradeEntry
extends Resource

# ── display ──────────────────────────────────────────────────────────────────

@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null

# ── per-rarity stat deltas ────────────────────────────────────────────────────
# Each dictionary maps a RelicData exported property name → additive float delta.

@export_group("Stat Deltas")
@export var stat_deltas_common:    Dictionary = {}
@export var stat_deltas_uncommon:  Dictionary = {}
@export var stat_deltas_rare:      Dictionary = {}
@export var stat_deltas_epic:      Dictionary = {}
@export var stat_deltas_legendary: Dictionary = {}

# ── helpers ───────────────────────────────────────────────────────────────────

## Returns the stat-delta dictionary for [rarity] (a Util.Rarity int value).
## Falls back to the nearest lower rarity that has a non-empty dictionary.
func get_stat_deltas(rarity: int) -> Dictionary:
	var tiers: Array = [
		stat_deltas_common,
		stat_deltas_uncommon,
		stat_deltas_rare,
		stat_deltas_epic,
		stat_deltas_legendary,
	]
	for i: int in range(rarity, -1, -1):
		if not tiers[i].is_empty():
			return tiers[i]
	return {}

## Convert to the plain Dictionary format that RelicLevelUpUpgrade expects.
func to_dict(rarity: int = 0) -> Dictionary:
	return {
		"display_name": display_name,
		"description":  description,
		"icon":         icon,
		"stat_deltas":  get_stat_deltas(rarity),
	}
