class_name UpgradeCostTable

const BASE_COST: Dictionary = {
	Util.Rarity.COMMON:    10,
	Util.Rarity.UNCOMMON:  20,
	Util.Rarity.RARE:      35,
	Util.Rarity.EPIC:      55,
	Util.Rarity.LEGENDARY: 80,
}
const NEW_ITEM_SURCHARGE: int = 15

static func upgrade_cost(rarity: int) -> int:
	return BASE_COST.get(rarity, BASE_COST[Util.Rarity.COMMON])

static func new_item_cost(rarity: int) -> int:
	return upgrade_cost(rarity) + NEW_ITEM_SURCHARGE

## Builds { ItemData → int } for a given item and amount.
## Returns {} if item is null or amount <= 0 (treated as free).
static func build_cost(item: ItemData, amount: int) -> Dictionary:
	if item == null or amount <= 0:
		return {}
	return { item: amount }

## Returns cost dict scaled by tier: 0=free, 1=amount, 2=amount*2
static func build_tiered_cost(item: ItemData, base_amount: int, tier: int) -> Dictionary:
	if tier == 0 or item == null or base_amount <= 0:
		return {}
	return { item: base_amount * tier }
