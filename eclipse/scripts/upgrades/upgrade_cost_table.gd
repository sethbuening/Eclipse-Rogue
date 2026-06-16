# upgrade_cost_table.gd
# ---------------------------------------------------------------------------
# Central source of truth for level-up upgrade metal costs.
#
# Every ability/relic upgrade and "add new ability/relic" offer now costs a
# quantity of a specific metal (the ability's ore_type, or a relic's
# associated metal where applicable). Higher rarity upgrades cost more.
#
# This is the system referenced in the design discussion: instead of free
# level-up power, players "forge" upgrades using ore gathered from mining,
# making metals matter for *every* level-up choice — not just forge visits.
# ---------------------------------------------------------------------------
class_name UpgradeCostTable

# Base ore cost per rarity tier (Util.Rarity int: 0=Common … 4=Legendary).
const BASE_COST: Dictionary = {
	Util.Rarity.COMMON:    10,
	Util.Rarity.UNCOMMON:  20,
	Util.Rarity.RARE:      35,
	Util.Rarity.EPIC:      55,
	Util.Rarity.LEGENDARY: 80,
}

# Extra flat cost added for upgrades that add a brand-new ability/relic
# (these are stronger than a single stat bump).
const NEW_ITEM_SURCHARGE: int = 15

## Returns the ore cost for a stat-upgrade of the given rarity.
static func upgrade_cost(rarity: int) -> int:
	return BASE_COST.get(rarity, BASE_COST[Util.Rarity.COMMON])

## Returns the ore cost for an "add new ability/relic" offer of the given rarity.
static func new_item_cost(rarity: int) -> int:
	return upgrade_cost(rarity) + NEW_ITEM_SURCHARGE

## Builds a single-metal cost dictionary: { metal: amount }.
## Returns an empty dictionary if [metal] is null (cost can't be enforced,
## e.g. no MetalData found for the ability's ore_type — treated as free).
static func build_cost(metal: MetalData, amount: int) -> Dictionary:
	if metal == null or amount <= 0:
		return {}
	return { metal: amount }

# ── discount roll ─────────────────────────────────────────────────────────────
# Chance for an upgrade's cost to roll a discount. When it hits, the total
# ore cost drops, but is split across the ability's own metal plus one other
# random metal instead of being paid entirely in one type — a cheaper but
# less flexible price (the player needs a bit of a second ore too).

const DISCOUNT_CHANCE:    float = 0.25  # 25% chance per upgrade offer
const DISCOUNT_REDUCTION: float = 0.30  # total cost reduced by 30% when it hits
## How much of the (discounted) total goes to the primary metal vs the
## secondary one. 0.6 = 60% primary / 40% secondary.
const DISCOUNT_PRIMARY_SHARE: float = 0.6

## Builds the ore cost for an upgrade, possibly rolling a discount that
## splits the (reduced) total across [primary_metal] and a second random
## metal drawn from [secondary_pool] (an Array[MetalData] of candidates,
## e.g. ItemManager.get_all_metals() or the player's current ore holdings).
##
## Returns a Dictionary { MetalData: int amount }:
##   - No discount (or no valid secondary candidate): single-metal cost,
##     exactly like build_cost(primary_metal, amount).
##   - Discount hit: two-metal cost, primary + secondary, summing to less
##     than [amount].
static func build_discountable_cost(
		primary_metal:   MetalData,
		amount:          int,
		secondary_pool:  Array[MetalData] = []
) -> Dictionary:
	if primary_metal == null or amount <= 0:
		return {}

	# Candidates for the secondary metal: anything but the primary itself.
	var candidates: Array[MetalData] = []
	for m: MetalData in secondary_pool:
		if m != null and m != primary_metal:
			candidates.append(m)

	if candidates.is_empty() or randf() >= DISCOUNT_CHANCE:
		return { primary_metal: amount }

	var secondary_metal: MetalData = candidates[randi() % candidates.size()]

	var discounted_total: int = maxi(2, roundi(amount * (1.0 - DISCOUNT_REDUCTION)))
	var primary_amount:   int = maxi(1, roundi(discounted_total * DISCOUNT_PRIMARY_SHARE))
	var secondary_amount: int = maxi(1, discounted_total - primary_amount)

	return {
		primary_metal:   primary_amount,
		secondary_metal: secondary_amount,
	}
