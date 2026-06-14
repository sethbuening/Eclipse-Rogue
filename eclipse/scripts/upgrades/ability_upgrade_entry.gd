# ability_upgrade_entry.gd
# ---------------------------------------------------------------------------
# A single level-up upgrade entry for an ability.
#
# stat_deltas_by_rarity holds five separate delta dictionaries — one per
# rarity tier (indexed by Util.Rarity int: 0=Common … 4=Legendary).
# When AbilityLevelUpUpgrade applies an upgrade it passes the rolled rarity
# so the correct delta is used.
#
# In the Inspector each tier shows up as its own Dictionary export so you can
# tune values independently. If you want all rarities to share the same value,
# set stat_deltas_common and leave the others empty — get_stat_deltas() falls
# back up the rarity ladder to the nearest populated tier.
#
# Data-loader usage (abilities.json columns, one row per stat per level):
#   "value_common"    → Common delta   (required if using per-rarity values)
#   "value_uncommon"  → Uncommon delta
#   "value_rare"      → Rare delta
#   "value_epic"      → Epic delta
#   "value_legendary" → Legendary delta
#   "value"           → fallback applied to ALL tiers that have no explicit value
#
# Code usage:
#   var entry := AbilityUpgradeEntry.new()
#   entry.display_name = "Overcharged Bolt"
#   entry.stat_deltas_common    = { "damage": 4.0 }
#   entry.stat_deltas_uncommon  = { "damage": 6.0 }
#   entry.stat_deltas_rare      = { "damage": 9.0 }
#   entry.stat_deltas_epic      = { "damage": 13.0 }
#   entry.stat_deltas_legendary = { "damage": 18.0 }
#   ability.upgrade_levels.append(entry)
# ---------------------------------------------------------------------------
class_name AbilityUpgradeEntry
extends Resource

# ── display ──────────────────────────────────────────────────────────────────

## Title shown on the level-up card. If blank, the ability's own
## display_name is used as a fallback.
@export var display_name: String = ""

## Body text shown on the level-up card.
@export_multiline var description: String = ""

## Optional icon override for the level-up card.
## When null, the ability's own icon is used.
@export var icon: Texture2D = null

# ── per-rarity stat deltas ────────────────────────────────────────────────────
# Each dictionary maps AbilityStats property name → additive float delta.
# Negative values reduce the stat.  Leave a dictionary empty to inherit from
# the tier below (see get_stat_deltas).

@export_group("Stat Deltas")
## Deltas applied when the upgrade rolls Common rarity.
@export var stat_deltas_common:    Dictionary = {}
## Deltas applied when the upgrade rolls Uncommon rarity.
@export var stat_deltas_uncommon:  Dictionary = {}
## Deltas applied when the upgrade rolls Rare rarity.
@export var stat_deltas_rare:      Dictionary = {}
## Deltas applied when the upgrade rolls Epic rarity.
@export var stat_deltas_epic:      Dictionary = {}
## Deltas applied when the upgrade rolls Legendary rarity.
@export var stat_deltas_legendary: Dictionary = {}

# ── stat promotion ────────────────────────────────────────────────────────────

## Stat names to add to ability.main_stats when this upgrade is applied
## (regardless of rarity). Stats in main_stats are multiplied by orb_potency.
@export var main_stats: Array[String] = []

# ── helpers ───────────────────────────────────────────────────────────────────

## Returns the stat-delta dictionary for [rarity] (a Util.Rarity int value).
## Falls back to the nearest lower rarity that has a non-empty dictionary,
## then to an empty dict if none are populated.
func get_stat_deltas(rarity: int) -> Dictionary:
	var tiers: Array = [
		stat_deltas_common,
		stat_deltas_uncommon,
		stat_deltas_rare,
		stat_deltas_epic,
		stat_deltas_legendary,
	]
	# Walk from the requested rarity down to COMMON looking for a populated tier.
	for i: int in range(rarity, -1, -1):
		if not tiers[i].is_empty():
			return tiers[i]
	return {}

## Convert to the plain Dictionary format that AbilityLevelUpUpgrade expects.
## [rarity] selects which delta set to embed (Util.Rarity int).
func to_dict(rarity: int = 0) -> Dictionary:
	return {
		"display_name": display_name,
		"description":  description,
		"icon":         icon,
		"stat_deltas":  get_stat_deltas(rarity),
		"main_stats":   main_stats,
	}
