class_name RunInventory
extends Node

signal item_changed(item: ItemData, new_qty: int)
signal relic_added(relic: RelicData, quantity: int)
signal relic_removed(relic: RelicData, quantity: int)
signal ability_added(ability: AbilityData)
signal ability_removed(ability: AbilityData)

var _items:     Dictionary        = {}  # StringName → int
var _item_refs: Dictionary        = {}  # StringName → ItemData
var relics:     Dictionary        = {}  # RelicData → int
var abilities:  Array[AbilityData] = []

var _player_stats: PlayerStats = null

# ── items ─────────────────────────────────────────────────────────────────────

func add_item(item: ItemData, quantity: int = 1) -> void:
	_item_refs[item.id] = item
	_items[item.id] = _items.get(item.id, 0) + quantity
	item_changed.emit(item, _items[item.id])

func remove_item(item: ItemData, quantity: int = 1) -> bool:
	if _items.get(item.id, 0) < quantity:
		return false
	_items[item.id] -= quantity
	if _items[item.id] <= 0:
		_items.erase(item.id)
	item_changed.emit(item, _items.get(item.id, 0))
	return true

func has_item(item: ItemData, quantity: int = 1) -> bool:
	return _items.get(item.id, 0) >= quantity

func get_quantity(item: ItemData) -> int:
	return _items.get(item.id, 0)

func get_quantity_by_id(id: StringName) -> int:
	return _items.get(id, 0)

func get_item_data(id: StringName) -> ItemData:
	return _item_refs.get(id, null)

func get_all_item_ids() -> Array:
	return _items.keys()

## cost: Array of { "item": ItemData, "quantity": int }
func can_afford(cost: Array) -> bool:
	for slot: Dictionary in cost:
		if not has_item(slot["item"], slot["quantity"]):
			return false
	return true

func spend_for_upgrade(cost: Array) -> bool:
	if not can_afford(cost):
		return false
	for slot: Dictionary in cost:
		remove_item(slot["item"], slot["quantity"])
	return true

# ── relics ────────────────────────────────────────────────────────────────────

func add_relic(relic: RelicData, quantity: int = 1) -> void:
	if _player_stats != null and _player_stats.relic_max > 0:
		var total: int = 0
		for v: int in relics.values(): total += v
		if total + quantity > _player_stats.relic_max:
			return
	relics[relic] = relics.get(relic, 0) + quantity
	relic_added.emit(relic, quantity)

func remove_relic(relic: RelicData, quantity: int = 1) -> bool:
	if relics.get(relic, 0) < quantity:
		return false
	relics[relic] -= quantity
	if relics[relic] <= 0:
		relics.erase(relic)
	relic_removed.emit(relic, quantity)
	return true

func has_relic(relic: RelicData, quantity: int = 1) -> bool:
	return relics.get(relic, 0) >= quantity

func get_relic_quantity(relic: RelicData) -> int:
	return relics.get(relic, 0)

# ── abilities ─────────────────────────────────────────────────────────────────

func add_ability(ability: AbilityData) -> void:
	ability.ensure_loaded()
	abilities.append(ability)
	ability_added.emit(ability)

func remove_ability(ability: AbilityData) -> bool:
	if not abilities.has(ability):
		return false
	abilities.erase(ability)
	ability_removed.emit(ability)
	return true

func has_ability(ability: AbilityData) -> bool:
	return abilities.has(ability)
