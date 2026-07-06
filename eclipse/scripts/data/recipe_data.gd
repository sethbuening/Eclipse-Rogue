class_name RecipeData
extends Resource

## inputs/outputs: Array of { "item": ItemData, "quantity": int }
@export var inputs:   Array[Dictionary] = []
@export var outputs:  Array[Dictionary] = []
@export var unlocked: bool              = false

func can_craft(profile: ProfileInventory) -> bool:
	if not unlocked:
		return false
	for slot: Dictionary in inputs:
		if profile.get_quantity(slot["item"]) < slot["quantity"]:
			return false
	return true

## Executes the craft directly against the profile inventory.
## Returns false if can_craft fails.
func craft(profile: ProfileInventory) -> bool:
	if not can_craft(profile):
		return false
	for slot: Dictionary in inputs:
		profile.remove_item(slot["item"], slot["quantity"])
	for slot: Dictionary in outputs:
		profile.add_item(slot["item"], slot["quantity"])
	return true
