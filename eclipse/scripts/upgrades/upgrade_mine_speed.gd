# upgrade_mine_speed.gd — increases mining tick rate
class_name UpgradeMineSpeed
extends LevelUpUpgrade

const SPEED_BONUS: float = 0.20  # +20% mining speed per stack

func _init() -> void:
	display_name = "Hardened Pick"
	description  = "Increases mining speed by 20%."
	rarity       = Util.Rarity.COMMON

func apply(player: CharacterBody2D) -> void:
	player.mine_speed_mult += SPEED_BONUS

func tick(_delta: float, _player: CharacterBody2D) -> void:
	pass
