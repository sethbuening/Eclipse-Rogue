# relic_data.gd
class_name RelicData
extends Resource

@export var id:           String    = ""
@export var display_name: String    = ""
@export_multiline var description: String = ""
@export var icon:         Texture2D = null
@export var rarity:       int       = Util.Rarity.COMMON  # Util.Rarity value; default COMMON

# ── upgrade levels ────────────────────────────────────────────────────────────

## Current upgrade level of this relic. Starts at 0 (no upgrades taken yet).
## Incremented by RelicLevelUpUpgrade.apply().
var level: int = 0

## Ordered list of upgrade entries for this relic (one per upgrade level).
## An empty array means the relic cannot be upgraded via the relic screen.
@export var upgrade_levels: Array[RelicUpgradeEntry] = []

## Returns the next upgrade entry as a Dictionary for the given rarity.
func next_upgrade_entry(rarity: int = 0) -> Dictionary:
	if level < upgrade_levels.size():
		return upgrade_levels[level].to_dict(rarity)
	return {}

## True when at least one more upgrade level is available.
func can_upgrade() -> bool:
	return level < upgrade_levels.size()

func on_equip(player: CharacterBody2D) -> void:
	pass

func on_remove(player: CharacterBody2D) -> void:
	pass

func on_kill(enemy: Enemy, player: CharacterBody2D) -> void:
	pass

func on_damaged(amount: float, player: CharacterBody2D) -> float:
	return amount  # return (possibly modified) damage amount

func on_orb_shatter(orb: Orb, player: CharacterBody2D) -> void:
	pass

func tick(delta: float, player: CharacterBody2D) -> void:
	pass
