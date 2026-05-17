# inventory.gd
extends Node

signal item_added(item_type: Util.tile, quantity: int)
signal item_removed(item_type: Util.tile, quantity: int)
signal orb_added(orb: Orb)
signal orb_removed(orb: Orb)

var items: Dictionary = {}
var orbs:  Array[Orb] = []

# ── items ─────────────────────────────────────────────────────────────────────
func add(item_type: Util.tile, quantity: int = 1) -> void:
	items[item_type] = items.get(item_type, 0) + quantity
	emit_signal("item_added", item_type, quantity)

func remove(item_type: Util.tile, quantity: int = 1) -> bool:
	if items.get(item_type, 0) < quantity:
		return false
	items[item_type] -= quantity
	if items[item_type] <= 0:
		items.erase(item_type)
	emit_signal("item_removed", item_type, quantity)
	return true

func has(item_type: Util.tile, quantity: int = 1) -> bool:
	return items.get(item_type, 0) >= quantity

func get_quantity(item_type: Util.tile) -> int:
	return items.get(item_type, 0)

# ── orbs ──────────────────────────────────────────────────────────────────────
func add_orb(orb: Orb) -> void:
	orbs.append(orb)
	emit_signal("orb_added", orb)

func remove_orb(orb: Orb) -> bool:
	if not orbs.has(orb):
		return false
	orbs.erase(orb)
	emit_signal("orb_removed", orb)
	return true

func get_orbs_by_trigger(trigger: AbilityData.TriggerType) -> Array[Orb]:
	return orbs.filter(func(o: Orb) -> bool:
		return o.abilities.any(func(a: AbilityData) -> bool:
			return a != null and a.trigger_type == trigger
		)
	)

func get_all_active_orbs() -> Array[Orb]:
	return get_orbs_by_trigger(AbilityData.TriggerType.ACTIVE)

func get_all_passive_orbs() -> Array[Orb]:
	return get_orbs_by_trigger(AbilityData.TriggerType.PASSIVE)
