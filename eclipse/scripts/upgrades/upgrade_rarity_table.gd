# upgrade_rarity_table.gd
# ---------------------------------------------------------------------------
# Central source of truth for level-up upgrade rarity chances.
#
# BASE_WEIGHTS defines the un-modified probability weight for each rarity
# tier. These are relative, not percentages — a weight of 60 vs 20 means
# Common is 3× as likely as Uncommon, everything else equal.
#
# LUCK_WEIGHT_BONUS is added to every non-Common tier per point of luck the
# player has. Luck does NOT reduce Common's weight — it just makes higher
# tiers more competitive. One luck point shifts the table meaningfully but
# won't trivialise Common until ~20+ luck.
#
# Example at luck = 0:
#   Common 60, Uncommon 25, Rare 10, Epic 4, Legendary 1  → total 100
#   Common  ≈ 60%,  Uncommon ≈ 25%,  Rare ≈ 10%,  Epic ≈ 4%,  Legendary ≈ 1%
#
# Example at luck = 5 (LUCK_WEIGHT_BONUS = 3.0 per tier):
#   Common 60, Uncommon 40, Rare 25, Epic 19, Legendary 16  → total 160
#   Common ≈ 37.5%, Uncommon ≈ 25%, Rare ≈ 15.6%, Epic ≈ 11.9%, Legendary ≈ 10%
# ---------------------------------------------------------------------------
class_name UpgradeRarityTable

# Base weight per rarity tier. Keys are Util.Rarity int values.
const BASE_WEIGHTS: Dictionary = {
	Util.Rarity.COMMON:    60.0,
	Util.Rarity.UNCOMMON:  25.0,
	Util.Rarity.RARE:      10.0,
	Util.Rarity.EPIC:       4.0,
	Util.Rarity.LEGENDARY:  1.0,
}

# Weight added to every non-Common tier per point of player luck.
const LUCK_WEIGHT_BONUS: float = 3.0

# Roll a rarity tier given a luck value. Returns a Util.Rarity int.
static func roll(luck: float) -> int:
	var weights: Dictionary = {}
	for tier: int in BASE_WEIGHTS:
		var bonus: float = 0.0
		if tier != Util.Rarity.COMMON:
			bonus = luck * LUCK_WEIGHT_BONUS
		weights[tier] = BASE_WEIGHTS[tier] + bonus

	var total: float = 0.0
	for tier: int in weights:
		total += weights[tier]

	var roll_val: float = randf() * total
	var accum:    float = 0.0
	for tier: int in weights:
		accum += weights[tier]
		if roll_val <= accum:
			return tier

	return Util.Rarity.COMMON
