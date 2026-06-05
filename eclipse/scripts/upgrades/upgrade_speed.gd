# res://scripts/upgrades/upgrade_speed.gd
class_name UpgradeSpeed
extends LevelUpUpgrade

func _init() -> void:
	display_name = "Swift Feet"
	description  = "Increases movement speed by 15%."

func apply(player: CharacterBody2D) -> void:
	player.speed *= 1.15
