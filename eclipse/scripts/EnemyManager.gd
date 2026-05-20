# enemy_manager.gd
extends Node

var living_enemies:  Array[Enemy]   = []
var player:          CharacterBody2D
var tilemap_manager: Node = null

signal enemy_died

func spawn_squad(squad: Array[EnemyData], modifier: Util.Modifier) -> void:
	for data: EnemyData in squad:
		spawn_enemy(data, modifier)

func spawn_enemy(data: EnemyData, modifier: Util.Modifier = Util.Modifier.NONE) -> void:
	if data.scene == null:
		push_error("[EnemyManager] EnemyData '" + data.id + "' has no scene assigned.")
		return
	var enemy: Enemy = data.scene.instantiate()
	enemy.data            = data
	enemy.tilemap_manager = tilemap_manager
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	enemy.initialize(player, modifier)
	living_enemies.append(enemy)

## Register an enemy that was spawned outside the normal spawn_enemy path
## (e.g. pylons parented to another enemy).  Connects the died signal so the
## entry is cleaned up automatically.
func register_enemy(enemy: Enemy) -> void:
	if living_enemies.has(enemy):
		return
	enemy.died.connect(_on_enemy_died)
	living_enemies.append(enemy)

## Remove an enemy from the living list without freeing it.
## Use when you need manual control over the node lifetime.
func unregister_enemy(enemy: Enemy) -> void:
	living_enemies.erase(enemy)

func clear_all() -> void:
	for enemy: Enemy in living_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	living_enemies.clear()

func on_level_changed() -> void:
	clear_all()

func _on_enemy_died(enemy: Enemy) -> void:
	living_enemies.erase(enemy)
	emit_signal("enemy_died")

func Log(msg: Variant) -> void:
	print("[EnemyManager.gd] " + str(msg))
