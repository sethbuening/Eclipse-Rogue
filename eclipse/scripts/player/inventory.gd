# inventory.gd
extends Node

signal relic_added(relic: RelicData, quantity: int)
signal relic_removed(relic: RelicData, quantity: int)
signal orb_added(orb: Orb)
signal orb_removed(orb: Orb)
signal metal_added(metal: MetalData, quantity: int)
signal metal_removed(metal: MetalData, quantity: int)

var relics: Dictionary = {}   # RelicData → int
var orbs:   Array[Orb] = []
var metals: Dictionary = {}   # MetalData → int


# ── relics ────────────────────────────────────────────────────────────────────

func add_relic(relic: RelicData, quantity: int = 1) -> void:
	relics[relic] = relics.get(relic, 0) + quantity
	emit_signal("relic_added", relic, quantity)

func remove_relic(relic: RelicData, quantity: int = 1) -> bool:
	if relics.get(relic, 0) < quantity:
		return false
	relics[relic] -= quantity
	if relics[relic] <= 0:
		relics.erase(relic)
	emit_signal("relic_removed", relic, quantity)
	return true

func has_relic(relic: RelicData, quantity: int = 1) -> bool:
	return relics.get(relic, 0) >= quantity

func get_relic_quantity(relic: RelicData) -> int:
	return relics.get(relic, 0)


# ── metals ────────────────────────────────────────────────────────────────────

func add_metal(metal: MetalData, quantity: int = 1) -> void:
	metals[metal] = metals.get(metal, 0) + quantity
	emit_signal("metal_added", metal, quantity)

func remove_metals(metal: MetalData, quantity: int = 1) -> bool:
	if metals.get(metal, 0) < quantity:
		return false
	metals[metal] -= quantity
	if metals[metal] <= 0:
		metals.erase(metal)
	emit_signal("metal_removed", metal, quantity)
	return true

func has_metal(metal: MetalData, quantity: int = 1) -> bool:
	return metals.get(metal, 0) >= quantity

func get_metal_quantity(metal: MetalData) -> int:
	return metals.get(metal, 0)

func get_metals() -> Dictionary:
	return metals.duplicate()


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
