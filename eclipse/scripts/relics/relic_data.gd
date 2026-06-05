# relic_data.gd
class_name RelicData
extends Resource

@export var id:           String    = ""
@export var display_name: String    = ""
@export var description:  String    = ""
@export var icon:         Texture2D = null
@export var rarity:       int       = 0  # Util.Rarity value; default COMMON

# Override these in subclasses or via composition
func on_equip(player: CharacterBody2D) -> void:
	pass

func on_kill(enemy: Enemy, player: CharacterBody2D) -> void:
	pass

func on_damaged(amount: float, player: CharacterBody2D) -> float:
	return amount  # return (possibly modified) damage amount

func on_orb_shatter(orb: Orb, player: CharacterBody2D) -> void:
	pass

func tick(delta: float, player: CharacterBody2D) -> void:
	pass
