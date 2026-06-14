# enemy_manager.gd
extends Node

# ── constants ─────────────────────────────────────────────────────────────────

const SEP_CELL:     float = 64.0
const AI_TICK_RATE: float = 1.0 / 20.0
const CULL_MARGIN:  float = 64.0   # pixels beyond screen edge before culling

# ── public state ──────────────────────────────────────────────────────────────

var living_enemies: Array[Enemy] = []
var player:         CharacterBody2D
var tilemap:        Node = null

# set of enemies currently offscreen — read by enemy.gd in tick_ai
var offscreen_enemies: Dictionary = {}

## When true (toggled by dev_mode), all enemy children stay visible
## regardless of on-screen culling — useful for debugging spawn logic.
var debug_force_visible: bool = false

signal enemy_died(enemy: Enemy)

# ── private state ─────────────────────────────────────────────────────────────

var _sep_grid: Dictionary = {}
var _ai_accum: float      = 0.0
var _camera:   Camera2D   = null

# ── process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_update_visibility()

	for enemy in living_enemies:
		if is_instance_valid(enemy):
			enemy.tick_move(delta, offscreen_enemies.has(enemy))

	_ai_accum += delta
	if _ai_accum < AI_TICK_RATE:
		return

	var ai_delta: float = _ai_accum
	_ai_accum = 0.0
	_build_sep_grid()
	for enemy in living_enemies:
		if is_instance_valid(enemy):
			enemy.tick_ai(ai_delta)

# ── visibility culling ────────────────────────────────────────────────────────

func _update_visibility() -> void:
	offscreen_enemies.clear()
	var vp_size: Vector2     = get_viewport().get_visible_rect().size
	var transform: Transform2D = get_viewport().get_canvas_transform()

	for enemy in living_enemies:
		if not is_instance_valid(enemy):
			continue
		var screen_pos: Vector2 = transform * enemy.global_position
		var on_screen: bool = screen_pos.x > -CULL_MARGIN \
						  and screen_pos.x < vp_size.x + CULL_MARGIN \
						  and screen_pos.y > -CULL_MARGIN \
						  and screen_pos.y < vp_size.y + CULL_MARGIN
		if not on_screen:
			offscreen_enemies[enemy] = true
		var show: bool = on_screen or debug_force_visible
		for child in enemy.get_children():
			if child is Node2D:
				child.visible = show

# ── separation grid ───────────────────────────────────────────────────────────

func _build_sep_grid() -> void:
	_sep_grid.clear()
	for enemy in living_enemies:
		if not is_instance_valid(enemy):
			continue
		var cell := Vector2i(
			int(floor(enemy.global_position.x / SEP_CELL)),
			int(floor(enemy.global_position.y / SEP_CELL))
		)
		if not _sep_grid.has(cell):
			_sep_grid[cell] = []
		_sep_grid[cell].append(enemy)

func get_nearby_enemies(pos: Vector2, radius: float) -> Array:
	var result:      Array = []
	var cell_radius: int   = int(ceil(radius / SEP_CELL)) + 1
	var origin := Vector2i(
		int(floor(pos.x / SEP_CELL)),
		int(floor(pos.y / SEP_CELL))
	)
	for dx in range(-cell_radius, cell_radius + 1):
		for dy in range(-cell_radius, cell_radius + 1):
			var bucket = _sep_grid.get(origin + Vector2i(dx, dy), null)
			if bucket == null:
				continue
			for e in bucket:
				if is_instance_valid(e):
					result.append(e)
	return result

# ── spawning ──────────────────────────────────────────────────────────────────

func spawn_squad(squad: Array[EnemyData], modifier: Util.Modifier) -> void:
	for d: EnemyData in squad:
		spawn_enemy(d, modifier)

func spawn_enemy(data: EnemyData, modifier: Util.Modifier = Util.Modifier.NONE) -> void:
	if data.scene == null:
		push_error("[EnemyManager] '%s' has no scene assigned." % data.id)
		return
	var enemy: Enemy  = data.scene.instantiate()
	enemy.data        = data
	enemy.tilemap     = tilemap
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	enemy.setup(AI_TICK_RATE)
	enemy.initialize(player, modifier)
	living_enemies.append(enemy)

func register_enemy(enemy: Enemy) -> void:
	if living_enemies.has(enemy):
		return
	enemy.died.connect(_on_enemy_died)
	living_enemies.append(enemy)

func unregister_enemy(enemy: Enemy) -> void:
	living_enemies.erase(enemy)

# ── lifecycle ─────────────────────────────────────────────────────────────────

func clear_all() -> void:
	for enemy: Enemy in living_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	living_enemies.clear()

func on_level_changed() -> void:
	clear_all()

func _on_enemy_died(enemy: Enemy) -> void:
	living_enemies.erase(enemy)
	emit_signal("enemy_died", enemy)
