# relic_data.gd
class_name RelicData
extends Resource

@export var id:           String    = ""
@export var display_name: String    = ""
@export_multiline var description: String = ""
@export var icon:         Texture2D = null
@export var rarity:       int       = Util.Rarity.COMMON  # Util.Rarity value; default COMMON

func on_equip(player: CharacterBody2D) -> void:
	pass

func on_remove(player: CharacterBody2D) -> void:
	pass

func on_kill(enemy: Enemy, player: CharacterBody2D) -> void:
	pass

func on_damaged(amount: float, player: CharacterBody2D) -> float:
	return amount  # return (possibly modified) damage amount

func on_orb_shatter(orb: Orb, player: CharacterBody2D) -> void:
	pass

func tick(delta: float, player: CharacterBody2D) -> void:
	pass
