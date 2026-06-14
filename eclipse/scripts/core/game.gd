# game.gd
extends Node2D

const FORGE_SCENE: PackedScene = preload("res://scenes/forge.tscn")

const DEBUG_MSG_DURATION: float = 3.0
var debug_messages: Array[Dictionary] = []

const FPS_DROP_THRESHOLD: int = 40
var _prev_fps: int = 0
var _frame_times: Array[float] = []

func _ready() -> void:
	ParticleManager.tilemap_manager = %TilemapManager
	EnemyManager.tilemap    = %TilemapManager
	EnemyManager.player             = %Player
	ItemManager.player              = %Player
	ItemManager.game                = self
	ItemManager.tilemap_manager     = %TilemapManager
	WaveManager.encounter_started.connect(_on_encounter_started)
	WaveManager.horde_started.connect(_on_horde_started)
	WaveManager.forging_wave_started.connect(_on_forging_wave_started)
	WaveManager.forging_wave_ended.connect(_on_forging_wave_ended)
	%TilemapManager.camera = %Camera2D
	%DebugLabel.add_theme_font_size_override(
		"normal_font_size",
		DisplayServer.window_get_size().y / 50
	)
	#NavManager.build(%TilemapManager)
	FlowField.initialize(%TilemapManager)
	_spawn_world_forges(3)

func _process(delta: float) -> void:
	FlowField.set_target(%Player.global_position)

	_process_debug_messages(delta)
	var player: CharacterBody2D = %Player
	if player == null:
		return
	var fps: int         = int(1.0 / delta)
	var env: Environment = %Environment.environment

	if _prev_fps >= FPS_DROP_THRESHOLD and fps < FPS_DROP_THRESHOLD:
		_report_drop(fps)
	_prev_fps = fps

	%DebugLabel.parse_bbcode(_build_debug_text(fps, env, player))

func _report_drop(fps: int) -> void:
	push_debug("DROP %d fps | enemies=%d" % [
		fps,
		EnemyManager.living_enemies.size(),
	], true)

func push_debug(msg: String, flash: bool = false) -> void:
	debug_messages.append({ "text": msg, "age": 0.0, "flash": flash })

func _process_debug_messages(delta: float) -> void:
	for m: Dictionary in debug_messages:
		m.age += delta
	debug_messages = debug_messages.filter(func(m: Dictionary): return m.age < DEBUG_MSG_DURATION)

func _build_debug_text(fps: int, env: Environment, player: CharacterBody2D) -> String:
	var lines: Array[String] = [
		"fps: "     + str(fps),
		"bloom: "   + str(snappedf(env.glow_bloom, 0.01)),
		"glow: "    + str(snappedf(env.glow_intensity, 0.01)),
		"enemies: " + str(EnemyManager.living_enemies.size()),
	]

	# ── ore collection counts ─────────────────────────────────────────────────
	var inventory: Node = %Player.get_node("Inventory")
	for relic: RelicData in inventory.relics:
		lines.append(relic.display_name + " x" + str(inventory.get_relic_quantity(relic)))
	for metal: MetalData in inventory.metals:
		lines.append(metal.display_name + " collected: " + str(inventory.get_metal_quantity(metal)))

	if debug_messages.size() > 0:
		lines.append("")
		for m: Dictionary in debug_messages:
			if m.flash:
				var f:   float  = m.age * 8.0
				var r:   float  = 1.0
				var g:   float  = 0.5 + 0.5 * sin(f)
				var b:   float  = 0.5 + 0.5 * sin(f + PI)
				var hex: String = Color(r, g, b).to_html(false)
				lines.append("[color=#" + hex + "]>> " + m.text + "[/color]")
			else:
				lines.append(">> " + m.text)

	return "\n".join(lines)

func _on_encounter_started(type: WaveManager.Encounter) -> void:
	push_debug("ENCOUNTER — " + WaveManager.Encounter.keys()[type], true)

func _on_horde_started() -> void:
	push_debug("HORDE incoming!", true)

func _on_forging_wave_started() -> void:
	push_debug("Forging wave — enemies alerted", false)

func _on_forging_wave_ended() -> void:
	push_debug("Forging wave ended", false)

# ══════════════════════════════════════════════════════════ forge spawning ══

# Tile offsets (relative to the anchor tile) that the forge's collision
# polygon covers, pre-computed from forge.tscn.
# StaticBody2D offset: (0, -14). TILE_SIZE = 32.
# Recompute if the polygon or pivot changes.
# Computed by testing all 4 tile corners + centre + polygon vertices against
# the CollisionPolygon2D (StaticBody2D offset (0,-14), TILE_SIZE=32).
const FORGE_POLYGON_TILE_OFFSETS: Array[Vector2i] = [
	# y = -2
	Vector2i(-1, -2), Vector2i( 0, -2), Vector2i( 1, -2),
	# y = -1
	Vector2i(-5, -1), Vector2i(-4, -1), Vector2i(-3, -1), Vector2i(-2, -1),
	Vector2i(-1, -1), Vector2i( 0, -1), Vector2i( 1, -1), Vector2i( 2, -1),
	Vector2i( 3, -1), Vector2i( 4, -1),
	# y =  0
	Vector2i(-5,  0), Vector2i(-4,  0), Vector2i(-3,  0), Vector2i(-2,  0),
	Vector2i(-1,  0), Vector2i( 0,  0), Vector2i( 1,  0), Vector2i( 2,  0),
	Vector2i( 3,  0), Vector2i( 4,  0),
	# y =  1
	Vector2i(-4,  1), Vector2i(-3,  1), Vector2i(-2,  1), Vector2i(-1,  1),
	Vector2i( 0,  1), Vector2i( 1,  1), Vector2i( 2,  1), Vector2i( 3,  1),
	# y =  2
	Vector2i(-2,  2), Vector2i(-1,  2),
]

func _spawn_world_forges(count: int, candidates_per_forge: int = 200) -> void:
	var tilemap: Node = %TilemapManager
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var cx: int            = tilemap.WIDTH  / 2
	var cy: int            = tilemap.HEIGHT / 2
	var play_radius: float = (tilemap.WIDTH - tilemap.BUFFER_TILES) / 2.0 - 4.0

	var placed_positions: Array[Vector2] = []

	for _forge_i in count:
		var best_tile: Vector2i = Vector2i(-1, -1)
		var best_score: float   = -1.0

		for _i in candidates_per_forge:
			var angle: float        = rng.randf() * TAU
			var dist:  float        = rng.randf_range(2.0, play_radius)
			var candidate: Vector2i = Vector2i(
				cx + int(cos(angle) * dist),
				cy + int(sin(angle) * dist)
			)

			# Every polygon tile must be inside the world and air
			var clear := true
			for offset: Vector2i in FORGE_POLYGON_TILE_OFFSETS:
				var check: Vector2i = candidate + offset
				if not tilemap.ground_types.has(check) or not tilemap.is_air(check):
					clear = false
					break
			if not clear:
				continue

			var world_pos: Vector2 = tilemap.map_to_world(candidate)
			var min_dist: float    = INF
			for placed: Vector2 in placed_positions:
				min_dist = minf(min_dist, world_pos.distance_to(placed))
			if placed_positions.is_empty():
				min_dist = 0.0

			if min_dist > best_score:
				best_score = min_dist
				best_tile  = candidate

		if best_tile == Vector2i(-1, -1):
			push_warning("spawn_forge: could not find a clear air location for forge %d" % _forge_i)
			continue

		var forge: Forge = FORGE_SCENE.instantiate()
		add_child(forge)
		forge.global_position = tilemap.map_to_world(best_tile)
		forge.init(%Player)
		placed_positions.append(forge.global_position)

# Spawns a single forge as far as possible from existing Forge nodes.
# Returns the new Forge or null on failure.
func spawn_forge(max_attempts: int = 200) -> Forge:
	var tilemap: Node = %TilemapManager

	var placed_positions: Array[Vector2] = []
	for node in get_children():
		if node is Forge:
			placed_positions.append(node.global_position)

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var cx: int            = tilemap.WIDTH  / 2
	var cy: int            = tilemap.HEIGHT / 2
	var play_radius: float = (tilemap.WIDTH - tilemap.BUFFER_TILES) / 2.0 - 4.0

	var best_tile: Vector2i = Vector2i(-1, -1)
	var best_score: float   = -1.0

	for _i in max_attempts:
		var angle: float        = rng.randf() * TAU
		var dist:  float        = rng.randf_range(2.0, play_radius)
		var candidate: Vector2i = Vector2i(
			cx + int(cos(angle) * dist),
			cy + int(sin(angle) * dist)
		)

		var clear := true
		for offset: Vector2i in FORGE_POLYGON_TILE_OFFSETS:
			var check: Vector2i = candidate + offset
			if not tilemap.ground_types.has(check) or not tilemap.is_air(check):
				clear = false
				break
		if not clear:
			continue

		var world_pos: Vector2 = tilemap.map_to_world(candidate)
		var min_dist: float    = INF
		for placed: Vector2 in placed_positions:
			min_dist = minf(min_dist, world_pos.distance_to(placed))
		if placed_positions.is_empty():
			min_dist = 0.0

		if min_dist > best_score:
			best_score = min_dist
			best_tile  = candidate

	if best_tile == Vector2i(-1, -1):
		push_warning("spawn_forge: could not find a clear air location after %d attempts" % max_attempts)
		return null

	var forge: Forge = FORGE_SCENE.instantiate()
	add_child(forge)
	forge.global_position = tilemap.map_to_world(best_tile)
	forge.init(%Player)
	return forge
