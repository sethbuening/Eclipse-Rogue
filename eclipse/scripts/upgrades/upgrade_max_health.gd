# upgrade_max_health.gd — permanently increases the player's maximum health
class_name UpgradeMaxHealth
extends LevelUpUpgrade

const HEALTH_BONUS: int = 25

func _init() -> void:
	display_name = "Fortified Core"
	description  = "Increases maximum health by %d." % HEALTH_BONUS
	rarity       = Util.Rarity.COMMON

func apply(player: CharacterBody2D) -> void:
	player.max_health += HEALTH_BONUS
	player.health     += HEALTH_BONUS  # heal for the bonus so HP doesn't feel wasted

func tick(_delta: float, _player: CharacterBody2D) -> void:
	pass
