# upgrade_flare_velocity.gd — increases how fast flares are thrown
class_name UpgradeFlareVelocity
extends LevelUpUpgrade

const VELOCITY_BONUS: float = 80.0  # pixels per second

func _init() -> void:
	display_name = "Strong Arm"
	description  = "Flares are thrown faster (+%.0f px/s)." % VELOCITY_BONUS
	rarity       = Util.Rarity.UNCOMMON

func apply(player: CharacterBody2D) -> void:
	player.flare_throw_velocity += VELOCITY_BONUS

func tick(_delta: float, _player: CharacterBody2D) -> void:
	pass
