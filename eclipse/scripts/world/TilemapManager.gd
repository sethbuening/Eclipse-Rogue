extends Node

var map_seed: int
var camera: Camera2D = null

# ══════════════════════════════════════════════════════════ exports ══
@export_group("Proc Gen Parameters")
@export_subgroup("Map Sizing")
@export_multiline var note: String = "WIDTH and HEIGHT must be divisible by 16 since CHUNK_SIZE is WIDTH/16"
@export var WIDTH:                int      = 256 + 32
@export var HEIGHT:               int      = 256 + 32
@warning_ignore("integer_division")
@export var CHUNK_SIZE:           int      = WIDTH / 16
@export var TILE_SIZE:            Vector2i = Vector2i(32, 32)
@export var STARTING_AREA_RADIUS: float    = 3 * sqrt(2)

@export_subgroup("Air Generation Perlin Values")
@export var PERLIN_CHAMBER_THRESHOLD: float = 0.20
@export var PERLIN_CHAMBER_FREQUENCY: float = 0.04
@export var PERLIN_PATH_THRESHOLD:    float = 0.06
@export var PERLIN_PATH_FREQUENCY:    float = 0.01

@export_subgroup("Air Edge Smoothing")
@export var CELL_DEATH_THRESHOLD: int = 4
@export var CELL_BIRTH_THRESHOLD: int = 4

@export_subgroup("Gold Generation")
@export var CHUNK_CHANCE:     float = 0.25
@export var ADD_POINT_CHANCE: float = 0.035

@export_subgroup("Copper Generation")
@export var COPPER_CHANCE:     float = 0.1
@export var COPPER_ADD_CHANCE: float = 0.015
@export var COPPER_MIN_RADIUS: int   = 3
@export var COPPER_MAX_RADIUS: int   = 5

@export_subgroup("Relic Generation")
@export var relic_count: Vector2i = Vector2i(12, 15)
@onready var AncientContainerScene: PackedScene = preload("res://scenes/ancient_container.tscn")

@export_subgroup("Rock Variation")
@export var ROCK_VARIATION_THRESHOLD: float = 0.01
@export var ROCK_VARIATION_FREQUENCY: float = 0.025

@export var BUFFER_TILES: int = 32

@export_group("Rendering")
@export var tile_atlas:   Texture2D
@export var ore_atlas:    Texture2D
@export var relic_atlas:  Texture2D
@export var ground_atlas: Texture2D
@export var ATLAS_TILE_SIZE: Vector2i = Vector2i(32, 48)
var SPRITE_OFFSET_Y: float = 0

@export_subgroup("Wall Atlas Rows")
@export var atlas_row_stone:        int = 0
@export var atlas_variants_stone:   int = 2
@export var atlas_row_rock:         int = 2
@export var atlas_variants_rock:    int = 2
@export var atlas_row_crystal:      int = 4
@export var atlas_variants_crystal: int = 1

@export_subgroup("Ore Atlas Rows")
@export var ore_row_gold:        int = 0
@export var ore_variants_gold:   int = 1
@export var ore_row_copper:      int = 1
@export var ore_variants_copper: int = 1

@export_subgroup("Relic Atlas Rows")
@export var relic_atlas_row: int = 0

@export_subgroup("Ground Atlas Rows")
@export var ground_atlas_row_floor: int = 0
@export var ground_atlas_row_dirt:  int = 1

# ══════════════════════════════════════════════════════════ tile data ══
var tile_types:   Dictionary = {}   # Vector2i → Util.tile
var ore_types:    Dictionary = {}   # Vector2i → Util.tile
var tile_health:  Dictionary = {}   # Vector2i → int
var tile_shapes:  Dictionary = {}   # Vector2i → CollisionShape2D
var tile_variant: Dictionary = {}   # Vector2i → int
var ore_variant:  Dictionary = {}   # Vector2i → int
var ground_types: Dictionary = {}   # Vector2i → int (ground_atlas_row_*)

# ══════════════════════════════════════════════════════════ relic data ══
var relic_tiles:         Dictionary = {}
var _relic_cover_counts: Dictionary = {}
var _relic_containers:   Dictionary = {}

# ══════════════════════════════════════════════════════════ noise ══
var chamber_noise:        FastNoiseLite   = FastNoiseLite.new()
var path_noise:           FastNoiseLite   = FastNoiseLite.new()
var rock_variation_noise: FastNoiseLite   = FastNoiseLite.new()
var rock_variation_tiles: Array[Vector2i] = []

# ══════════════════════════════════════════════════ bounce anim ══
class BounceState:
	var start_time: float
	var amplitude:  float
	var delay:      float

var _tile_bounces: Dictionary[Vector2i, BounceState] = {}

# ══════════════════════════════════════════════════════════ rendering ══
var static_body: StaticBody2D

class OverlayLayer:
	var multimesh:   MultiMesh           = null
	var instance:    MultiMeshInstance2D = null
	var index:       Dictionary          = {}
	var occluders:   Dictionary          = {}
	var atlas:       Texture2D           = null
	var z_offset:    int                 = 0
	var has_data:    Callable
	var get_uv_rect: Callable
	var get_uv:      Callable

var _wall_layer:   OverlayLayer
var _ore_layer:    OverlayLayer
var _relic_layer:  OverlayLayer
var _ground_layer: OverlayLayer

# ══════════════════════════════════════════════════════════ distance field ══
var _df_texture:      ImageTexture    = ImageTexture.new()
var _df_thread:       Thread          = Thread.new()
var _df_pending:      Image           = null
var _df_pending_rect: Rect2i          = Rect2i()
var _df_dirty_chunks: Array[Vector2i] = []
var _df_running:      bool            = false
var _df_image:        Image           = null

const DF_CHUNK_SIZE: int   = 16
const DF_MAX_DEPTH:  float = 5.0

# ══════════════════════════════════════════════════════ ready / gen ══
func _ready() -> void:
	SPRITE_OFFSET_Y = (ATLAS_TILE_SIZE.y - TILE_SIZE.y) / 2.0
	map_seed        = randi()

	_setup_noise(chamber_noise,        PERLIN_CHAMBER_FREQUENCY)
	_setup_noise(path_noise,           PERLIN_PATH_FREQUENCY)
	_setup_noise(rock_variation_noise, ROCK_VARIATION_FREQUENCY)

	var play_radius: float = (WIDTH - BUFFER_TILES) / 2.0
	var cx: float = WIDTH  / 2.0
	var cy: float = HEIGHT / 2.0

	var t_start: int = Time.get_ticks_usec()
	var t:       int = t_start

	# ── Pass 1: fill + rock variation + chamber noise + path noise ──────
	var grid: Array[Array] = []
	for x in range(WIDTH):
		grid.append([])
		for y in range(HEIGHT):
			var tile: Util.tile = Util.tile.STONE
			var dist:   float = sqrt((x - cx) ** 2 + (y - cy) ** 2)
			var dist_n: float = dist / play_radius
			var rock_bonus: float = 0.0
			if dist >= WIDTH / 2.0:
				rock_bonus = (1.0 - ROCK_VARIATION_THRESHOLD) * dist_n
			if rock_variation_noise.get_noise_2d(x, y) > (ROCK_VARIATION_THRESHOLD + rock_bonus):
				tile = Util.tile.ROCK
				rock_variation_tiles.append(Vector2i(x, y))
			var chamber_bonus: float = 0.0
			if dist > (WIDTH - BUFFER_TILES) / 3.0:
				chamber_bonus = (1.0 - PERLIN_CHAMBER_THRESHOLD) * dist_n
			if chamber_noise.get_noise_2d(x, y) > (PERLIN_CHAMBER_THRESHOLD + chamber_bonus) and is_replaceable(tile):
				tile = Util.tile.AIR
			var path_bonus: float = 0.0
			if dist > 2.0 * (WIDTH - BUFFER_TILES) / 5.0:
				path_bonus = PERLIN_PATH_THRESHOLD * dist_n
			if absf(path_noise.get_noise_2d(x, y)) < (PERLIN_PATH_THRESHOLD - path_bonus) and is_replaceable(tile):
				tile = Util.tile.AIR
			grid[x].append(tile)

	var t_pass1: int = Time.get_ticks_usec()
	print("Pass 1 (fill+rock+chamber+path noise): %.2f ms" % [(t_pass1 - t) / 1000.0]); t = t_pass1

	generate_ores(grid)
	var t_ores: int = Time.get_ticks_usec()
	print("generate_ores:                         %.2f ms" % [(t_ores - t) / 1000.0]); t = t_ores

	grid = generate_faults(grid)
	var t_faults: int = Time.get_ticks_usec()
	print("generate_faults:                       %.2f ms" % [(t_faults - t) / 1000.0]); t = t_faults

	for i in range(4):
		var t_step_start: int = Time.get_ticks_usec()
		grid = cellular_step(grid)
		print("  cellular_step[%d]:                  %.2f ms" % [i, (Time.get_ticks_usec() - t_step_start) / 1000.0])
	var t_cellular: int = Time.get_ticks_usec()
	print("cellular_step x4 (total):              %.2f ms" % [(t_cellular - t) / 1000.0]); t = t_cellular

	place_starting_area(grid)
	var t_start_area: int = Time.get_ticks_usec()
	print("place_starting_area:                   %.2f ms" % [(t_start_area - t) / 1000.0]); t = t_start_area

	_place_relic_tiles_on_grid(grid)
	var t_relics: int = Time.get_ticks_usec()
	print("_place_relic_tiles_on_grid:            %.2f ms" % [(t_relics - t) / 1000.0]); t = t_relics

	# ── Pass 2: populate tile dictionaries ───────────────────────────────
	for x in range(WIDTH):
		for y in range(HEIGHT):
			var dist: float = sqrt((x - cx) ** 2 + (y - cy) ** 2)
			if dist >= play_radius:
				continue
			var pos: Vector2i = Vector2i(x, y)
			var tile_val: Util.tile = grid[x][y]
			if tile_val == null or tile_val == Util.tile.AIR:
				ground_types[pos] = ground_atlas_row_floor
				continue
			if _is_ore(tile_val):
				ore_types[pos]   = tile_val
				tile_types[pos]  = Util.tile.STONE
				ore_variant[pos] = randi() % _ore_variant_count(tile_val)
			else:
				tile_types[pos] = tile_val
			tile_health[pos]  = get_tile_max_health(tile_val)
			tile_variant[pos] = randi() % _base_variant_count(tile_val)
			ground_types[pos] = ground_atlas_row_dirt

	var t_pass2: int = Time.get_ticks_usec()
	print("Pass 2 (populate dictionaries):        %.2f ms" % [(t_pass2 - t) / 1000.0]); t = t_pass2

	for pos in relic_tiles.keys():
		if not tile_types.has(pos):
			relic_tiles.erase(pos)
			_relic_cover_counts.erase(pos)

	var t_relic_valid: int = Time.get_ticks_usec()
	print("relic validation:                      %.2f ms" % [(t_relic_valid - t) / 1000.0]); t = t_relic_valid

	_setup_rendering()
	var t_render: int = Time.get_ticks_usec()
	print("_setup_rendering:                      %.2f ms" % [(t_render - t) / 1000.0]); t = t_render

	_initial_df_bake()
	var t_df: int = Time.get_ticks_usec()
	print("_initial_df_bake:                      %.2f ms" % [(t_df - t) / 1000.0]); t = t_df

	_build_collision()
	var t_col: int = Time.get_ticks_usec()
	print("_build_collision:                      %.2f ms" % [(t_col - t) / 1000.0]); t = t_col

	_setup_occluders()
	var t_occ: int = Time.get_ticks_usec()
	print("_setup_occluders:                      %.2f ms" % [(t_occ - t) / 1000.0]); t = t_occ

	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print("TOTAL generation time:                 %.2f ms" % [(t_occ - t_start) / 1000.0])

	_spawn_relic_containers.call_deferred()

func _process(_delta: float) -> void:
	_update_tile_bounces()
	if _df_pending != null and not _df_thread.is_alive():
		_df_thread.wait_to_finish()
		_df_image.blit_rect(_df_pending, Rect2i(Vector2i.ZERO, _df_pending_rect.size), _df_pending_rect.position)
		_df_pending      = null
		_df_pending_rect = Rect2i()
		_df_running      = false
		if not _df_dirty_chunks.is_empty():
			_request_df_update()
		else:
			_df_texture.update(_df_image)

# ══════════════════════════════════════════════════════════ noise ══
func _setup_noise(noise: FastNoiseLite, frequency: float) -> void:
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed       = map_seed
	noise.frequency  = frequency

# ══════════════════════════════════════════════════════════ coordinate utils ══
func world_to_map(world_pos: Vector2) -> Vector2i:
	var local: Vector2 = world_pos / get_parent().scale
	@warning_ignore("integer_division")
	return Vector2i((local / Vector2(TILE_SIZE)).floor()) + Vector2i(WIDTH / 2, HEIGHT / 2)

func map_to_world(pos: Vector2i) -> Vector2:
	@warning_ignore("integer_division")
	var local: Vector2 = Vector2((pos - Vector2i(WIDTH / 2, HEIGHT / 2)) * TILE_SIZE) + Vector2(TILE_SIZE) / 2.0
	return local * get_parent().scale

# Returns the multimesh draw origin (unscaled, atlas-offset baked in — quad center).
func _world_origin(pos: Vector2i) -> Vector2:
	@warning_ignore("integer_division")
	var local: Vector2 = Vector2((pos - Vector2i(WIDTH / 2, HEIGHT / 2)) * TILE_SIZE) + Vector2(TILE_SIZE) / 2.0
	local.y -= SPRITE_OFFSET_Y
	return local

# Returns the top-left corner of the atlas sprite in Sprite2D position space (scaled).
func _sprite_top_left(pos: Vector2i) -> Vector2:
	var origin: Vector2 = _world_origin(pos) * get_parent().scale
	origin.x -= TILE_SIZE.x      / 2.0 * get_parent().scale.x
	origin.y -= ATLAS_TILE_SIZE.y / 2.0 * get_parent().scale.y
	return origin

func in_bounds(loc: Vector2i) -> bool:
	return loc.x >= 0 and loc.x < WIDTH and loc.y >= 0 and loc.y < HEIGHT

func tile_exists(pos: Vector2i) -> bool:
	return tile_types.has(pos)

func is_air(pos: Vector2i) -> bool:
	return not tile_types.has(pos)

# ══════════════════════════════════════════════════════════ tile queries ══
func get_tile_max_health(t: Util.tile) -> int:
	return 12  # all tile types share the same health for now

func get_tile_uv(t: Util.tile) -> Rect2:
	return _uv_for(0, _wall_row_for(t), tile_atlas)

func get_tile_color(pos: Vector2i) -> Color:
	if not _wall_layer.index.has(pos):
		return Color.WHITE
	return _wall_layer.multimesh.get_instance_color(_wall_layer.index[pos])

func get_z_for(world_pos: Vector2) -> int:
	var tile_row:    int   = world_to_map(world_pos).y
	var tile_top:    float = map_to_world(Vector2i(0, tile_row)).y - TILE_SIZE.y / 2.0
	var within_tile: int   = int((world_pos.y - tile_top) / float(TILE_SIZE.y) * 8.0)
	return clampi(tile_row * 10 + clampi(within_tile, 0, 9), -4096, 4096)

func is_replaceable(t: Variant) -> bool:
	return t != null and t != Util.tile.AIR and t != Util.tile.CRYSTAL and t != Util.tile.COPPER

func _is_ore(t: Util.tile) -> bool:
	return t == Util.tile.GOLD or t == Util.tile.COPPER

# ══════════════════════════════════════════════════════════ atlas helpers ══
func _wall_row_for(t: Util.tile) -> int:
	match t:
		Util.tile.STONE:   return atlas_row_stone
		Util.tile.ROCK:    return atlas_row_rock
		Util.tile.CRYSTAL: return atlas_row_crystal
		_:                 return atlas_row_stone

func _base_variant_count(t: Util.tile) -> int:
	match t:
		Util.tile.STONE:   return atlas_variants_stone
		Util.tile.ROCK:    return atlas_variants_rock
		Util.tile.CRYSTAL: return atlas_variants_crystal
		_:                 return 1

func _ore_row_for(t: Util.tile) -> int:
	match t:
		Util.tile.GOLD:   return ore_row_gold
		Util.tile.COPPER: return ore_row_copper
		_:                return 0

func _ore_variant_count(t: Util.tile) -> int:
	match t:
		Util.tile.GOLD:   return ore_variants_gold
		Util.tile.COPPER: return ore_variants_copper
		_:                return 1

# ══════════════════════════════════════════════════════════ bitmask ══
func _bitmask_for(pos: Vector2i, predicate: Callable) -> int:
	var mask: int = 0
	if predicate.call(pos + Vector2i( 0, -1)): mask |= 1
	if predicate.call(pos + Vector2i( 1,  0)): mask |= 2
	if predicate.call(pos + Vector2i( 0,  1)): mask |= 4
	if predicate.call(pos + Vector2i(-1,  0)): mask |= 8
	return mask

func _get_bitmask(pos: Vector2i) -> int:
	return _bitmask_for(pos, func(nb: Vector2i) -> bool: return not is_air(nb))

func _get_ground_bitmask(pos: Vector2i) -> int:
	return _bitmask_for(pos, func(nb: Vector2i) -> bool:
		return ground_types.get(nb, ground_atlas_row_floor) == ground_atlas_row_dirt)

# ══════════════════════════════════════════════════════════ UV helpers ══
func _uv_for(col: int, row: int, atlas: Texture2D) -> Rect2:
	var atlas_px:  Vector2 = Vector2(atlas.get_size()) if atlas else Vector2(512.0, 192.0)
	var uv_origin: Vector2 = Vector2(col * ATLAS_TILE_SIZE.x, row * ATLAS_TILE_SIZE.y) / atlas_px
	var uv_size:   Vector2 = Vector2(ATLAS_TILE_SIZE) / atlas_px
	return Rect2(uv_origin, uv_size)

func _wall_atlas_uv(pos: Vector2i) -> Rect2:
	if not tile_types.has(pos) or not tile_variant.has(pos):
		return Rect2()
	return _uv_for(_get_bitmask(pos), _wall_row_for(tile_types[pos]) + tile_variant[pos], tile_atlas)

func _ore_atlas_uv(pos: Vector2i) -> Rect2:
	return _uv_for(_get_bitmask(pos), _ore_row_for(ore_types[pos]) + ore_variant[pos], ore_atlas)

func _relic_atlas_uv(pos: Vector2i) -> Rect2:
	return _uv_for(_get_bitmask(pos), relic_atlas_row, relic_atlas)

func _ground_atlas_uv(pos: Vector2i) -> Rect2:
	var is_dirt: bool = ground_types.get(pos, 0) == ground_atlas_row_dirt
	var row: int = ground_atlas_row_dirt if is_dirt else ground_atlas_row_floor
	var col: int = _get_ground_bitmask(pos) if is_dirt else 0
	return _uv_for(col, row, ground_atlas)

# ══════════════════════════════════════════════════════════ rendering ══
func _make_quad_mesh() -> QuadMesh:
	var quad := QuadMesh.new()
	@warning_ignore("integer_division")
	quad.size = Vector2(TILE_SIZE) + Vector2(0, TILE_SIZE.y / 2)
	return quad

func _make_multimesh(count: int) -> MultiMesh:
	var mm             := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors       = true
	mm.use_custom_data  = true
	mm.mesh             = _make_quad_mesh()
	mm.instance_count   = count
	return mm

func _make_multimesh_instance(mm: MultiMesh, atlas: Texture2D, z: int) -> MultiMeshInstance2D:
	var inst          := MultiMeshInstance2D.new()
	inst.scale         = get_parent().scale
	inst.multimesh     = mm
	inst.texture       = atlas
	inst.z_index       = z
	inst.z_as_relative = false
	var mat           := ShaderMaterial.new()
	mat.shader         = preload("res://scripts/world/MultiMesh.gdshader")
	mat.set_shader_parameter("atlas",       atlas)
	mat.set_shader_parameter("sprite_size", Vector2(ATLAS_TILE_SIZE))
	inst.material      = mat
	return inst

func _setup_rendering() -> void:
	static_body                 = StaticBody2D.new()
	static_body.collision_layer = 1
	static_body.collision_mask  = 0
	static_body.scale           = get_parent().scale
	add_child(static_body)

	# ── ground layer ──────────────────────────────────────────────────
	_ground_layer             = OverlayLayer.new()
	_ground_layer.atlas       = ground_atlas
	_ground_layer.z_offset    = -1
	_ground_layer.has_data    = func(pos: Vector2i) -> bool: return ground_types.has(pos)
	_ground_layer.get_uv      = func(pos: Vector2i) -> Rect2: return _ground_atlas_uv(pos)
	_ground_layer.get_uv_rect = func(pos: Vector2i) -> Rect2:
		var row: int = ground_types.get(pos, ground_atlas_row_floor)
		var col: int = _get_ground_bitmask(pos) if row == ground_atlas_row_dirt else 0
		return Rect2(Vector2(col * ATLAS_TILE_SIZE.x, row * ATLAS_TILE_SIZE.y), Vector2(ATLAS_TILE_SIZE))

	if ground_atlas != null and not ground_types.is_empty():
		_ground_layer.multimesh = _make_multimesh(ground_types.size())
		_ground_layer.instance  = _make_multimesh_instance(_ground_layer.multimesh, ground_atlas, -4096)
		_ground_layer.instance.material.set_shader_parameter("darkness_power", 0.0)
		add_child(_ground_layer.instance)
		var sorted_ground: Array = ground_types.keys()
		sorted_ground.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y)
		for i in sorted_ground.size():
			_ground_layer.index[sorted_ground[i]] = i
			_write_ground_instance(i, sorted_ground[i])

	# ── walls ─────────────────────────────────────────────────────────
	_wall_layer             = OverlayLayer.new()
	_wall_layer.atlas       = tile_atlas
	_wall_layer.z_offset    = 0
	_wall_layer.has_data    = func(pos: Vector2i) -> bool: return tile_types.has(pos)
	_wall_layer.get_uv      = func(pos: Vector2i) -> Rect2: return _wall_atlas_uv(pos)
	_wall_layer.get_uv_rect = func(pos: Vector2i) -> Rect2:
		if not tile_types.has(pos) or not tile_variant.has(pos): return Rect2()
		var row: int = _wall_row_for(tile_types[pos]) + tile_variant[pos]
		return Rect2(Vector2(_get_bitmask(pos) * ATLAS_TILE_SIZE.x, row * ATLAS_TILE_SIZE.y), Vector2(ATLAS_TILE_SIZE))

	_wall_layer.multimesh = _make_multimesh(tile_types.size())
	_wall_layer.instance  = _make_multimesh_instance(_wall_layer.multimesh, tile_atlas, -1)
	add_child(_wall_layer.instance)
	var sorted_walls: Array = tile_types.keys()
	sorted_walls.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y)
	for i in sorted_walls.size():
		_wall_layer.index[sorted_walls[i]] = i
		_write_layer_instance(_wall_layer, i, sorted_walls[i])

	# ── ore overlay ───────────────────────────────────────────────────
	_ore_layer             = OverlayLayer.new()
	_ore_layer.atlas       = ore_atlas
	_ore_layer.z_offset    = 1
	_ore_layer.has_data    = func(pos: Vector2i) -> bool: return ore_types.has(pos)
	_ore_layer.get_uv      = func(pos: Vector2i) -> Rect2: return _ore_atlas_uv(pos)
	_ore_layer.get_uv_rect = func(pos: Vector2i) -> Rect2:
		if not ore_types.has(pos) or not ore_variant.has(pos): return Rect2()
		var row: int = _ore_row_for(ore_types[pos]) + ore_variant[pos]
		return Rect2(Vector2(_get_bitmask(pos) * ATLAS_TILE_SIZE.x, row * ATLAS_TILE_SIZE.y), Vector2(ATLAS_TILE_SIZE))

	_ore_layer.multimesh = _make_multimesh(ore_types.size())
	_ore_layer.instance  = _make_multimesh_instance(_ore_layer.multimesh, ore_atlas, -1)
	add_child(_ore_layer.instance)
	var sorted_ores: Array = ore_types.keys()
	sorted_ores.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y)
	for i in sorted_ores.size():
		_ore_layer.index[sorted_ores[i]] = i
		_write_layer_instance(_ore_layer, i, sorted_ores[i])

	# ── relic overlay ─────────────────────────────────────────────────
	_relic_layer             = OverlayLayer.new()
	_relic_layer.atlas       = relic_atlas
	_relic_layer.z_offset    = 2
	_relic_layer.has_data    = func(pos: Vector2i) -> bool: return relic_tiles.has(pos)
	_relic_layer.get_uv      = func(pos: Vector2i) -> Rect2: return _relic_atlas_uv(pos)
	_relic_layer.get_uv_rect = func(pos: Vector2i) -> Rect2:
		if not relic_tiles.has(pos): return Rect2()
		return Rect2(Vector2(_get_bitmask(pos) * ATLAS_TILE_SIZE.x, relic_atlas_row * ATLAS_TILE_SIZE.y), Vector2(ATLAS_TILE_SIZE))

	if relic_atlas != null and not relic_tiles.is_empty():
		_relic_layer.multimesh = _make_multimesh(relic_tiles.size())
		_relic_layer.instance  = _make_multimesh_instance(_relic_layer.multimesh, relic_atlas, -1)
		add_child(_relic_layer.instance)
		var sorted_relics: Array = relic_tiles.keys()
		sorted_relics.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y)
		for i in sorted_relics.size():
			_relic_layer.index[sorted_relics[i]] = i
			_write_layer_instance(_relic_layer, i, sorted_relics[i])

# ── multimesh write / hide helpers ────────────────────────────────────
func _write_layer_instance(layer: OverlayLayer, idx: int, pos: Vector2i) -> void:
	var t := Transform2D.IDENTITY
	t.origin = _world_origin(pos)
	layer.multimesh.set_instance_transform_2d(idx, t)
	layer.multimesh.set_instance_color(idx, Color.WHITE)
	var uv: Rect2 = layer.get_uv.call(pos)
	layer.multimesh.set_instance_custom_data(idx, Color(uv.position.x, uv.position.y, uv.size.x, uv.size.y))

func _write_ground_instance(idx: int, pos: Vector2i) -> void:
	var t := Transform2D.IDENTITY
	t.origin = _world_origin(pos) + Vector2(0, 16)
	_ground_layer.multimesh.set_instance_transform_2d(idx, t)
	_ground_layer.multimesh.set_instance_color(idx, Color.WHITE)
	var uv: Rect2 = _ground_atlas_uv(pos)
	_ground_layer.multimesh.set_instance_custom_data(idx, Color(uv.position.x, uv.position.y, uv.size.x, uv.size.y))

func _hide_layer_instance(layer: OverlayLayer, pos: Vector2i) -> void:
	if not layer.index.has(pos) or layer.multimesh == null:
		return
	var t := Transform2D.IDENTITY
	t.origin = Vector2(-999999, -999999)
	layer.multimesh.set_instance_transform_2d(layer.index[pos], t)

func _hide_wall_instance(pos: Vector2i)  -> void: _hide_layer_instance(_wall_layer,  pos)
func _hide_ore_instance(pos: Vector2i)   -> void: _hide_layer_instance(_ore_layer,   pos)
func _hide_relic_instance(pos: Vector2i) -> void: _hide_layer_instance(_relic_layer, pos)

func _redraw_neighbors(pos: Vector2i) -> void:
	for nb: Vector2i in [pos + Vector2i(0,-1), pos + Vector2i(1,0), pos + Vector2i(0,1), pos + Vector2i(-1,0)]:
		if _ground_layer.index.has(nb):
			_write_ground_instance(_ground_layer.index[nb], nb)
		if not tile_types.has(nb):
			continue
		for layer: OverlayLayer in [_wall_layer, _ore_layer, _relic_layer]:
			if layer.index.has(nb) and not layer.occluders.has(nb):
				_write_layer_instance(layer, layer.index[nb], nb)
			if layer.occluders.has(nb):
				var full_px: Rect2 = layer.get_uv_rect.call(nb)
				layer.occluders[nb].region_rect = Rect2(full_px.position, Vector2(full_px.size.x, _get_occluder_clip_height(nb)))

# ── color helpers ─────────────────────────────────────────────────────
func set_tile_color(pos: Vector2i, color: Color) -> void:
	if _wall_layer.index.has(pos):
		_wall_layer.multimesh.set_instance_color(_wall_layer.index[pos], color)
	if _ore_layer.index.has(pos):
		_ore_layer.multimesh.set_instance_color(_ore_layer.index[pos], color)
	var side_color := Color(
		(color.r - 1.0) * 0.38 + 1.0,
		(color.g - 1.0) * 0.38 + 1.0,
		(color.b - 1.0) * 0.38 + 1.0
	)
	for layer: OverlayLayer in [_wall_layer, _ore_layer, _relic_layer]:
		if layer.occluders.has(pos):
			layer.occluders[pos].modulate = side_color

# ══════════════════════════════════════════════════════════ occluders ══

# Returns the correct region_rect height (in atlas pixels) for an occluder
# sprite at pos, accounting for both its own bounce and the tile below's bounce.
func _get_occluder_clip_height(pos: Vector2i) -> float:
	var below: Vector2i = pos + Vector2i(0, 1)
	var above: Vector2i = pos + Vector2i(0, -1)
	var scale_y: float = get_parent().scale.y

	var sprite_top: float = _sprite_top_left(pos).y

	# Default = fully visible atlas sprite
	var clip_y_screen: float = sprite_top + float(ATLAS_TILE_SIZE.y) * scale_y

	# If the tile has air both above and below, clip it exactly 
	# at its logical layout tile boundary so texture bleed doesn't hang in mid-air.
	if is_air(above) and is_air(below):
		clip_y_screen = sprite_top + float(ATLAS_TILE_SIZE.y) * scale_y
	# Otherwise, if there is a tile below, clip against its shifting top edge
	elif tile_types.has(below):
		var current_bounce: float = _get_bounce_offset(pos)
		var below_bounce: float = _get_bounce_offset(below)
		var below_top: float = _sprite_top_left(below).y

		clip_y_screen = below_top - current_bounce + below_bounce

	return clampf(
		(clip_y_screen - sprite_top) / scale_y,
		0.0,
		float(ATLAS_TILE_SIZE.y)
	)

func _recalculate_full_occluder(pos: Vector2i) -> void:
	for layer: OverlayLayer in [_wall_layer, _ore_layer, _relic_layer]:
		if not layer.occluders.has(pos):
			continue

		var sprite: Sprite2D = layer.occluders[pos]

		# Recompute base UV fully (not cached / not partial)
		var full_rect: Rect2 = layer.get_uv_rect.call(pos)

		# Recompute clipping based on CURRENT world + bounce
		var h: float = _get_occluder_clip_height(pos)

		sprite.region_rect = Rect2(
			full_rect.position,
			Vector2(full_rect.size.x, h)
		)

		# Also ensure correct world position after bounce
		sprite.position = _sprite_top_left(pos) + Vector2(0, _get_bounce_offset(pos))

func _apply_occluder_clip(pos: Vector2i) -> void:
	var h: float = _get_occluder_clip_height(pos)
	for layer: OverlayLayer in [_wall_layer, _ore_layer, _relic_layer]:
		if not layer.occluders.has(pos):
			continue
		var full_px: Rect2 = layer.get_uv_rect.call(pos)
		layer.occluders[pos].region_rect = Rect2(full_px.position, Vector2(full_px.size.x, h))

func _setup_occluders() -> void:
	for pos: Vector2i in tile_types.keys():
		if is_air(pos + Vector2i(0, -1)):
			_add_occluder_sprite(pos)

func _add_occluder_sprite(pos: Vector2i) -> void:
	if _wall_layer.occluders.has(pos):
		return
	_hide_wall_instance(pos)
	_hide_ore_instance(pos)
	_hide_relic_instance(pos)

	var sprite_pos: Vector2 = _sprite_top_left(pos)

	var _make_sprite: Callable = func(atlas: Texture2D, rect: Rect2, z_off: int) -> Sprite2D:
		var s            := Sprite2D.new()
		s.texture        = atlas
		s.region_enabled = true
		s.region_rect    = rect  # full rect; clip applied after deferred add
		s.centered       = false
		s.z_as_relative  = false
		s.z_index        = pos.y * 10 + z_off
		s.position       = sprite_pos
		return s

	var wall_sprite: Sprite2D = _make_sprite.call(tile_atlas, _wall_layer.get_uv_rect.call(pos), 0)
	_wall_layer.occluders[pos] = wall_sprite
	get_parent().add_child.call_deferred(wall_sprite)

	if ore_types.has(pos):
		var ore_sprite: Sprite2D = _make_sprite.call(ore_atlas, _ore_layer.get_uv_rect.call(pos), 1)
		_ore_layer.occluders[pos] = ore_sprite
		get_parent().add_child.call_deferred(ore_sprite)

	if relic_tiles.has(pos) and relic_atlas != null:
		var relic_sprite: Sprite2D = _make_sprite.call(relic_atlas, _relic_layer.get_uv_rect.call(pos), 2)
		_relic_layer.occluders[pos] = relic_sprite
		get_parent().add_child.call_deferred(relic_sprite)

	# Instead of only clipping the region rect texture, completely recalculate 
	# the resting position offset and clip properties in tandem.
	_recalculate_full_occluder.call_deferred(pos)

func _remove_occluder_sprite(pos: Vector2i) -> void:
	if not _wall_layer.occluders.has(pos):
		return
	for layer: OverlayLayer in [_wall_layer, _ore_layer, _relic_layer]:
		if layer.occluders.has(pos):
			layer.occluders[pos].queue_free()
			layer.occluders.erase(pos)
		if layer.has_data.call(pos) and layer.index.has(pos):
			_write_layer_instance(layer, layer.index[pos], pos)

func update_occluder_depths(_player: Node2D) -> void:
	pass

# ══════════════════════════════════════════════════════════ collision ══
func _build_collision() -> void:
	for pos: Vector2i in tile_types.keys():
		_add_collision_shape(pos)

func _add_collision_shape(pos: Vector2i) -> void:
	var shape     := RectangleShape2D.new()
	shape.size     = Vector2(TILE_SIZE)
	var col       := CollisionShape2D.new()
	col.shape      = shape
	@warning_ignore("integer_division")
	col.position   = Vector2((pos - Vector2i(WIDTH / 2, HEIGHT / 2)) * TILE_SIZE) + Vector2(TILE_SIZE) / 2.0
	static_body.add_child(col)
	tile_shapes[pos] = col

# ══════════════════════════════════════════════════════════ bounce anim ══

# Returns the current bounce offset in pixels for a tile, or 0 if not bouncing.
func _get_bounce_offset(pos: Vector2i) -> float:
	if not _tile_bounces.has(pos):
		return 0.0
	var b: BounceState = _tile_bounces[pos]
	var age: float = (Time.get_ticks_msec() / 1000.0) - b.start_time - b.delay
	if age < 0.0:
		return 0.0
	return sin(clampf(age / 0.25, 0.0, 1.0) * PI) * b.amplitude

func bounce_tile(pos: Vector2i, amp: float = 6.0, delay: float = 0.0) -> void:
	var b          := BounceState.new()
	b.start_time    = Time.get_ticks_msec() / 1000.0
	b.amplitude     = amp
	b.delay         = delay
	_tile_bounces[pos] = b

func squish_tile(pos: Vector2i, amp: float = 6.0) -> void:
	bounce_tile(pos, amp)
	for nb: Vector2i in [pos + Vector2i(0,-1), pos + Vector2i(1,0),
						  pos + Vector2i(0,1),  pos + Vector2i(-1,0)]:
		if tile_exists(nb):
			bounce_tile(nb, amp * 0.35, 0.07)

func _update_tile_bounces() -> void:
	var now:      float           = Time.get_ticks_msec() / 1000.0
	var finished: Array[Vector2i] = []

	for pos: Vector2i in _tile_bounces.keys():
		var b: BounceState = _tile_bounces[pos]
		var age: float = now - b.start_time
		if age < b.delay:
			continue
		var t: float = (age - b.delay) / 0.25
		if t >= 1.0:
			_restore_tile_transform(pos)
			finished.append(pos)
			continue
		_apply_tile_offset(pos, sin(t * PI) * b.amplitude)

	for pos: Vector2i in finished:
		_tile_bounces.erase(pos)

func _apply_tile_offset(pos: Vector2i, offset_y: float) -> void:
	offset_y = clampf(offset_y, -TILE_SIZE.y / 2.0, TILE_SIZE.y / 2.0)

	var base:          Vector2 = _world_origin(pos)
	var has_air_below: bool    = is_air(pos + Vector2i(0, 1))

	# ── MultiMesh paths ────────────────────────────────────────────────
	for layer: OverlayLayer in [_wall_layer, _ore_layer, _relic_layer]:
		if layer == null or not layer.index.has(pos) or layer.occluders.has(pos):
			continue
		var t := Transform2D.IDENTITY
		t.origin = base + Vector2(0.0, offset_y)
		layer.multimesh.set_instance_transform_2d(layer.index[pos], t)
		var current_color: Color = layer.multimesh.get_instance_color(layer.index[pos])
		var clip_alpha: float = 1.0 + (offset_y if has_air_below else 0.0)
		layer.multimesh.set_instance_color(layer.index[pos], Color(current_color.r, current_color.g, current_color.b, clip_alpha))

	# ── Occluder Sprite2D: move and reclip this tile ───────────────────
	var sprite_base_y: float = _sprite_top_left(pos).y
	for layer: OverlayLayer in [_wall_layer, _ore_layer, _relic_layer]:
		if layer == null or not layer.occluders.has(pos):
			continue
		layer.occluders[pos].position.y = sprite_base_y + offset_y

	# Both loops explicitly enforce the fresh _get_occluder_clip_height constraints per-frame
	# Reclip this tile (its own bounce shifts the clip boundary).
	_apply_occluder_clip(pos)

	# Reclip the tile above (the tile below it — this tile — moved).
	_apply_occluder_clip(pos + Vector2i(0, -1))

func _restore_tile_transform(pos: Vector2i) -> void:
	_apply_tile_offset(pos, 0.0)
	for layer: OverlayLayer in [_wall_layer, _ore_layer, _relic_layer]:
		if layer == null or layer.occluders.has(pos) or not layer.index.has(pos):
			continue
		_write_layer_instance(layer, layer.index[pos], pos)

# ══════════════════════════════════════════════════════════ nearest tile ══
func get_nearest_mineable_tile(aim_world: Vector2, origin_world: Vector2, range: float) -> Vector2:
	var aim_map:    Vector2i = world_to_map(aim_world)
	var tile_range: int      = int(ceil(range / float(TILE_SIZE.x))) + 1

	var best_dist_sq: float   = INF
	var best_world:   Vector2 = Vector2.INF

	for dx: int in range(-tile_range, tile_range + 1):
		for dy: int in range(-tile_range, tile_range + 1):
			var candidate: Vector2i = aim_map + Vector2i(dx, dy)
			if not tile_exists(candidate):
				continue
			var cand_world: Vector2 = map_to_world(candidate)
			if range > 0.0 and cand_world.distance_to(origin_world) > range:
				continue
			var d2: float = cand_world.distance_squared_to(aim_world)
			if d2 < best_dist_sq:
				best_dist_sq = d2
				best_world   = cand_world

	return best_world

# ══════════════════════════════════════════════════════════ drops ══
func _drop_ore(pos: Vector2i) -> void:
	if not ore_types.has(pos):
		return
	var metal: MetalData = ItemManager._metal_map.get(ore_types[pos], null)
	if metal != null:
		ItemManager.spawn_metal_drop(map_to_world(pos), metal)

# ══════════════════════════════════════════════════════════ damage / removal ══
func damage_tile(pos: Vector2i, damage: int = 1, play_bounce: bool = true) -> bool:
	if not tile_health.has(pos):
		return false
	if play_bounce:
		squish_tile(pos)
	tile_health[pos] -= damage
	if tile_health[pos] <= 0:
		if ore_types.has(pos):
			ParticleManager.spawn_ore_rubble(map_to_world(pos), tile_types[pos], ore_types[pos])
			_drop_ore(pos)
		if camera and camera.has_method("shake"):
			camera.shake(0.1)
		remove_tile(pos)
		return true
	camera.shake(0.05)
	return false

func damage_tile_silent(pos: Vector2i, damage: int = 1) -> bool:
	if not tile_health.has(pos):
		return false
	tile_health[pos] -= damage
	if tile_health[pos] <= 0:
		if ore_types.has(pos):
			_drop_ore(pos)
		_remove_tile_silent(pos)
		return true
	return false

func _erase_tile_data(pos: Vector2i) -> void:
	tile_health.erase(pos)
	tile_types.erase(pos)
	tile_variant.erase(pos)
	tile_shapes[pos].disabled = true
	if ore_types.has(pos):
		_hide_ore_instance(pos)
		ore_types.erase(pos)
		ore_variant.erase(pos)
	if relic_tiles.has(pos):
		_hide_relic_instance(pos)
		_check_relic_reveal(pos)
		relic_tiles.erase(pos)

func _remove_tile_silent(pos: Vector2i) -> void:
	if not tile_types.has(pos):
		return
	_erase_tile_data(pos)
	if _wall_layer.occluders.has(pos):
		_remove_occluder_sprite(pos)
	else:
		_hide_wall_instance(pos)

func remove_tile(pos: Vector2i) -> void:
	if not tile_types.has(pos):
		return
	_tile_bounces.erase(pos)
	_erase_tile_data(pos)
	NavManager.on_tile_removed(pos)
	if _wall_layer.occluders.has(pos):
		_remove_occluder_sprite(pos)
	else:
		_hide_wall_instance(pos)
	var below: Vector2i = pos + Vector2i(0, 1)
	if tile_types.has(below) and not _wall_layer.occluders.has(below):
		_add_occluder_sprite(below)
	_redraw_neighbors(pos)
	_mark_chunk_dirty(pos)
	_request_df_update()

func flush_removed_tiles(removed: Array[Vector2i]) -> void:
	if removed.is_empty():
		return
	var nav_touched: Dictionary = {}
	var df_touched:  Dictionary = {}
	for pos in removed:
		var below: Vector2i = pos + Vector2i(0, 1)
		if tile_types.has(below) and not _wall_layer.occluders.has(below):
			_add_occluder_sprite(below)
		_redraw_neighbors(pos)
		nav_touched[Vector2i(pos.x / NavManager.chunk_size, pos.y / NavManager.chunk_size)] = true
		df_touched[Vector2i(pos.x / DF_CHUNK_SIZE, pos.y / DF_CHUNK_SIZE)]                  = true
	for chunk in nav_touched:
		NavManager._dirty_chunks[chunk] = NavManager.REBAKE_DELAY
	for chunk in df_touched:
		if not _df_dirty_chunks.has(chunk):
			_df_dirty_chunks.append(chunk)
	_request_df_update()

# ══════════════════════════════════════════════════ relic reveal ══
func _check_relic_reveal(pos: Vector2i) -> void:
	if not _relic_cover_counts.has(pos):
		return
	var entry: Dictionary = _relic_cover_counts[pos]
	_relic_cover_counts.erase(pos)
	entry["remaining"] -= 1
	if entry["remaining"] <= 0:
		var container: AncientContainer = _relic_containers.get(entry["center"], null)
		if container != null:
			container.set_interactable(true)

func _spawn_relic_container(center: Vector2i, relic: RelicData) -> void:
	var container: AncientContainer = AncientContainerScene.instantiate()
	container.relic = relic
	var world_tl: Vector2 = map_to_world(center)
	var world_br: Vector2 = map_to_world(center + Vector2i(1, 1))
	get_parent().add_child(container)
	container.global_position = (world_tl + world_br) * 0.5
	container.set_interactable(false)
	_relic_containers[center] = container

func _spawn_relic_containers() -> void:
	var seen: Dictionary = {}
	for pos: Vector2i in relic_tiles:
		var entry: Dictionary = _relic_cover_counts[pos]
		var center: Vector2i  = entry["center"]
		if seen.has(center):
			continue
		seen[center] = true
		_spawn_relic_container(center, entry["relic"])
		print("Spawned a relic at %d, %d" % [center.x, center.y])

# ══════════════════════════════════════════════════════════ proc gen ══
func count_neighbors(grid: Array, x: int, y: int) -> int:
	var count: int = 0
	for nx in range(x - 1, x + 2):
		for ny in range(y - 1, y + 2):
			if nx == x and ny == y: continue
			if nx >= 0 and nx < WIDTH and ny >= 0 and ny < HEIGHT:
				if grid[nx][ny] == Util.tile.AIR:
					count += 1
	return count

func cellular_step(grid: Array) -> Array[Array]:
	var new_grid: Array[Array] = []
	for x in range(WIDTH):
		new_grid.append([])
		for y in range(HEIGHT):
			var alive:     bool = grid[x][y] == Util.tile.AIR
			var neighbors: int  = count_neighbors(grid, x, y)
			if alive:
				if neighbors < CELL_DEATH_THRESHOLD:
					var neighbor_value: Variant = null
					for _x in range(-1, 2):
						for _y in range(-1, 2):
							var nx: int = x + _x
							var ny: int = y + _y
							if nx < 0 or nx >= WIDTH or ny < 0 or ny >= HEIGHT: continue
							if grid[nx][ny] != Util.tile.AIR and grid[nx][ny] != grid[x][y]:
								neighbor_value = grid[nx][ny]
								break
						if neighbor_value != null: break
					new_grid[x].append(neighbor_value if neighbor_value != null else null)
				else:
					new_grid[x].append(grid[x][y])
			else:
				if neighbors > CELL_BIRTH_THRESHOLD and is_replaceable(grid[x][y]):
					new_grid[x].append(Util.tile.AIR)
				else:
					new_grid[x].append(grid[x][y])
	return new_grid

func place_starting_area(grid: Array) -> void:
	@warning_ignore("integer_division")
	var cx: int = WIDTH  / 2
	@warning_ignore("integer_division")
	var cy: int = HEIGHT / 2
	for x in range(cx - STARTING_AREA_RADIUS, cx + STARTING_AREA_RADIUS + 1):
		for y in range(cy - STARTING_AREA_RADIUS, cy + STARTING_AREA_RADIUS + 1):
			if sqrt((x - cx) ** 2 + (y - cy) ** 2) <= STARTING_AREA_RADIUS:
				grid[x][y] = Util.tile.AIR

func generate_ores(grid: Array) -> void:
	place_gold(grid)
	place_copper(grid)

func place_gold(grid: Array) -> void:
	@warning_ignore("integer_division")
	for chunk_x in range(WIDTH / CHUNK_SIZE):
		@warning_ignore("integer_division")
		for chunk_y in range(HEIGHT / CHUNK_SIZE):
			if randf() >= CHUNK_CHANCE:
				continue
			var points: Array[Vector2i] = []
			for _x in range(CHUNK_SIZE):
				for _y in range(CHUNK_SIZE):
					if randf() < ADD_POINT_CHANCE:
						points.append(Vector2i(_x, _y))
			if points.size() < 2:
				continue
			if randf() < 0.5:
				points.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x)
			else:
				points.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y)
			for i in range(points.size() - 1):
				var line: Array[Vector2] = bresenham_line(points[i], points[i + 1])
				if randf() < 0.35 and line.size() > 2:
					line.append_array(generate_branch(Vector2i(line[randi_range(1, line.size() - 2)])))
				for p: Vector2 in line:
					var tx: int = chunk_x * CHUNK_SIZE + int(p.x)
					var ty: int = chunk_y * CHUNK_SIZE + int(p.y)
					if tx >= 0 and tx < WIDTH and ty >= 0 and ty < HEIGHT and grid[tx][ty] != Util.tile.AIR:
						grid[tx][ty] = Util.tile.GOLD

func bresenham_line(a: Vector2, b: Vector2) -> Array[Vector2]:
	var x0: int = int(a.x); var y0: int = int(a.y)
	var x1: int = int(b.x); var y1: int = int(b.y)
	var tiles: Array[Vector2] = []
	var dx: int = abs(x1 - x0); var dy: int = -abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	while true:
		tiles.append(Vector2(x0, y0))
		if x0 == x1 and y0 == y1: break
		var e2: int = 2 * err
		if e2 >= dy: err += dy; x0 += sx
		if e2 <= dx: err += dx; y0 += sy
	return tiles

func generate_branch(origin: Vector2, length: int = 4, turn_chance: float = 0.5) -> Array[Vector2]:
	var tiles:   Array[Vector2] = []
	var dir:     Vector2        = Vector2(1, 0).rotated(randf_range(0, PI * 2))
	var current: Vector2        = Vector2(origin)
	for i in range(length):
		if randf() < turn_chance:
			dir = dir.rotated(randf_range(-0.6, 0.6))
		current += dir.snapped(Vector2(1, 1))
		tiles.append(current)
	return tiles

func generate_faults(grid: Array) -> Array[Array]:
	var new_grid: Array[Array] = []
	var fault_point: Vector2i
	if rock_variation_tiles.is_empty():
		@warning_ignore("integer_division")
		fault_point = Vector2i(WIDTH / 2, HEIGHT / 2)
	else:
		var pt: Vector2i = rock_variation_tiles.pop_at(0)
		while sqrt((pt.x - WIDTH / 2.0) ** 2 + (pt.y - HEIGHT / 2.0) ** 2) > WIDTH / 4.0:
			pt = rock_variation_tiles.pop_at(randi_range(0, rock_variation_tiles.size() - 1))
		fault_point = pt

	var m:         float   = randf_range(-2.0, 2.0)
	var fault_dir: Vector2 = Vector2(1.0 / sqrt(1.0 + m ** 2), m / sqrt(1.0 + m ** 2))
	var magnitude: float   = randf_range(16.0, 32.0)
	print("Fault magnitude: %.2f" % magnitude)

	for x in range(WIDTH):
		new_grid.append([])
		var y_fault: float = m * (x - fault_point.x) + fault_point.y
		for y in range(HEIGHT):
			if y < y_fault:
				var x_old: int = int(x - fault_dir.x * magnitude)
				var y_old: int = int(y - fault_dir.y * magnitude)
				if x_old < 0 or x_old >= WIDTH or y_old < 0 or y_old >= HEIGHT:
					new_grid[x].append(Util.tile.AIR)
				else:
					new_grid[x].append(grid[x_old][y_old])
			else:
				new_grid[x].append(grid[x][y])

	var candidates: Array[Vector2i] = []
	for x in range(WIDTH):
		var y_fault: float = m * (x - fault_point.x) + fault_point.y
		var y:       int   = int(floor(y_fault))
		var dist:    float = sqrt((x - WIDTH / 2.0) ** 2 + (y - HEIGHT / 2.0) ** 2)
		var radius:  float = (WIDTH - BUFFER_TILES) / 2.0
		if dist < radius and dist > radius - 16.0:
			candidates.append(Vector2i(x, y))
	for i in range(2):
		if candidates.is_empty(): break
		var loc: Vector2i = candidates.pop_at(randi_range(0, candidates.size() - 1))
		if new_grid[loc.x][loc.y] != Util.tile.AIR:
			new_grid[loc.x][loc.y] = Util.tile.CRYSTAL
		print("Crystal %d: %d, %d" % [i + 1, loc.x, loc.y])
	return new_grid

func place_copper(grid: Array) -> void:
	for chunk_x in range(0, WIDTH, CHUNK_SIZE):
		for chunk_y in range(0, HEIGHT, CHUNK_SIZE):
			if randf() > COPPER_CHANCE: continue
			var seeds: Array[Vector2i] = []
			for x in range(chunk_x, chunk_x + CHUNK_SIZE):
				for y in range(chunk_y, chunk_y + CHUNK_SIZE):
					if x >= WIDTH or y >= HEIGHT or grid[x][y] == null: continue
					if randf() < COPPER_ADD_CHANCE:
						seeds.append(Vector2i(x, y))
			for center: Vector2i in seeds:
				var rx: int = randi_range(COPPER_MIN_RADIUS, COPPER_MAX_RADIUS)
				var ry: int = randi_range(COPPER_MIN_RADIUS, COPPER_MAX_RADIUS)
				for dx in range(-rx, rx + 1):
					for dy in range(-ry, ry + 1):
						var px: int = center.x + dx
						var py: int = center.y + dy
						if px < 0 or px >= WIDTH or py < 0 or py >= HEIGHT: continue
						var nx: float = float(dx) / float(rx)
						var ny: float = float(dy) / float(ry)
						if nx * nx + ny * ny <= 1.0 and grid[px][py] != Util.tile.AIR:
							grid[px][py] = Util.tile.COPPER

func _place_relic_tiles_on_grid(grid: Array) -> void:
	if ItemManager._relic_pool.is_empty():
		printerr("Warning! No relics exist to be loaded!")
		return
	var target:   int = randi_range(relic_count.x, relic_count.y)
	var placed:   int = 0
	var attempts: int = 0

	var play_radius: float = (WIDTH - BUFFER_TILES) / 2.0
	var cx: float = WIDTH  / 2.0
	var cy: float = HEIGHT / 2.0

	while placed < target and attempts < 5000:
		attempts += 1
		var x: int = randi_range(BUFFER_TILES + 4, WIDTH  - BUFFER_TILES - 4)
		var y: int = randi_range(BUFFER_TILES + 4, HEIGHT - BUFFER_TILES - 4)
		var cluster: Array[Vector2i] = [Vector2i(x,y), Vector2i(x+1,y), Vector2i(x,y+1), Vector2i(x+1,y+1)]
		var valid: bool = true
		for pos in cluster:
			if pos.x >= WIDTH or pos.y >= HEIGHT:
				valid = false; break
			if sqrt((pos.x - cx) ** 2 + (pos.y - cy) ** 2) >= play_radius:
				valid = false; break
			var t: Variant = grid[pos.x][pos.y]
			if t != Util.tile.STONE and t != Util.tile.ROCK:
				valid = false; break
			if relic_tiles.has(pos):
				valid = false; break
		if not valid: continue
		var relic: RelicData = ItemManager._relic_pool.pick_random()
		var entry: Dictionary = { "relic": relic, "remaining": 4, "center": Vector2i(x, y) }
		for pos in cluster:
			relic_tiles[pos]         = relic
			_relic_cover_counts[pos] = entry
		placed += 1
	print("Placed %d relic clusters" % placed)

# ══════════════════════════════════════════════ distance field ══
func _initial_df_bake() -> void:
	var img:  Image = Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RF)
	var dist: Array = []; dist.resize(WIDTH * HEIGHT); dist.fill(-1.0)
	var queue: Array[Vector2i] = []
	for x in range(WIDTH):
		for y in range(HEIGHT):
			if is_air(Vector2i(x, y)):
				dist[y * WIDTH + x] = 0.0
				queue.append(Vector2i(x, y))
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	var i: int = 0
	while i < queue.size():
		var cur: Vector2i = queue[i]; i += 1
		for d in dirs:
			var nb: Vector2i = cur + d
			if nb.x < 0 or nb.y < 0 or nb.x >= WIDTH or nb.y >= HEIGHT: continue
			if dist[nb.y * WIDTH + nb.x] >= 0.0: continue
			dist[nb.y * WIDTH + nb.x] = dist[cur.y * WIDTH + cur.x] + 1.0
			queue.append(nb)
	for x in range(WIDTH):
		for y in range(HEIGHT):
			img.set_pixel(x, y, Color(clampf((dist[y * WIDTH + x] - 1.0) / DF_MAX_DEPTH, 0.0, 1.0), 0, 0, 1))
	_df_image = img
	_df_texture.set_image(img)
	_set_df_shader_params()

func _set_df_shader_params() -> void:
	var world_origin: Vector2 = map_to_world(Vector2i(0, 0)) - Vector2(TILE_SIZE) / 2.0
	var wall_mats: Array[ShaderMaterial] = [
		_wall_layer.instance.material,
		_ore_layer.instance.material,
	]
	if _relic_layer.instance != null:
		wall_mats.append(_relic_layer.instance.material)
	for mat: ShaderMaterial in wall_mats:
		mat.set_shader_parameter("distance_field",   _df_texture)
		mat.set_shader_parameter("map_size",         Vector2(WIDTH, HEIGHT))
		mat.set_shader_parameter("map_world_origin", world_origin)
		mat.set_shader_parameter("tile_world_size",  float(TILE_SIZE.x))
		mat.set_shader_parameter("max_depth",        DF_MAX_DEPTH)
		mat.set_shader_parameter("darkness_power",   1.0)
	if _ground_layer.instance != null:
		var mat: ShaderMaterial = _ground_layer.instance.material
		mat.set_shader_parameter("distance_field",   _df_texture)
		mat.set_shader_parameter("map_size",         Vector2(WIDTH, HEIGHT))
		mat.set_shader_parameter("map_world_origin", world_origin)
		mat.set_shader_parameter("tile_world_size",  float(TILE_SIZE.x))
		mat.set_shader_parameter("max_depth",        DF_MAX_DEPTH)
		mat.set_shader_parameter("darkness_power",   0.0)

func _mark_chunk_dirty(pos: Vector2i) -> void:
	var chunk: Vector2i = Vector2i(pos.x / DF_CHUNK_SIZE, pos.y / DF_CHUNK_SIZE)
	if not _df_dirty_chunks.has(chunk):
		_df_dirty_chunks.append(chunk)

func _request_df_update() -> void:
	if _df_running or _df_dirty_chunks.is_empty():
		return
	_df_running = true
	var dirty_copy: Array[Vector2i] = _df_dirty_chunks.duplicate()
	_df_dirty_chunks.clear()
	_df_thread.start(_compute_df_threaded.bind(dirty_copy, tile_types.duplicate(), _df_image.duplicate()))

func _compute_df_threaded(dirty_chunks: Array[Vector2i], snapshot: Dictionary, base_img: Image) -> void:
	var min_tile := Vector2i(WIDTH, HEIGHT)
	var max_tile := Vector2i(0, 0)
	for chunk in dirty_chunks:
		var margin: int = int(DF_MAX_DEPTH) + 2
		min_tile.x = mini(min_tile.x, chunk.x * DF_CHUNK_SIZE - margin)
		min_tile.y = mini(min_tile.y, chunk.y * DF_CHUNK_SIZE - margin)
		max_tile.x = maxi(max_tile.x, (chunk.x + 1) * DF_CHUNK_SIZE + margin)
		max_tile.y = maxi(max_tile.y, (chunk.y + 1) * DF_CHUNK_SIZE + margin)
	min_tile = min_tile.clamp(Vector2i.ZERO, Vector2i(WIDTH - 1, HEIGHT - 1))
	max_tile = max_tile.clamp(Vector2i.ZERO, Vector2i(WIDTH - 1, HEIGHT - 1))
	var rw: int = max_tile.x - min_tile.x + 1
	var rh: int = max_tile.y - min_tile.y + 1
	var dist: Array = []; dist.resize(rw * rh); dist.fill(-1.0)
	var queue: Array[Vector2i] = []
	for x in range(rw):
		for y in range(rh):
			if not snapshot.has(min_tile + Vector2i(x, y)):
				dist[y * rw + x] = 0.0
				queue.append(Vector2i(x, y))
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	var i: int = 0
	while i < queue.size():
		var cur: Vector2i = queue[i]; i += 1
		for d in dirs:
			var nb: Vector2i = cur + d
			if nb.x < 0 or nb.y < 0 or nb.x >= rw or nb.y >= rh: continue
			if dist[nb.y * rw + nb.x] >= 0.0: continue
			dist[nb.y * rw + nb.x] = dist[cur.y * rw + cur.x] + 1.0
			queue.append(nb)
	var patch: Image = Image.create(rw, rh, false, Image.FORMAT_RF)
	for x in range(rw):
		for y in range(rh):
			var d:       float = dist[y * rw + x]
			var new_val: float = clampf((d - 1.0) / DF_MAX_DEPTH, 0.0, 1.0) if d >= 0.0 else 0.0
			var old_val: float = base_img.get_pixel(min_tile.x + x, min_tile.y + y).r
			patch.set_pixel(x, y, Color(new_val if new_val < old_val else old_val, 0, 0, 1))
	_df_pending      = patch
	_df_pending_rect = Rect2i(min_tile, Vector2i(rw, rh))
