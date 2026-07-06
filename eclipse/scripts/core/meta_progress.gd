# meta_progress.gd
# ---------------------------------------------------------------------------
# Stub meta-progression resource pool, spent in the Gear menu to craft/uncraft
# gear between runs. Add this as an autoload (singleton) named "MetaProgress",
# same convention as DataLoader/ItemManager/etc.
#
# TODO: back this with the (not-yet-built) save system instead of an
# in-memory value, and replace the flat int with real currency types once
# the crafting system is designed.
# ---------------------------------------------------------------------------
extends Node

signal currency_changed(new_amount: int)

var currency: int = 0

func add_currency(amount: int) -> void:
	currency = max(0, currency + amount)
	currency_changed.emit(currency)

func can_afford(amount: int) -> bool:
	return currency >= amount

func spend(amount: int) -> bool:
	if not can_afford(amount):
		return false
	currency -= amount
	currency_changed.emit(currency)
	return true
