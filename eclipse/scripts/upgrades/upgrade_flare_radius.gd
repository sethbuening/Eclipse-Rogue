# upgrade_flare_radius.gd — increases the illumination radius of thrown flares
class_name UpgradeFlareRadius
extends LevelUpUpgrade

const RADIUS_BONUS: float = 24.0  # pixels

func _init() -> void:
	display_name = "Wide Flame"
	description  = "Flares illuminate a wider area (+%.0fpx radius)." % RADIUS_BONUS
	rarity       = Util.Rarity.UNCOMMON

func apply(player: CharacterBody2D) -> void:
	player.flare_radius += RADIUS_BONUS

func tick(_delta: float, _player: CharacterBody2D) -> void:
	pass
