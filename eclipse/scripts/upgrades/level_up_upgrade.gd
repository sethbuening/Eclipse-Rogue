class_name LevelUpUpgrade
extends Resource

@export var display_name: String    = ""
@export_multiline var description: String = ""
@export var icon:         Texture2D = null
@export var rarity:       int       = 0  # Util.Rarity

## { ItemData → int }. Empty = free.
var item_cost: Dictionary = {}

## 0 = free, 1 = base cost, 2 = double cost
var tier: int = 0

func is_affordable(run_inv: RunInventory) -> bool:
	for item: ItemData in item_cost:
		if not run_inv.has_item(item, item_cost[item]):
			return false
	return true

func pay_cost(run_inv: RunInventory) -> bool:
	for item: ItemData in item_cost:
		if not run_inv.remove_item(item, item_cost[item]):
			return false
	return true

func apply(player: CharacterBody2D) -> void:
	pass

func tick(_delta: float, _player: CharacterBody2D) -> void:
	pass
