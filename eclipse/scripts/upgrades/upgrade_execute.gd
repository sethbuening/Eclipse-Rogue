# upgrade_execute.gd — deal bonus damage to enemies below 20% health
class_name UpgradeExecute
extends LevelUpUpgrade

const THRESHOLD: float = 0.2
const BONUS_DAMAGE: int = 30
var _cooldown: float = 0.0

func _init() -> void:
	display_name = "Execute"
	description  = "Instantly deal 30 bonus damage to enemies below 20% health."

func apply(player: CharacterBody2D) -> void:
	pass  # no one-time effect

func tick(delta: float, player: CharacterBody2D) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _cooldown > 0.0:
		return
	for enemy in EnemyManager.living_enemies:
		if not is_instance_valid(enemy):
			continue
		if float(enemy.health) / float(enemy.data.max_health) < THRESHOLD:
			enemy.take_damage(BONUS_DAMAGE)
			_cooldown = 0.5  # don't proc every frame
