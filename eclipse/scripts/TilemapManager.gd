extends Node

var map_seed: int

@export_group("Proc Gen Parameters")
@export_subgroup("Map Sizing")
@export_multiline var note: String = "WIDTH and HEIGHT must be divisible by 16 since CHUNK_SIZE is WIDTH/16"
@export var WIDTH:                int     = 256 + 32
@export var HEIGHT:               int     = 256 + 32
@warning_ignore("integer_division")
@export var CHUNK_SIZE:           int     = WIDTH / 16
@export var TILE_SIZE:            Vector2i = Vector2i(32, 32)
@export var STARTING_AREA_RADIUS: float   = 3 * sqrt(2)

@export_subgroup("Air Generation Perlin Values")
@export var PERLIN_CHAMBER_THRESHOLD: float = 0.20
@export var PERLIN_CHAMBER_FREQUENCY: float = 0.04
@export var PERLIN_PATH_THRESHOLD:    float = 0.06
@export var PERLIN_PATH_FREQUENCY:    float = 0.01

@export_subgroup("Air Edge Smoothing")
@export var CELL_DEATH_THRESHOLD: int = 4
@export var CELL_BIRTH_THRESHOLD: int = 4

@export_subgroup("Gold Generation")
@export var CHUNK_CHANCE:    float = 0.25
@export var ADD_POINT_CHANCE: float = 0.035

@export_subgroup("Copper Generation")
@export var COPPER_CHANCE:      float = 0.1
@export var COPPER_ADD_CHANCE:  float = 0.015
@export var COPPER_MIN_RADIUS:  int   = 3
@export var COPPER_MAX_RADIUS:  int   = 5

@export_subgroup("Rock Variation")
@export var ROCK_VARIATION_THRESHOLD: float = 0.01
@export var ROCK_VARIATION_FREQUENCY: float = 0.025

@export var BUFFER_TILES: int = 32

@export_group("Rendering")
@export var tile_atlas:      Texture2D
@export var ore_atlas:       Texture2D
@export var ATLAS_TILE_SIZE: Vector2i = Vector2i(32, 48)
var SPRITE_OFFSET_Y: float = 0

# ── bitmask atlas layout ──────────────────────────────────────────────────────
# Each entry: atlas row of the FIRST variant for bitmask tiles 0-15
# Variants occupy consecutive rows beneath the base row
@export_subgroup("Bitmask Atlas Rows")
@export var atlas_row_stone:   int = 0   # stone base row
@export var atlas_variants_stone: int = 2
@export var atlas_row_rock:    int = 2   # rock base row
@export var atlas_variants_rock:  int = 2
@export var atlas_row_crystal: int = 4
@export var atlas_variants_crystal: int = 1

# ── ore atlas layout ──────────────────────────────────────────────────────────
@export var ore_row_gold:          int = 0
@export var ore_variants_gold:     int = 1
@export var ore_row_copper:        int = 1
@export var ore_variants_copper:   int = 1

# ── noise ─────────────────────────────────────────────────────────────────────
var chamber_noise:        FastNoiseLite = FastNoiseLite.new()
var path_noise:           FastNoiseLite = FastNoiseLite.new()
var rock_variation_noise: FastNoiseLite = FastNoiseLite.new()
var rock_variation_tiles: Array[Vector2i] = []

# ── tile data ─────────────────────────────────────────────────────────────────
var tile_types:   Dictionary = {}   # Vector2i -> Util.tile (stone/rock/crystal only)
var ore_types:    Dictionary = {}   # Vector2i -> Util.tile (gold/copper only)
var tile_health:  Dictionary = {}   # Vector2i -> int (shared pool for ore+base)
var tile_shapes:  Dictionary = {}
var tile_variant: Dictionary = {}   # Vector2i -> int (which variant row was chosen)
var ore_variant:  Dictionary = {}   # Vector2i -> int

var static_body: StaticBody2D

# ── multimesh ─────────────────────────────────────────────────────────────────
var multimesh:           MultiMesh
var multimesh_instance:  MultiMeshInstance2D
var tile_instance_index: Dictionary = {}

var ore_multimesh:          MultiMesh
var ore_multimesh_instance: MultiMeshInstance2D
var ore_instance_index:     Dictionary = {}

var gold_tiles_added:   int = 0
var copper_tiles_added: int = 0

# ── occluder ──────────────────────────────────────────────────────────────────
var occluder_sprites: Dictionary = {}
var ore_occluder_sprites: Dictionary = {}  # Vector2i -> Sprite2D

# ─────────────────────────────────────────────────────────────────── ready ───
func _ready() -> void:
	SPRITE_OFFSET_Y = (ATLAS_TILE_SIZE.y - TILE_SIZE.y) / 2.0
	map_seed = randi()

	_setup_noise(chamber_noise,        PERLIN_CHAMBER_FREQUENCY)
	_setup_noise(path_noise,           PERLIN_PATH_FREQUENCY)
	_setup_noise(rock_variation_noise, ROCK_VARIATION_FREQUENCY)

	var tilemap: Array[Array] = []
	for x in range(WIDTH):
		tilemap.append([])
		for y in range(HEIGHT):
			tilemap[x].append(Util.tile.STONE)

	generate_rock_variation(tilemap)
	generate_ores(tilemap)
	tilemap = generate_faults(tilemap)
	generate_chamber_noise(tilemap)
	generate_path_noise(tilemap)
	for i in range(6):
		tilemap = cellular_step(tilemap)
	place_starting_area(tilemap)

	for x in range(WIDTH):
		for y in range(HEIGHT):
			var dist: float = sqrt((x - WIDTH / 2.0) ** 2 + (y - HEIGHT / 2.0) ** 2)
			if dist >= (WIDTH - BUFFER_TILES) / 2.0:
				continue
			var t: Util.tile = tilemap[x][y]
			if t == null or t == Util.tile.AIR:
				continue
			var map_pos: Vector2i = Vector2i(x, y)
			if _is_ore(t):
				# Store ore separately, base tile defaults to STONE
				ore_types[map_pos]    = t
				tile_types[map_pos]   = Util.tile.STONE
				ore_variant[map_pos]  = randi() % _ore_variant_count(t)
				if t == Util.tile.COPPER: copper_tiles_added += 1
				elif t == Util.tile.GOLD: gold_tiles_added   += 1
			else:
				tile_types[map_pos] = t
			tile_health[map_pos]  = get_tile_max_health(t)
			tile_variant[map_pos] = randi() % _base_variant_count(t)

	print("Generated %d gold tiles"   % gold_tiles_added)
	print("Generated %d copper tiles" % copper_tiles_added)

	_setup_rendering()
	_initial_df_bake()
	_build_collision()
	_setup_occluder()

func _setup_noise(noise: FastNoiseLite, frequency: float) -> void:
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed       = map_seed
	noise.frequency  = frequency

# ──────────────────────────────────────────────────────────────── bitmask ───
# North=1, East=2, South=4, West=8
func _get_bitmask(map_pos: Vector2i) -> int:
	var mask: int = 0
	if not is_air(map_pos + Vector2i( 0, -1)): mask |= 1
	if not is_air(map_pos + Vector2i( 1,  0)): mask |= 2
	if not is_air(map_pos + Vector2i( 0,  1)): mask |= 4
	if not is_air(map_pos + Vector2i(-1,  0)): mask |= 8
	return mask

func _base_atlas_uv(map_pos: Vector2i) -> Rect2:
	if not tile_types.has(map_pos) or not tile_variant.has(map_pos):
		return Rect2()
	var t:        Util.tile = tile_types[map_pos]
	var variant:  int       = tile_variant[map_pos]
	var base_row: int       = _base_row_for(t) + variant
	var bitmask:  int       = _get_bitmask(map_pos)
	return _uv_for(bitmask, base_row, tile_atlas)

func _ore_atlas_uv(map_pos: Vector2i) -> Rect2:
	var t:       Util.tile = ore_types[map_pos]
	var variant: int       = ore_variant[map_pos]
	var base_row: int      = _ore_row_for(t) + variant
	var bitmask:  int      = _get_bitmask(map_pos)
	return _uv_for(bitmask, base_row, ore_atlas)

func _uv_for(col: int, row: int, atlas: Texture2D) -> Rect2:
	var atlas_px:  Vector2 = Vector2(atlas.get_size()) if atlas else Vector2(512.0, 192.0)
	var uv_origin: Vector2 = Vector2(col * ATLAS_TILE_SIZE.x, row * ATLAS_TILE_SIZE.y) / atlas_px
	var uv_size:   Vector2 = Vector2(ATLAS_TILE_SIZE) / atlas_px
	return Rect2(uv_origin, uv_size)

func _base_row_for(t: Util.tile) -> int:
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

func _is_ore(t: Util.tile) -> bool:
	return t == Util.tile.GOLD or t == Util.tile.COPPER

# ─────────────────────────────────────────────────────────────── rendering ───
func _make_quad_mesh() -> QuadMesh:
	var quad: QuadMesh = QuadMesh.new()
	@warning_ignore("integer_division")
	quad.size = Vector2(TILE_SIZE) + Vector2(0, TILE_SIZE.y / 2)
	return quad

func _setup_rendering() -> void:
	static_body                 = StaticBody2D.new()
	static_body.collision_layer = 1
	static_body.collision_mask  = 0
	static_body.scale           = get_parent().scale
	add_child(static_body)

	# ── base multimesh ──
	multimesh                  = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors       = true
	multimesh.use_custom_data  = true
	multimesh.mesh             = _make_quad_mesh()
	multimesh.instance_count   = tile_types.size()

	multimesh_instance             = MultiMeshInstance2D.new()
	multimesh_instance.scale       = get_parent().scale
	multimesh_instance.multimesh   = multimesh
	multimesh_instance.texture     = tile_atlas
	multimesh_instance.z_index     = -1
	multimesh_instance.z_as_relative = false

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/MultiMesh.gdshader")
	mat.set_shader_parameter("atlas",       tile_atlas)
	mat.set_shader_parameter("sprite_size", Vector2(ATLAS_TILE_SIZE))
	multimesh_instance.material = mat
	add_child(multimesh_instance)

	# ── ore multimesh ──
	ore_multimesh                  = MultiMesh.new()
	ore_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	ore_multimesh.use_colors       = true
	ore_multimesh.use_custom_data  = true
	ore_multimesh.mesh             = _make_quad_mesh()
	ore_multimesh.instance_count   = ore_types.size()

	ore_multimesh_instance               = MultiMeshInstance2D.new()
	ore_multimesh_instance.scale         = get_parent().scale
	ore_multimesh_instance.multimesh     = ore_multimesh
	ore_multimesh_instance.texture       = ore_atlas
	ore_multimesh_instance.z_index       = -1
	ore_multimesh_instance.z_as_relative = false

	var ore_mat := ShaderMaterial.new()
	ore_mat.shader = preload("res://scripts/MultiMesh.gdshader")
	ore_mat.set_shader_parameter("atlas",       ore_atlas)
	ore_mat.set_shader_parameter("sprite_size", Vector2(ATLAS_TILE_SIZE))
	ore_multimesh_instance.material = ore_mat
	add_child(ore_multimesh_instance)

	# ── write instances ──
	var sorted_tiles: Array = tile_types.keys()
	sorted_tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y)
	var idx: int = 0
	for map_pos: Vector2i in sorted_tiles:
		tile_instance_index[map_pos] = idx
		_write_base_instance(idx, map_pos)
		idx += 1

	var sorted_ores: Array = ore_types.keys()
	sorted_ores.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y)
	idx = 0
	for map_pos: Vector2i in sorted_ores:
		ore_instance_index[map_pos] = idx
		_write_ore_instance(idx, map_pos)
		idx += 1

func _world_origin(map_pos: Vector2i) -> Vector2:
	@warning_ignore("integer_division")
	var local_pos: Vector2 = Vector2((map_pos - Vector2i(WIDTH / 2, HEIGHT / 2)) * TILE_SIZE) + Vector2(TILE_SIZE) / 2.0
	local_pos.y -= SPRITE_OFFSET_Y
	return local_pos

func _write_base_instance(idx: int, map_pos: Vector2i) -> void:
	var t: Transform2D = Transform2D.IDENTITY
	t.origin = _world_origin(map_pos)
	multimesh.set_instance_transform_2d(idx, t)
	var has_side: bool = is_air(map_pos + Vector2i(0, 1))
	multimesh.set_instance_color(idx, Color(1.0, 1.0, 1.0, 0.0 if has_side else 1.0))
	var uv: Rect2 = _base_atlas_uv(map_pos)
	multimesh.set_instance_custom_data(idx, Color(uv.position.x, uv.position.y, uv.size.x, uv.size.y))

func _write_ore_instance(idx: int, map_pos: Vector2i) -> void:
	var t: Transform2D = Transform2D.IDENTITY
	t.origin = _world_origin(map_pos)
	ore_multimesh.set_instance_transform_2d(idx, t)
	var has_side: bool = is_air(map_pos + Vector2i(0, 1))
	ore_multimesh.set_instance_color(idx, Color(1.0, 1.0, 1.0, 0.0 if has_side else 1.0))
	var uv: Rect2 = _ore_atlas_uv(map_pos)
	ore_multimesh.set_instance_custom_data(idx, Color(uv.position.x, uv.position.y, uv.size.x, uv.size.y))

func _hide_instance(map_pos: Vector2i) -> void:
	if not tile_instance_index.has(map_pos):
		return
	var t := Transform2D.IDENTITY
	t.origin = Vector2(-999999, -999999)
	multimesh.set_instance_transform_2d(tile_instance_index[map_pos], t)

func _hide_ore_instance(map_pos: Vector2i) -> void:
	if not ore_instance_index.has(map_pos):
		return
	var t := Transform2D.IDENTITY
	t.origin = Vector2(-999999, -999999)
	ore_multimesh.set_instance_transform_2d(ore_instance_index[map_pos], t)

# When a neighbor changes, redraw affected tiles so bitmask updates
func _redraw_neighbors(map_pos: Vector2i) -> void:
	for neighbor: Vector2i in [
		map_pos + Vector2i( 0, -1),
		map_pos + Vector2i( 1,  0),
		map_pos + Vector2i( 0,  1),
		map_pos + Vector2i(-1,  0),
	]:
		if not tile_types.has(neighbor):
			continue
		if tile_instance_index.has(neighbor) and not occluder_sprites.has(neighbor):
			_write_base_instance(tile_instance_index[neighbor], neighbor)
		if ore_instance_index.has(neighbor):
			_write_ore_instance(ore_instance_index[neighbor], neighbor)
		if occluder_sprites.has(neighbor):
			occluder_sprites[neighbor].region_rect = _get_occluder_rect(neighbor)

func get_tile_uv(t: Util.tile) -> Rect2:
	return _uv_for(0, _base_row_for(t), tile_atlas)

func set_tile_color(map_pos: Vector2i, color: Color) -> void:
	if tile_instance_index.has(map_pos):
		multimesh.set_instance_color(tile_instance_index[map_pos], color)
	if ore_instance_index.has(map_pos):
		ore_multimesh.set_instance_color(ore_instance_index[map_pos], color)
	if occluder_sprites.has(map_pos):                                           # Magic number
		var sprite_color: Color = Color(
			(color.r - 1.0) * 0.38 + 1.0,
			(color.g - 1.0) * 0.38 + 1.0,
			(color.b - 1.0) * 0.38 + 1.0
		)
		occluder_sprites[map_pos].modulate = sprite_color

func get_tile_color(map_pos: Vector2i) -> Color:
	if not tile_instance_index.has(map_pos):
		return Color.WHITE
	return multimesh.get_instance_color(tile_instance_index[map_pos])

func get_z_for(world_pos: Vector2) -> int:
	var tile_row: int    = world_to_map(world_pos).y
	var tile_top: float  = map_to_world(Vector2i(0, tile_row)).y - TILE_SIZE.y / 2.0
	var within_tile: int = int((world_pos.y - tile_top) / float(TILE_SIZE.y) * 8.0)
	return tile_row * 10 + clampi(within_tile, 0, 9)

# ─────────────────────────────────────────────────────────────── occluder ───
func _get_occluder_rect(map_pos: Vector2i) -> Rect2:
	if not tile_types.has(map_pos) or not tile_variant.has(map_pos):
		return Rect2()
	var t:        Util.tile = tile_types[map_pos]
	var variant:  int       = tile_variant[map_pos]
	var base_row: int       = _base_row_for(t) + variant
	var bitmask:  int       = _get_bitmask(map_pos)
	return Rect2(Vector2(bitmask * ATLAS_TILE_SIZE.x, base_row * ATLAS_TILE_SIZE.y), Vector2(ATLAS_TILE_SIZE))

func _setup_occluder() -> void:
	for map_pos: Vector2i in tile_types.keys():
		if is_air(map_pos + Vector2i(0, -1)):
			_add_occluder_sprite(map_pos)

func _add_occluder_sprite(map_pos: Vector2i) -> void:
	if occluder_sprites.has(map_pos):
		return
	_hide_instance(map_pos)
	_hide_ore_instance(map_pos)  # hide ore multimesh too

	var world_center: Vector2 = map_to_world(map_pos)
	var sprite             := Sprite2D.new()
	sprite.texture          = tile_atlas
	sprite.region_enabled   = true
	sprite.region_rect      = _get_occluder_rect(map_pos)
	sprite.z_as_relative    = false
	sprite.z_index          = map_pos.y * 10
	sprite.position         = Vector2(world_center.x, world_center.y - SPRITE_OFFSET_Y - ATLAS_TILE_SIZE.y / 2.0)
	sprite.offset           = Vector2(0, ATLAS_TILE_SIZE.y / 2.0)
	occluder_sprites[map_pos] = sprite
	get_parent().add_child.call_deferred(sprite)

	# add ore overlay sprite on top if this tile has ore
	if ore_types.has(map_pos):
		var ore_sprite            := Sprite2D.new()
		ore_sprite.texture         = ore_atlas
		ore_sprite.region_enabled  = true
		ore_sprite.region_rect     = Rect2(
			_ore_atlas_uv(map_pos).position * Vector2(ore_atlas.get_size()),
			Vector2(ATLAS_TILE_SIZE)
		)
		ore_sprite.z_as_relative   = false
		ore_sprite.z_index         = map_pos.y * 10 + 1
		ore_sprite.position        = sprite.position
		ore_sprite.offset          = sprite.offset
		ore_occluder_sprites[map_pos] = ore_sprite
		get_parent().add_child.call_deferred(ore_sprite)

func _remove_occluder_sprite(map_pos: Vector2i) -> void:
	if not occluder_sprites.has(map_pos):
		return
	occluder_sprites[map_pos].queue_free()
	occluder_sprites.erase(map_pos)
	if ore_occluder_sprites.has(map_pos):
		ore_occluder_sprites[map_pos].queue_free()
		ore_occluder_sprites.erase(map_pos)
	if tile_types.has(map_pos):
		_write_base_instance(tile_instance_index[map_pos], map_pos)
	if ore_types.has(map_pos):
		_write_ore_instance(ore_instance_index[map_pos], map_pos)

func update_occluder_depths(_player: Node2D) -> void:
	pass

# ─────────────────────────────────────────────────────────────── collision ───
func _build_collision() -> void:
	for map_pos: Vector2i in tile_types.keys():
		_add_collision_shape(map_pos)

func _add_collision_shape(map_pos: Vector2i) -> void:
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size                  = Vector2(TILE_SIZE)
	var col: CollisionShape2D   = CollisionShape2D.new()
	col.shape                   = shape
	@warning_ignore("integer_division")
	col.position = Vector2((map_pos - Vector2i(WIDTH / 2, HEIGHT / 2)) * TILE_SIZE) + Vector2(TILE_SIZE) / 2.0
	static_body.add_child(col)
	tile_shapes[map_pos] = col

# ──────────────────────────────────────────────────────────────── mining ────
func get_tile_max_health(t: Util.tile) -> int:
	match t:
		Util.tile.STONE:   return 2
		Util.tile.ROCK:    return 3
		Util.tile.GOLD:    return 2
		Util.tile.COPPER:  return 2
		Util.tile.CRYSTAL: return 5
		_:                 return 3

func world_to_map(world_pos: Vector2) -> Vector2i:
	var local_pos: Vector2 = world_pos / get_parent().scale
	@warning_ignore("integer_division")
	return Vector2i((local_pos / Vector2(TILE_SIZE)).floor()) + Vector2i(WIDTH / 2, HEIGHT / 2)

func map_to_world(map_pos: Vector2i) -> Vector2:
	@warning_ignore("integer_division")
	var local_pos: Vector2 = Vector2((map_pos - Vector2i(WIDTH / 2, HEIGHT / 2)) * TILE_SIZE) + Vector2(TILE_SIZE) / 2.0
	return local_pos * get_parent().scale

func tile_exists(map_pos: Vector2i) -> bool:
	return tile_types.has(map_pos)

func is_air(map_pos: Vector2i) -> bool:
	return not tile_types.has(map_pos)
	
func _drop_ore(map_pos: Vector2i) -> void:
	if not ore_types.has(map_pos):
		return
	ItemManager.spawn_dropped_item(map_to_world(map_pos), ore_types[map_pos])

func damage_tile(map_pos: Vector2i, damage: int = 1) -> void:
	if not tile_health.has(map_pos):
		return
	var world_pos: Vector2  = map_to_world(map_pos)
	var base_type: Util.tile = tile_types[map_pos]
	ParticleManager.spawn_mine_dust(world_pos, base_type)
	ParticleManager.spawn_debris(world_pos, base_type)
	tile_health[map_pos] -= damage
	if tile_health[map_pos] <= 0:
		if ore_types.has(map_pos):
			ParticleManager.spawn_ore_rubble(world_pos, base_type, ore_types[map_pos])
			_drop_ore(map_pos)
		remove_tile(map_pos)

func remove_tile(map_pos: Vector2i) -> void:
	if not tile_types.has(map_pos):
		return

	tile_health.erase(map_pos)
	tile_types.erase(map_pos)
	tile_variant.erase(map_pos)
	tile_shapes[map_pos].disabled = true
	
	NavManager.on_tile_removed(map_pos)

	# Remove ore overlay if present
	if ore_types.has(map_pos):
		_hide_ore_instance(map_pos)
		ore_types.erase(map_pos)
		ore_variant.erase(map_pos)

	if occluder_sprites.has(map_pos):
		_remove_occluder_sprite(map_pos)
	else:
		_hide_instance(map_pos)

	# Promote tile below to occluder if now exposed
	var below: Vector2i = map_pos + Vector2i(0, 1)
	if tile_types.has(below) and not occluder_sprites.has(below):
		_add_occluder_sprite(below)

	# Redraw neighbors so their bitmasks update
	_redraw_neighbors(map_pos)
	
	# update the distance field for shadows created by the shader
	_mark_chunk_dirty(map_pos)
	_request_df_update()

func in_bounds(loc: Vector2i) -> bool:
	return loc.x >= 0 and loc.x < WIDTH and loc.y >= 0 and loc.y < HEIGHT

# ───────────────────────────────────────────────────────────────── proc gen ──
func generate_chamber_noise(grid: Array) -> void:
	for x in range(WIDTH):
		for y in range(HEIGHT):
			var perlin_value: float = chamber_noise.get_noise_2d(x, y)
			var dist: float         = sqrt((x - WIDTH / 2.0) ** 2 + (y - HEIGHT / 2.0) ** 2)
			var dist_n: float       = dist / ((WIDTH - BUFFER_TILES) / 2.0)
			var bonus: float        = 0.0
			if dist > (WIDTH - BUFFER_TILES) / 3.0:
				bonus = (1.0 - PERLIN_CHAMBER_THRESHOLD) * dist_n
			if perlin_value > (PERLIN_CHAMBER_THRESHOLD + bonus) and is_replaceable(grid[x][y]):
				grid[x][y] = Util.tile.AIR

func generate_path_noise(grid: Array) -> void:
	for x in range(WIDTH):
		for y in range(HEIGHT):
			var perlin_value: float = path_noise.get_noise_2d(x, y)
			var dist: float         = sqrt((x - WIDTH / 2.0) ** 2 + (y - HEIGHT / 2.0) ** 2)
			var dist_n: float       = dist / ((WIDTH - BUFFER_TILES) / 2.0)
			var bonus: float        = 0.0
			if dist > 2.0 * (WIDTH - BUFFER_TILES) / 5.0:
				bonus = PERLIN_PATH_THRESHOLD * dist_n
			if absf(perlin_value) < (PERLIN_PATH_THRESHOLD - bonus) and is_replaceable(grid[x][y]):
				grid[x][y] = Util.tile.AIR

func count_neighbors(grid: Array, x: int, y: int) -> int:
	var count: int = 0
	for nx in range(x - 1, x + 2):
		for ny in range(y - 1, y + 2):
			if nx == x and ny == y:
				continue
			if nx >= 0 and nx < WIDTH and ny >= 0 and ny < HEIGHT:
				if grid[nx][ny] == Util.tile.AIR:
					count += 1
	return count

func cellular_step(grid: Array) -> Array[Array]:
	var new_grid: Array[Array] = []
	for x in range(WIDTH):
		new_grid.append([])
		for y in range(HEIGHT):
			var alive: bool    = grid[x][y] == Util.tile.AIR
			var neighbors: int = count_neighbors(grid, x, y)
			if alive:
				if neighbors < CELL_DEATH_THRESHOLD:
					var neighbor_value: Variant = null
					for _x in range(-1, 2):
						for _y in range(-1, 2):
							var nx: int = x + _x
							var ny: int = y + _y
							if nx < 0 or nx >= WIDTH or ny < 0 or ny >= HEIGHT:
								continue
							if grid[nx][ny] != Util.tile.AIR and grid[nx][ny] != grid[x][y]:
								neighbor_value = grid[nx][ny]
								break
						if neighbor_value != null:
							break
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
	var x_mid: int = WIDTH  / 2
	@warning_ignore("integer_division")
	var y_mid: int = HEIGHT / 2
	for x in range(x_mid - STARTING_AREA_RADIUS, x_mid + STARTING_AREA_RADIUS + 1):
		for y in range(y_mid - STARTING_AREA_RADIUS, y_mid + STARTING_AREA_RADIUS + 1):
			if sqrt((x - x_mid) ** 2 + (y - y_mid) ** 2) <= STARTING_AREA_RADIUS:
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
				points.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
			else:
				points.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y)
			for i in range(points.size() - 1):
				var line: Array[Vector2] = bresenham_line(points[i], points[i + 1])
				if randf() < 0.35 and line.size() > 2:
					var branch_start: Vector2 = line[randi_range(1, line.size() - 2)]
					line.append_array(generate_branch(Vector2i(branch_start)))
				for p: Vector2 in line:
					var tx: int = chunk_x * CHUNK_SIZE + int(p.x)
					var ty: int = chunk_y * CHUNK_SIZE + int(p.y)
					if tx < 0 or tx >= WIDTH or ty < 0 or ty >= HEIGHT:
						continue
					if grid[tx][ty] != Util.tile.AIR:
						grid[tx][ty] = Util.tile.GOLD

func bresenham_line(a: Vector2, b: Vector2) -> Array[Vector2]:
	var x0: int = int(a.x); var y0: int = int(a.y)
	var x1: int = int(b.x); var y1: int = int(b.y)
	var tiles: Array[Vector2] = []
	var dx: int  =  abs(x1 - x0)
	var dy: int  = -abs(y1 - y0)
	var sx: int  = 1 if x0 < x1 else -1
	var sy: int  = 1 if y0 < y1 else -1
	var err: int = dx + dy
	while true:
		tiles.append(Vector2(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy: err += dy; x0 += sx
		if e2 <= dx: err += dx; y0 += sy
	return tiles

func generate_branch(origin: Vector2, length: int = 4, turn_chance: float = 0.5) -> Array[Vector2]:
	var tiles: Array[Vector2] = []
	var dir: Vector2          = Vector2(1, 0).rotated(randf_range(0, PI * 2))
	var current: Vector2      = Vector2(origin)
	for i in range(length):
		if randf() < turn_chance:
			dir = dir.rotated(randf_range(-0.6, 0.6))
		current += dir.snapped(Vector2(1, 1))
		tiles.append(current)
	return tiles

func generate_rock_variation(grid: Array) -> void:
	for x in range(WIDTH):
		for y in range(HEIGHT):
			var perlin_value: float = rock_variation_noise.get_noise_2d(x, y)
			var dist: float         = sqrt((x - WIDTH / 2.0) ** 2 + (y - HEIGHT / 2.0) ** 2)
			var dist_n: float       = dist / ((WIDTH - BUFFER_TILES) / 2.0)
			var bonus: float        = 0.0
			if dist >= WIDTH / 2.0:
				bonus = (1.0 - ROCK_VARIATION_THRESHOLD) * dist_n
			if perlin_value > (ROCK_VARIATION_THRESHOLD + bonus):
				grid[x][y] = Util.tile.ROCK
				rock_variation_tiles.append(Vector2i(x, y))

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

	var m: float           = randf_range(-2.0, 2.0)
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
		var y: int         = int(floor(y_fault))
		var dist: float    = sqrt((x - WIDTH / 2.0) ** 2 + (y - HEIGHT / 2.0) ** 2)
		var radius: float  = (WIDTH - BUFFER_TILES) / 2.0
		if dist < radius and dist > radius - 16.0:
			candidates.append(Vector2i(x, y))
	for i in range(2):
		if candidates.is_empty():
			break
		var loc: Vector2i = candidates.pop_at(randi_range(0, candidates.size() - 1))
		if new_grid[loc.x][loc.y] != Util.tile.AIR:
			new_grid[loc.x][loc.y] = Util.tile.CRYSTAL
		print("Crystal %d: %d, %d" % [i + 1, loc.x, loc.y])
	return new_grid

func place_copper(grid: Array) -> void:
	for chunk_x in range(0, WIDTH, CHUNK_SIZE):
		for chunk_y in range(0, HEIGHT, CHUNK_SIZE):
			if randf() > COPPER_CHANCE:
				continue
			var seeds: Array[Vector2i] = []
			for x in range(chunk_x, chunk_x + CHUNK_SIZE):
				for y in range(chunk_y, chunk_y + CHUNK_SIZE):
					if x >= WIDTH or y >= HEIGHT:
						continue
					if grid[x][y] == null:
						continue
					if randf() < COPPER_ADD_CHANCE:
						seeds.append(Vector2i(x, y))
			for center: Vector2i in seeds:
				var rx: int = randi_range(COPPER_MIN_RADIUS, COPPER_MAX_RADIUS)
				var ry: int = randi_range(COPPER_MIN_RADIUS, COPPER_MAX_RADIUS)
				for dx in range(-rx, rx + 1):
					for dy in range(-ry, ry + 1):
						var px: int = center.x + dx
						var py: int = center.y + dy
						if px < 0 or px >= WIDTH or py < 0 or py >= HEIGHT:
							continue
						var nx: float = float(dx) / float(rx)
						var ny: float = float(dy) / float(ry)
						if nx * nx + ny * ny <= 1.0 and grid[px][py] != Util.tile.AIR:
							grid[px][py] = Util.tile.COPPER

func is_replaceable(t: Variant) -> bool:
	return t != null and t != Util.tile.AIR and t != Util.tile.CRYSTAL and t != Util.tile.COPPER

# ── distance field shadow calculation ─────────────────────────────────────────
var _df_texture:      ImageTexture     = ImageTexture.new()
var _df_thread:       Thread           = Thread.new()
var _df_pending:      Image            = null
var _df_dirty_chunks: Array[Vector2i]  = []
var _df_running:      bool             = false

const DF_CHUNK_SIZE: int   = 16
const DF_MAX_DEPTH:  float = 5.0

func _initial_df_bake() -> void:
	var img: Image = Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RF)
	var dist: Array = []
	dist.resize(WIDTH * HEIGHT)
	dist.fill(-1.0)
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
			if nb.x < 0 or nb.y < 0 or nb.x >= WIDTH or nb.y >= HEIGHT:
				continue
			if dist[nb.y * WIDTH + nb.x] >= 0.0:
				continue
			dist[nb.y * WIDTH + nb.x] = dist[cur.y * WIDTH + cur.x] + 1.0
			queue.append(nb)
	for x in range(WIDTH):
		for y in range(HEIGHT):
			img.set_pixel(x, y, Color(clampf((dist[y * WIDTH + x] - 1.0) / DF_MAX_DEPTH, 0.0, 1.0), 0, 0, 1))
	_df_texture.set_image(img)
	_set_df_shader_params()

func _set_df_shader_params() -> void:
	var world_origin: Vector2 = map_to_world(Vector2i(0, 0)) - Vector2(TILE_SIZE) / 2.0
	for mat: ShaderMaterial in [multimesh_instance.material, ore_multimesh_instance.material]:
		mat.set_shader_parameter("distance_field",  _df_texture)
		mat.set_shader_parameter("map_size",        Vector2(WIDTH, HEIGHT))
		mat.set_shader_parameter("map_world_origin", world_origin)
		mat.set_shader_parameter("tile_world_size", float(TILE_SIZE.x))
		mat.set_shader_parameter("max_depth",       DF_MAX_DEPTH)
		mat.set_shader_parameter("darkness_power",  1.0)

func _mark_chunk_dirty(map_pos: Vector2i) -> void:
	var chunk: Vector2i = Vector2i(map_pos.x / DF_CHUNK_SIZE, map_pos.y / DF_CHUNK_SIZE)
	if not _df_dirty_chunks.has(chunk):
		_df_dirty_chunks.append(chunk)

func _request_df_update() -> void:
	if _df_running or _df_dirty_chunks.is_empty():
		return
	_df_running = true
	var dirty_copy: Array[Vector2i] = _df_dirty_chunks.duplicate()
	_df_dirty_chunks.clear()
	_df_thread.start(_compute_df_threaded.bind(dirty_copy, tile_types.duplicate()))

func _compute_df_threaded(dirty_chunks: Array[Vector2i], snapshot: Dictionary) -> void:
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
			if nb.x < 0 or nb.y < 0 or nb.x >= rw or nb.y >= rh:
				continue
			if dist[nb.y * rw + nb.x] >= 0.0:
				continue
			dist[nb.y * rw + nb.x] = dist[cur.y * rw + cur.x] + 1.0
			queue.append(nb)

	var img: Image = _df_texture.get_image()
	if img == null or img.get_width() != WIDTH or img.get_height() != HEIGHT:
		img = Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RF)
	for x in range(rw):
		for y in range(rh):
			var d: float = dist[y * rw + x]
			var new_val: float = clampf((d - 1.0) / DF_MAX_DEPTH, 0.0, 1.0) if d >= 0.0 else 0.0
			var old_val: float = img.get_pixel(min_tile.x + x, min_tile.y + y).r
			# only write if new value is darker than current (tile was removed, so only brightening allowed)
			if new_val < old_val:
				img.set_pixel(min_tile.x + x, min_tile.y + y, Color(new_val, 0, 0, 1))
	_df_pending = img

func _process(_delta: float) -> void:
	if _df_pending != null and not _df_thread.is_alive():
		_df_thread.wait_to_finish()
		_df_texture.set_image(_df_pending)
		_df_pending = null
		_df_running = false
		if not _df_dirty_chunks.is_empty():
			_request_df_update()
