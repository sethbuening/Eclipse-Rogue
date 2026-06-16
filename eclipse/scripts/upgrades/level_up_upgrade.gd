class_name LevelUpUpgrade
extends Resource

@export var display_name: String    = ""
@export_multiline var description: String = ""
@export var icon:         Texture2D = null
@export var rarity:       int       = 0  # Util.Rarity value; default COMMON

## Ore cost required to take this upgrade: { MetalData → int amount }.
## Empty dictionary means free (no metal requirement).
var metal_cost: Dictionary = {}

## Returns true if [inventory] (player/Inventory node) holds enough of every
## metal in metal_cost.
func is_affordable(inventory: Node) -> bool:
	for metal: MetalData in metal_cost:
		if not inventory.has_metal(metal, metal_cost[metal]):
			return false
	return true

## Deducts metal_cost from [inventory]. Call only after is_affordable()
## returns true. Returns false if any deduction fails (shouldn't happen if
## is_affordable() was checked first).
func pay_cost(inventory: Node) -> bool:
	for metal: MetalData in metal_cost:
		if not inventory.remove_metals(metal, metal_cost[metal]):
			return false
	return true

func apply(player: CharacterBody2D) -> void:
	pass

## Called every frame after the upgrade is applied.
## Override in subclasses that need to poll conditions.
func tick(delta: float, player: CharacterBody2D) -> void:
	pass
