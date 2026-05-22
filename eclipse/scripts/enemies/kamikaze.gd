# kamikaze.gd
class_name E_Kamikaze
extends Enemy

const TRIGGER_RANGE: float = 28.0
const EXPLOSION_RADIUS: float = 72.0

var _exploded: bool = false

func _tick_behavior(_delta: float) -> void:
	if global_position.distance_to(player.global_position) <= TRIGGER_RANGE:
		die()

func die() -> void:
	_explode()   # always explode on death too
	super.die()

func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	# damage player
	if global_position.distance_to(player.global_position) <= EXPLOSION_RADIUS:
		player.light -= data.damage
	# damage all nearby enemies (chain reaction potential)
	for enemy: Enemy in EnemyManager.living_enemies:
		if not is_instance_valid(enemy) or enemy == self:
			continue
		if global_position.distance_to(enemy.global_position) <= EXPLOSION_RADIUS:
			enemy.take_damage(data.damage / 2)
	# VFX — reuse GoldShockwave or spawn a particle burst
	ParticleManager.spawn_gold_bomb_trail(global_position)
	if not _status.has("dead"):  # avoid double-free if die() called _explode()
		queue_free()
