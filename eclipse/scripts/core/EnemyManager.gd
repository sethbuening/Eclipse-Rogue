extends Node

const AI_TICK_RATE:          float = 1.0 / 20.0
const CULL_MARGIN:           float = 64.0
const NEAR_RADIUS_SQ:        float = 700.0  * 700.0
const FAR_RADIUS_SQ:         float = 1400.0 * 1400.0
const MID_TIER_MULT:         float = 2.0
const FAR_TIER_MULT:         float = 5.0
const MAX_POOL_SIZE_PER_TYPE: int  = 64
const SEP_CELL:              float = 32.0
const MAX_ENEMY_DISTANCE_SQ: float = 1800.0 * 1800.0
const TELEPORT_CHECK_BATCH:  int   = 30
const OFFSCREEN_AI_MULT:     float = 4.0   # extra AI slowdown when offscreen
const OFFSCREEN_MOVE_DIV:    int   = 4     # only integrate movement every Nth frame offscreen

var living_enemies:      Array[Enemy] = []
var player:              CharacterBody2D
var tilemap:             Node = null
var debug_force_visible: bool = false

signal enemy_died(enemy: Enemy)

var _ai_accum:         float       = 0.0
var _pool:             Dictionary  = {}
var _flow_cache:       Dictionary  = {}
var _sep_grid:         Dictionary  = {}
var _tick_index:       int         = 0
var _teleport_index:   int         = 0
var _vp_size:          Vector2     = Vector2.ZERO
var _canvas_transform: Transform2D

# --- Timing (usec accumulators, reset every T_PRINT_EVERY frames) ---
const T_PRINT_EVERY: int = 60
var _t_frame:        int = 0   # frame counter
var _t_main_loop:    int = 0   # sep grid + visibility + tick_move
var _t_teleport:     int = 0   # teleport batch
var _t_ai:           int = 0   # AI tick slice

func _process(delta: float) -> void:
	var player_pos: Vector2 = player.global_position if player != null else Vector2.ZERO
	_vp_size          = get_viewport().get_visible_rect().size
	_canvas_transform = get_viewport().get_canvas_transform()

	# --- Main loop: sep grid + visibility + tick_move ---
	var t0: int = Time.get_ticks_usec()
	_sep_grid.clear()
	var count: int = living_enemies.size()
	for i in count:
		var enemy: Enemy = living_enemies[i]
		var epos: Vector2 = enemy.global_position

		var sp: Vector2 = _canvas_transform * epos
		var on: bool    = sp.x > -CULL_MARGIN and sp.x < _vp_size.x + CULL_MARGIN \
						and sp.y > -CULL_MARGIN and sp.y < _vp_size.y + CULL_MARGIN
		var was_offscreen: bool = enemy._offscreen
		enemy._offscreen = not on
		if was_offscreen != enemy._offscreen or debug_force_visible:
			var show: bool = on or debug_force_visible
			for child in enemy.get_children():
				if child is Node2D: child.visible = show

		if not enemy._offscreen:
			var sc := Vector2i(int(floor(epos.x / SEP_CELL)), int(floor(epos.y / SEP_CELL)))
			if not _sep_grid.has(sc): _sep_grid[sc] = []
			_sep_grid[sc].append(enemy)
			enemy._move_skip = 0
			enemy.tick_move(delta, false)
		else:
			enemy._move_accum += delta
			enemy._move_skip  += 1
			if enemy._move_skip >= OFFSCREEN_MOVE_DIV:
				var d: float = enemy._move_accum
				enemy._move_accum = 0.0
				enemy._move_skip  = 0
				enemy.tick_move(d, true)
	_t_main_loop += Time.get_ticks_usec() - t0

	# --- Teleport batch ---
	t0 = Time.get_ticks_usec()
	if count > 0:
		var t_end: int = mini(_teleport_index + TELEPORT_CHECK_BATCH, count)
		for i in range(_teleport_index, t_end):
			var enemy: Enemy = living_enemies[i]
			if enemy.global_position.distance_squared_to(player_pos) > MAX_ENEMY_DISTANCE_SQ:
				enemy.global_position = enemy._find_spawn_position()
				enemy._last_flow_dir  = Vector2.ZERO
				enemy._velocity       = Vector2.ZERO
		_teleport_index = t_end % count
	_t_teleport += Time.get_ticks_usec() - t0

	# --- AI tick ---
	_ai_accum += delta
	if _ai_accum >= AI_TICK_RATE:
		t0 = Time.get_ticks_usec()
		var ai_delta: float = _ai_accum
		_ai_accum = 0.0
		_flow_cache.clear()
		if count > 0:
			var frames_per_batch: int = maxi(1, roundi(AI_TICK_RATE / delta))
			var slice_size:       int = maxi(1, ceili(float(count) / float(frames_per_batch)))
			var start: int = (_tick_index * slice_size) % count
			var end:   int = mini(start + slice_size, count)
			_tick_index = (_tick_index + 1) % frames_per_batch
			for i in range(start, end):
				_tick_enemy(living_enemies[i], ai_delta, player_pos)
		_t_ai += Time.get_ticks_usec() - t0

	# --- Print timing every T_PRINT_EVERY frames ---
	_t_frame += 1
	if _t_frame >= T_PRINT_EVERY:
		var f: int = T_PRINT_EVERY
		print("[EnemyManager] n=%d | main_loop=%dµs | teleport=%dµs | ai=%dµs | total=%dµs (per frame avg)" % [
			count,
			_t_main_loop / f,
			_t_teleport  / f,
			_t_ai        / f,
			(_t_main_loop + _t_teleport + _t_ai) / f,
		])
		_t_frame = 0; _t_main_loop = 0; _t_teleport = 0; _t_ai = 0

func _tick_enemy(enemy: Enemy, ai_delta: float, player_pos: Vector2) -> void:
	var d_sq: float = enemy.global_position.distance_squared_to(player_pos)
	var tier_mult: float = 1.0
	if   d_sq > FAR_RADIUS_SQ:  tier_mult = FAR_TIER_MULT
	elif d_sq > NEAR_RADIUS_SQ: tier_mult = MID_TIER_MULT
	if enemy._offscreen: tier_mult *= OFFSCREEN_AI_MULT

	if enemy._offscreen and d_sq > FAR_RADIUS_SQ:
		var cell: Vector2i = _world_to_cell(enemy.global_position)
		var dir: Vector2 = _flow_cache.get(cell, Vector2.ZERO)
		if dir == Vector2.ZERO:
			if FlowField.is_ready():
				dir = FlowField.get_direction(enemy.global_position, enemy.data.collision_radius)
			if dir == Vector2.ZERO:
				dir = enemy._last_flow_dir
			if dir == Vector2.ZERO:
				dir = (player_pos - enemy.global_position).normalized()
			_flow_cache[cell] = dir
		enemy._last_flow_dir = dir
		enemy._velocity = dir * enemy.data.speed
		return

	enemy._ai_accum += ai_delta
	if enemy._ai_accum < AI_TICK_RATE * tier_mult:
		return
	enemy._ai_accum = 0.0

	enemy.tick_ai(ai_delta)
	if enemy._effects.has("stun"): return

	enemy._tick_behavior(ai_delta)
	enemy._tick_attack(ai_delta)

	enemy._stuck_timer += ai_delta
	if enemy._stuck_timer >= enemy.STUCK_TIMEOUT:
		enemy._stuck_timer = 0.0
		if enemy.global_position.distance_squared_to(enemy._stuck_pos) < enemy.STUCK_DIST_SQ:
			enemy._last_flow_dir = Vector2.ZERO
		enemy._stuck_pos = enemy.global_position

	var cell: Vector2i = _world_to_cell(enemy.global_position)
	var dir: Vector2 = _flow_cache.get(cell, Vector2.ZERO)
	if dir == Vector2.ZERO:
		if FlowField.is_ready():
			dir = FlowField.get_direction(enemy.global_position, enemy.data.collision_radius)
		if dir == Vector2.ZERO:
			dir = enemy._last_flow_dir
		if dir == Vector2.ZERO:
			dir = (player_pos - enemy.global_position).normalized()
		_flow_cache[cell] = dir

	enemy._last_flow_dir = dir
	enemy._velocity = enemy._velocity.lerp(dir * enemy.data.speed, enemy.data.turn_speed * ai_delta)

func _world_to_cell(world: Vector2) -> Vector2i:
	var ts: float = tilemap.TILE_SIZE.x
	return Vector2i(int(floor(world.x / ts)), int(floor(world.y / ts))) + Vector2i(tilemap.WIDTH / 2, tilemap.HEIGHT / 2)

func get_nearby_enemies_into(pos: Vector2, radius: float, result: Array) -> void:
	result.clear()
	var cr:     int   = int(ceil(radius / SEP_CELL)) + 1
	var origin  := Vector2i(int(floor(pos.x / SEP_CELL)), int(floor(pos.y / SEP_CELL)))
	for dx in range(-cr, cr + 1):
		for dy in range(-cr, cr + 1):
			var bucket = _sep_grid.get(origin + Vector2i(dx, dy))
			if bucket: result.append_array(bucket)

func spawn_squad(squad: Array[EnemyData], modifier: Util.Modifier) -> void:
	for d: EnemyData in squad: spawn_enemy(d, modifier)

func spawn_enemy(data: EnemyData, modifier: Util.Modifier = Util.Modifier.NONE) -> void:
	if data.scene == null:
		push_error("[EnemyManager] '%s' has no scene assigned." % data.id)
		return
	var enemy: Enemy = _acquire_pooled(data)
	if enemy == null:
		enemy         = data.scene.instantiate()
		enemy.data    = data
		enemy.tilemap = tilemap
		enemy.died.connect(_on_enemy_died)
		add_child(enemy)
		enemy.setup(AI_TICK_RATE)
	else:
		enemy.data      = data
		enemy.tilemap   = tilemap
		enemy._ai_accum = 0.0
		for child in enemy.get_children():
			if child is Node2D: child.visible = true
	enemy.initialize(player, modifier)
	living_enemies.append(enemy)

func _acquire_pooled(data: EnemyData) -> Enemy:
	if not _pool.has(data.id): return null
	var bucket: Array = _pool[data.id]
	if bucket.is_empty(): return null
	var enemy: Enemy = bucket.pop_back()
	if not is_instance_valid(enemy): return _acquire_pooled(data)
	return enemy

func _release_to_pool(enemy: Enemy) -> void:
	var script: Script = enemy.get_script()
	if script != null and script.get_global_name() != &"Enemy" and script.get_global_name() != "":
		enemy.queue_free(); return
	var id: String = enemy.data.id if enemy.data else ""
	if id == "": enemy.queue_free(); return
	var bucket: Array = _pool.get(id, [])
	_pool[id] = bucket
	if bucket.size() >= MAX_POOL_SIZE_PER_TYPE:
		enemy.queue_free(); return
	enemy.deactivate()
	bucket.append(enemy)

func register_enemy(enemy: Enemy) -> void:
	if living_enemies.has(enemy): return
	enemy.died.connect(_on_enemy_died)
	living_enemies.append(enemy)

func unregister_enemy(enemy: Enemy) -> void:
	living_enemies.erase(enemy)

func clear_all() -> void:
	for enemy: Enemy in living_enemies:
		if is_instance_valid(enemy): _release_to_pool(enemy)
	living_enemies.clear()

func on_level_changed() -> void:
	clear_all()
	for id: String in _pool:
		for enemy: Enemy in _pool[id]:
			if is_instance_valid(enemy): enemy.queue_free()
	_pool.clear()

func _on_enemy_died(enemy: Enemy) -> void:
	living_enemies.erase(enemy)
	emit_signal("enemy_died", enemy)
	_release_to_pool(enemy)
