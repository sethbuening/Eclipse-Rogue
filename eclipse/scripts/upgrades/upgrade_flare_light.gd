# upgrade_flare_light.gd — increases the brightness/energy of thrown flares
class_name UpgradeFlareLightLevel
extends LevelUpUpgrade

const LIGHT_BONUS: float = 0.5

func _init() -> void:
	display_name = "Bright Core"
	description  = "Flares burn brighter, increasing their light level by %.1f." % LIGHT_BONUS
	rarity       = Util.Rarity.UNCOMMON

func apply(player: CharacterBody2D) -> void:
	player.flare_light_level += LIGHT_BONUS

func tick(_delta: float, _player: CharacterBody2D) -> void:
	pass
