## ProfileInventory — THE only autoload in this system.
## Owns persistent item storage and the recipe registry.
## Everything else (RunInventory, CraftingStation) is instanced, not global.
class_name ProfileInventory
extends Node

const SAVE_PATH    := "user://profile.cfg"
const RECIPES_PATH := "res://data/recipes/"

signal item_changed(item: ItemData, new_qty: int)
signal recipe_unlocked(recipe: RecipeData)

## StringName id → int quantity
var _items:   Dictionary = {}
## All RecipeData resources loaded from disk
var _recipes: Array[Resource] = []

func _ready() -> void:
	_recipes = Util.load_resources(RECIPES_PATH)
	_load()

# ── items ─────────────────────────────────────────────────────────────────────

func add_item(item: ItemData, quantity: int = 1) -> void:
	_items[item.id] = _items.get(item.id, 0) + quantity
	item_changed.emit(item, _items[item.id])
	_save()

func remove_item(item: ItemData, quantity: int = 1) -> bool:
	if _items.get(item.id, 0) < quantity:
		return false
	_items[item.id] -= quantity
	if _items[item.id] <= 0:
		_items.erase(item.id)
	item_changed.emit(item, _items.get(item.id, 0))
	_save()
	return true

func get_quantity(item: ItemData) -> int:
	return _items.get(item.id, 0)

func has_item(item: ItemData, quantity: int = 1) -> bool:
	return _items.get(item.id, 0) >= quantity

# ── recipes ───────────────────────────────────────────────────────────────────

func get_recipes() -> Array[Resource]:
	return _recipes

func get_unlocked_recipes() -> Array[Resource]:
	return _recipes.filter(func(r: RecipeData) -> bool: return r.unlocked)

## Call this from achievements, data terminals, mission completion, etc.
func unlock_recipe(recipe: RecipeData) -> void:
	if recipe.unlocked:
		return
	recipe.unlocked = true
	recipe_unlocked.emit(recipe)
	_save()

# ── extraction: transfer surviving run items to profile ───────────────────────

func deposit_run_items(run_inv: RunInventory) -> void:
	for id: StringName in run_inv.get_all_items():
		var qty: int = run_inv.get_quantity_by_id(id)
		_items[id] = _items.get(id, 0) + qty
		# find the ItemData to emit the signal properly
		var item: ItemData = run_inv.get_item_data(id)
		if item:
			item_changed.emit(item, _items[id])
	_save()

# ── persistence ───────────────────────────────────────────────────────────────

func _save() -> void:
	var cfg := ConfigFile.new()
	for id: StringName in _items:
		cfg.set_value("items", str(id), _items[id])
	# persist which recipes are unlocked by index so we don't rely on .tres mutability
	for i: int in _recipes.size():
		if (_recipes[i] as RecipeData).unlocked:
			cfg.set_value("recipes", str(i), true)
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if cfg.has_section("items"):
		for key: String in cfg.get_section_keys("items"):
			_items[StringName(key)] = cfg.get_value("items", key, 0)
	if cfg.has_section("recipes"):
		for key: String in cfg.get_section_keys("recipes"):
			var idx: int = key.to_int()
			if idx < _recipes.size():
				(_recipes[idx] as RecipeData).unlocked = true
