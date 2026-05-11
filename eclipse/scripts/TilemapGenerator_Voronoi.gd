extends Node

var map_seed: int

@export_group("Proc Gen Parameters")
@export_subgroup("Map Sizing")
@export_multiline var note: String = "WIDTH and HEIGHT must be divisible by 16 since CHUNK_SIZE is WIDTH/16"
@export var WIDTH:  int = 256 + 32
@export var HEIGHT: int = 256 + 32
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

@export_subgroup("Rock Variation")
@export var ROCK_VARIATION_THRESHOLD: float = 0.01
@export var ROCK_VARIATION_FREQUENCY: float = 0.025

@export var BUFFER_TILES: int = 32

# ================================================================ VORONOI ====
# Two independent visual effects driven by the Voronoi graph:
#
#  1. COLOUR MODULATION  (INSTANCE_COLOR)
#     Each Voronoi region tints its tiles a slightly different stone hue.
#     Tiles near seam edges are darkened to simulate natural rock cracking.
#
#  2. FACE BOUNDARY HEIGHT  (INSTANCE_CUSTOM .b / .a)
#     The dividing line between the flat "top face" and the vertical "front
#     face" of each 32x48 tile is not a flat horizontal line — it follows
#     the Voronoi graph, so adjacent rock chunks appear to be at different
#     heights, like chunky irregular boulders (DRG-style).
#
#     The shader reads the left/right boundary height per instance and
#     interpolates it across the tile horizontally.  Because sampling is
#     nearest-neighbour throughout, the result stays crisp and pixelated.
#
# Parameters are exposed as @export vars so you can tune them live in the
# Godot inspector without recompiling.

@export_group("Voronoi Stone Variation")

@export_subgroup("Seed Distribution")
## Average tile spacing between Voronoi seed points.
## Smaller = finer, more fragmented rock chunks.  Range 10-40.  Default 18.
@export var VORONOI_SEED_SPACING: int   = 18
## 0 = perfect grid (boxy Voronoi), 1 = fully random scatter.  Default 0.80.
@export var VORONOI_JITTER:       float = 0.80

@export_subgroup("Colour Modulation")
## Brightness of tiles exactly on a seam (0 = black, 1 = unchanged).
@export var VORONOI_EDGE_DARKNESS:   float = 0.60
## How quickly seam darkening falls off outward.  Higher = thinner seam lines.
@export var VORONOI_EDGE_SHARPNESS:  float = 10.0
## Strength of the per-region stone hue tint.  0 = no tint.
@export var VORONOI_TINT_STRENGTH:   float = 0.07

@export_subgroup("Face Boundary Height")
## Neutral boundary Y within the tile's top face (0 = very top, 1 = very bottom).
## 0.55 gives moderate front-face visibility.
@export var VORONOI_BOUNDARY_NEUTRAL:   float = 0.55
## Maximum deviation from neutral driven by per-region height variation.
## Higher = taller height differences between adjacent rock chunks.
@export var VORONOI_BOUNDARY_AMPLITUDE: float = 0.30
## How sharply the boundary steps at a Voronoi seam.
## 1 = smooth gradient, higher = harder pixel-art step.  Default 3.5.
@export var VORONOI_BOUNDARY_CONTRAST:  float = 3.5

# Internal Voronoi state — populated once in _build_voronoi().
var _voronoi_seeds:          PackedVector2Array = []
var _voronoi_region_tints:   Array[Color]       = []
var _voronoi_region_heights: Array[float]       = []

var gold_tiles_added:   int = 0
var copper_tiles_added: int = 0

@export_group("Rendering")
@export var tile_atlas:      Texture2D
@export var ATLAS_TILE_SIZE: Vector2i = Vector2i(32, 48)
var SPRITE_OFFSET_Y: float = 0

@export var atlas_pos_stone:   Vector2i = Vector2i(1, 2)
@export var atlas_pos_rock:    Vector2i = Vector2i(1, 5)
@export var atlas_pos_gold:    Vector2i = Vector2i(4, 2)
@export var atlas_pos_copper:  Vector2i = Vector2i(4, 5)
@export var atlas_pos_crystal: Vector2i = Vector2i(7, 2)

var chamber_noise:        FastNoiseLite = FastNoiseLite.new()
var path_noise:           FastNoiseLite = FastNoiseLite.new()
var rock_variation_noise: FastNoiseLite = FastNoiseLite.new()

var rock_variation_tiles: Array[Vector2i] = []

var tile_types:  Dictionary = {}
var tile_health: Dictionary = {}
var tile_shapes: Dictionary = {}

var static_body: StaticBody2D

var multimesh:           MultiMesh
var multimesh_instance:  MultiMeshInstance2D
var tile_instance_index: Dictionary = {}

# ----------------------------------------------------------------- ready ----
func _ready() -> void:
	SPRITE_OFFSET_Y = (ATLAS_TILE_SIZE.y - TILE_SIZE.y) / 2.0
	map_seed        = randi()

	_setup_noise(chamber_noise,        PERLIN_CHAMBER_FREQUENCY)
	_setup_noise(path_noise,           PERLIN_PATH_FREQUENCY)
	_setup_noise(rock_variation_noise, ROCK_VARIATION_FREQUENCY)

	_build_voronoi()

	var tilemap: Array[Array] = []
	for x: int in range(WIDTH):
		tilemap.append([])
		for y: int in range(HEIGHT):
			tilemap[x].append(Util.tile.STONE)

	generate_rock_variation(tilemap)
	generate_ores(tilemap)
	tilemap = generate_faults(tilemap)
	generate_chamber_noise(tilemap)
	generate_path_noise(tilemap)
	for i: int in range(6):
		tilemap = cellular_step(tilemap)
	place_starting_area(tilemap)

	for x: int in range(WIDTH):
		for y: int in range(HEIGHT):
			var dist: float = sqrt((x - WIDTH / 2.0) ** 2 + (y - HEIGHT / 2.0) ** 2)
			if dist >= (WIDTH - BUFFER_TILES) / 2.0:
				continue
			var t: Util.tile = tilemap[x][y]
			if t == null or t == Util.tile.AIR:
				continue
			var map_pos: Vector2i = Vector2i(x, y)
			tile_types[map_pos]   = t
			tile_health[map_pos]  = get_tile_max_health(t)
			if t == Util.tile.COPPER:
				copper_tiles_added += 1
			elif t == Util.tile.GOLD:
				gold_tiles_added   += 1

	print("Generated %d gold tiles"   % gold_tiles_added)
	print("Generated %d copper tiles" % copper_tiles_added)

	_setup_rendering()
	_build_collision()
	_setup_occluder()

func _setup_noise(noise: FastNoiseLite, frequency: float) -> void:
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed       = map_seed
	noise.frequency  = frequency

# ============================================================= Voronoi impl =

func _build_voronoi() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed ^ 0xDEADBEEF

	var cols: int = ceili(float(WIDTH)  / VORONOI_SEED_SPACING)
	var rows: int = ceili(float(HEIGHT) / VORONOI_SEED_SPACING)

	_voronoi_seeds.clear()
	_voronoi_region_tints.clear()
	_voronoi_region_heights.clear()

	for row: int in range(rows):
		for col: int in range(cols):
			var base_x:   float = (col + 0.5) * VORONOI_SEED_SPACING
			var base_y:   float = (row + 0.5) * VORONOI_SEED_SPACING
			var jitter_r: float = VORONOI_SEED_SPACING * 0.5 * VORONOI_JITTER
			_voronoi_seeds.append(Vector2(
				base_x + rng.randf_range(-jitter_r, jitter_r),
				base_y + rng.randf_range(-jitter_r, jitter_r)
			))
			_voronoi_region_tints.append(_pick_stone_tint(rng))
			_voronoi_region_heights.append(rng.randf_range(-1.0, 1.0))

func _pick_stone_tint(rng: RandomNumberGenerator) -> Color:
	var palette: Array[Color] = [
		Color(0.44, 0.444, 0.443, 1.0),  # neutral (weighted ×4)
	]
	return palette[rng.randi() % palette.size()]

# Core Voronoi query: returns F1, F2 distances and nearest region index for
# an arbitrary world-space position.  Uses a 5x5 neighbourhood search so
# jitter can never cause a miss even at high jitter values.
func _voronoi_query(px: float, py: float) -> Dictionary:
	var f1:  float = INF
	var f2:  float = INF
	var idx: int   = 0
	var cols: int  = ceili(float(WIDTH)  / VORONOI_SEED_SPACING)
	var rows: int  = ceili(float(HEIGHT) / VORONOI_SEED_SPACING)
	var cc:   int  = int(px / VORONOI_SEED_SPACING)
	var cr:   int  = int(py / VORONOI_SEED_SPACING)
	for dr: int in range(-2, 3):
		for dc: int in range(-2, 3):
			var nc: int = cc + dc
			var nr: int = cr + dr
			if nc < 0 or nc >= cols or nr < 0 or nr >= rows:
				continue
			var si: int = nr * cols + nc
			if si >= _voronoi_seeds.size():
				continue
			var seed: Vector2 = _voronoi_seeds[si]
			var d2: float     = (px - seed.x) * (px - seed.x) + (py - seed.y) * (py - seed.y)
			if d2 < f1:
				f2 = f1; f1 = d2; idx = si
			elif d2 < f2:
				f2 = d2
	return { "f1": sqrt(f1), "f2": sqrt(f2), "region": idx }

# ---- Colour modulation --------------------------------------------------

func _voronoi_color_for(map_pos: Vector2i, tile_type: Util.tile) -> Color:
	var q:      Dictionary = _voronoi_query(float(map_pos.x), float(map_pos.y))
	var f1:     float      = q["f1"]
	var f2:     float      = q["f2"]
	var region: int        = q["region"]

	var edge_factor: float = 0.0
	if f2 > 0.001:
		edge_factor = clamp(1.0 - f1 / f2, 0.0, 1.0)

	var darkness:   float = pow(edge_factor, VORONOI_EDGE_SHARPNESS)
	var brightness: float = lerp(1.0, VORONOI_EDGE_DARKNESS, darkness)

	var tint: Color = Color.WHITE
	if tile_type == Util.tile.STONE or tile_type == Util.tile.ROCK:
		if region < _voronoi_region_tints.size():
			tint = Color.WHITE.lerp(_voronoi_region_tints[region], VORONOI_TINT_STRENGTH)
	else:
		# Ores get only a faint edge hint — don't muddy their colours.
		brightness = lerp(1.0, VORONOI_EDGE_DARKNESS, darkness * 0.25)

	return Color(tint.r * brightness, tint.g * brightness, tint.b * brightness, 1.0)

# ---- Face boundary height -----------------------------------------------
# Returns the face-boundary Y value [0..1 within the tile's top face] for
# any world-space position.  The result is sharpened by VORONOI_BOUNDARY_CONTRAST
# to produce a crisp pixel-art step at Voronoi seams while remaining driven
# by the smooth underlying field.

func _boundary_at(world_x: float, world_y: float) -> float:
	var q:      Dictionary = _voronoi_query(world_x, world_y)
	var f1:     float      = q["f1"]
	var f2:     float      = q["f2"]
	var region: int        = q["region"]

	# blend = 0 at cell centre, 1 at the exact seam midpoint.
	var blend: float = 0.0
	if f1 + f2 > 0.001:
		blend = clamp(f1 / (f1 + f2) * 2.0, 0.0, 1.0)
	# Raise to VORONOI_BOUNDARY_CONTRAST to push the gradient toward a hard step.
	blend = pow(blend, VORONOI_BOUNDARY_CONTRAST)

	var h: float = 0.0
	if region < _voronoi_region_heights.size():
		h = _voronoi_region_heights[region]

	# At the seam, blend toward the neutral value so the step is sharp but
	# doesn't create an impossible discontinuity.
	var boundary: float = VORONOI_BOUNDARY_NEUTRAL + h * VORONOI_BOUNDARY_AMPLITUDE
	boundary = lerp(boundary, VORONOI_BOUNDARY_NEUTRAL, blend)
	return clamp(boundary, 0.05, 0.95)

# Samples boundary at the left-quarter and right-quarter of a tile so the
# shader can interpolate smoothly (but still pixelated) across the width.
func _boundary_lr(map_pos: Vector2i) -> Vector2:
	var y: float = float(map_pos.y) + 0.5
	return Vector2(
		_boundary_at(float(map_pos.x) + 0.25, y),
		_boundary_at(float(map_pos.x) + 0.75, y)
	)

# ============================================================= /Voronoi ====

# ------------------------------------------------------------ rendering ----
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
	%TilemapManager.add_child(static_body)

	multimesh                  = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors       = true
	multimesh.use_custom_data  = true
	multimesh.mesh             = _make_quad_mesh()
	multimesh.instance_count   = tile_types.size()

	multimesh_instance           = MultiMeshInstance2D.new()
	multimesh_instance.scale     = get_parent().scale
	multimesh_instance.multimesh = multimesh
	multimesh_instance.texture   = tile_atlas

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/MultiMesh.gdshader")
	mat.set_shader_parameter("atlas",       tile_atlas)
	mat.set_shader_parameter("sprite_size", Vector2(ATLAS_TILE_SIZE))
	var voronoi_textures := _pack_voronoi_textures()
	var cols: int = ceili(float(WIDTH)  / VORONOI_SEED_SPACING)
	var rows: int = ceili(float(HEIGHT) / VORONOI_SEED_SPACING)
	mat.set_shader_parameter("voronoi_seeds_tex",          voronoi_textures[0])
	mat.set_shader_parameter("voronoi_tints_tex",          voronoi_textures[1])
	mat.set_shader_parameter("voronoi_seed_count",         _voronoi_seeds.size())
	mat.set_shader_parameter("voronoi_cols",               cols)
	mat.set_shader_parameter("voronoi_rows",               rows)
	mat.set_shader_parameter("voronoi_seed_spacing",       float(VORONOI_SEED_SPACING))
	mat.set_shader_parameter("voronoi_edge_darkness",      VORONOI_EDGE_DARKNESS)
	mat.set_shader_parameter("voronoi_edge_sharpness",     VORONOI_EDGE_SHARPNESS)
	mat.set_shader_parameter("voronoi_tint_strength",      VORONOI_TINT_STRENGTH)
	mat.set_shader_parameter("voronoi_boundary_neutral",   VORONOI_BOUNDARY_NEUTRAL)
	mat.set_shader_parameter("voronoi_boundary_amplitude", VORONOI_BOUNDARY_AMPLITUDE)
	mat.set_shader_parameter("voronoi_boundary_contrast",  VORONOI_BOUNDARY_CONTRAST)
	multimesh_instance.material = mat

	multimesh_instance.z_index       = -1
	multimesh_instance.z_as_relative = false

	%TilemapManager.add_child(multimesh_instance)

	var sorted_tiles: Array = tile_types.keys()
	sorted_tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y)

	var idx: int = 0
	for map_pos: Vector2i in sorted_tiles:
		tile_instance_index[map_pos] = idx
		_write_instance(idx, map_pos)
		idx += 1

# INSTANCE_CUSTOM layout:
#   .r = atlas origin X (normalised 0..1 over full atlas width)
#   .g = atlas origin Y (normalised 0..1 over full atlas height)
#   .b = Voronoi face-boundary height, left  side of tile [0..1]
#   .a = Voronoi face-boundary height, right side of tile [0..1]
#
# The previous layout stored a full Rect2 (origin + size).  Since the sprite
# size is now a shader uniform, we only need the origin — freeing .b/.a for
# the Voronoi boundary heights that drive the face-split effect.
func _write_instance(idx: int, map_pos: Vector2i) -> void:
	@warning_ignore("integer_division")
	var world_pos: Vector2 = Vector2((map_pos - Vector2i(WIDTH / 2, HEIGHT / 2)) * TILE_SIZE) \
						   + Vector2(TILE_SIZE) / 2.0
	world_pos.y -= SPRITE_OFFSET_Y

	var xf: Transform2D = Transform2D(0.0, Vector2(1.0, -1.0), 0.0, world_pos)
	multimesh.set_instance_transform_2d(idx, xf)

	var tile_type: Util.tile = tile_types[map_pos]
	multimesh.set_instance_color(idx, _voronoi_color_for(map_pos, tile_type))

	var atlas_px:  Vector2   = Vector2(tile_atlas.get_size()) if tile_atlas else Vector2(128.0, 192.0)
	var apos:      Vector2i  = _atlas_pos_for(tile_types[map_pos])
	var uv_origin: Vector2   = Vector2(apos * ATLAS_TILE_SIZE) / atlas_px

	multimesh.set_instance_custom_data(idx, Color(
		uv_origin.x,
		uv_origin.y,
		float(map_pos.x),
		float(map_pos.y)
	))

func _atlas_pos_for(t: Util.tile) -> Vector2i:
	match t:
		Util.tile.STONE:   return atlas_pos_stone
		Util.tile.ROCK:    return atlas_pos_rock
		Util.tile.GOLD:    return atlas_pos_gold
		Util.tile.COPPER:  return atlas_pos_copper
		Util.tile.CRYSTAL: return atlas_pos_crystal
		_:                 return atlas_pos_stone

func _hide_instance(map_pos: Vector2i) -> void:
	if not tile_instance_index.has(map_pos):
		return
	var xf: Transform2D = Transform2D.IDENTITY
	xf.origin           = Vector2(-999999, -999999)
	multimesh.set_instance_transform_2d(tile_instance_index[map_pos], xf)

func get_tile_uv(t: Util.tile) -> Rect2:
	var atlas_px:  Vector2  = Vector2(tile_atlas.get_size()) if tile_atlas else Vector2(128.0, 192.0)
	var uv_origin: Vector2  = Vector2(_atlas_pos_for(t) * ATLAS_TILE_SIZE) / atlas_px
	var uv_size:   Vector2  = Vector2(ATLAS_TILE_SIZE) / atlas_px
	return Rect2(uv_origin, uv_size)

func _get_atlas_rect(t: Util.tile) -> Rect2:
	return Rect2(Vector2(_atlas_pos_for(t) * ATLAS_TILE_SIZE), Vector2(ATLAS_TILE_SIZE))

func set_tile_color(map_pos: Vector2i, color: Color) -> void:
	if not tile_instance_index.has(map_pos):
		return
	multimesh.set_instance_color(tile_instance_index[map_pos], color)
	if occluder_sprites.has(map_pos):
		occluder_sprites[map_pos].modulate = color

func get_tile_color(map_pos: Vector2i) -> Color:
	if not tile_instance_index.has(map_pos):
		return Color.WHITE
	return multimesh.get_instance_color(tile_instance_index[map_pos])

func redraw_tile(map_pos: Vector2i) -> void:
	if not tile_instance_index.has(map_pos):
		return
	_write_instance(tile_instance_index[map_pos], map_pos)

func _pack_voronoi_textures() -> Array:
	var n: int = _voronoi_seeds.size()
	var seeds_img: Image = Image.create(n, 1, false, Image.FORMAT_RGBAF)
	var tints_img: Image = Image.create(n, 1, false, Image.FORMAT_RGBA8)
	for i: int in range(n):
		seeds_img.set_pixel(i, 0, Color(
			_voronoi_seeds[i].x,
			_voronoi_seeds[i].y,
			_voronoi_region_heights[i],
			1.0
		))
		tints_img.set_pixel(i, 0, _voronoi_region_tints[i])
	return [
		ImageTexture.create_from_image(seeds_img),
		ImageTexture.create_from_image(tints_img)
	]

# ------------------------------------------------------------ occluder ----
var occluder_sprites: Dictionary = {}

func _setup_occluder() -> void:
	for map_pos: Vector2i in tile_types.keys():
		var above: Vector2i = map_pos + Vector2i(0, -1)
		if is_air(above):
			_add_occluder_sprite(map_pos)

func _add_occluder_sprite(map_pos: Vector2i) -> void:
	if occluder_sprites.has(map_pos):
		return
	var world_center: Vector2 = map_to_world(map_pos)
	var sprite             := Sprite2D.new()
	sprite.texture          = tile_atlas
	sprite.region_enabled   = true
	sprite.region_rect      = _get_atlas_rect(tile_types[map_pos])
	sprite.z_as_relative    = false
	sprite.position         = Vector2(world_center.x, world_center.y - SPRITE_OFFSET_Y - ATLAS_TILE_SIZE.y / 2.0)
	sprite.offset           = Vector2(0, ATLAS_TILE_SIZE.y / 2.0)
	sprite.modulate         = get_tile_color(map_pos)
	occluder_sprites[map_pos] = sprite
	get_parent().add_child.call_deferred(sprite)

func _remove_occluder_sprite(map_pos: Vector2i) -> void:
	if not occluder_sprites.has(map_pos):
		return
	occluder_sprites[map_pos].queue_free()
	occluder_sprites.erase(map_pos)

func update_occluder_depths(player: Node2D) -> void:
	var player_map := world_to_map(player.global_position)
	for map_pos: Vector2i in occluder_sprites:
		var sprite: Sprite2D = occluder_sprites[map_pos]
		sprite.z_index = 1 if player_map.y <= map_pos.y else -1

# ------------------------------------------------------------ collision ----
func _build_collision() -> void:
	for map_pos: Vector2i in tile_types.keys():
		_add_collision_shape(map_pos)

func _add_collision_shape(map_pos: Vector2i) -> void:
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size                  = Vector2(TILE_SIZE)
	var col: CollisionShape2D   = CollisionShape2D.new()
	col.shape                   = shape
	@warning_ignore("integer_division")
	col.position     = Vector2((map_pos - Vector2i(WIDTH / 2, HEIGHT / 2)) * TILE_SIZE) + Vector2(TILE_SIZE) / 2.0
	static_body.add_child(col)
	tile_shapes[map_pos] = col

# ------------------------------------------------------------ mining -------
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

func damage_tile(map_pos: Vector2i, damage: int = 1) -> void:
	if not tile_health.has(map_pos):
		return
	tile_health[map_pos] -= damage
	if tile_health[map_pos] <= 0:
		remove_tile(map_pos)

func remove_tile(map_pos: Vector2i) -> void:
	if not tile_types.has(map_pos):
		return
	_hide_instance(map_pos)
	_remove_occluder_sprite(map_pos)
	tile_health.erase(map_pos)
	tile_types.erase(map_pos)
	tile_shapes[map_pos].disabled = true
	var below: Vector2i = map_pos + Vector2i(0, 1)
	if tile_types.has(below) and not occluder_sprites.has(below):
		_add_occluder_sprite(below)

func in_bounds(loc: Vector2i) -> bool:
	return loc.x >= 0 and loc.x < WIDTH and loc.y >= 0 and loc.y < HEIGHT

# --------------------------------------------------------- proc gen --------
func generate_chamber_noise(grid: Array) -> void:
	for x: int in range(WIDTH):
		for y: int in range(HEIGHT):
			var perlin_value: float = chamber_noise.get_noise_2d(x, y)
			var dist:         float = sqrt((x - WIDTH / 2.0) ** 2 + (y - HEIGHT / 2.0) ** 2)
			var dist_n:       float = dist / ((WIDTH - BUFFER_TILES) / 2.0)
			var bonus:        float = 0.0
			if dist > (WIDTH - BUFFER_TILES) / 3.0:
				bonus = (1.0 - PERLIN_CHAMBER_THRESHOLD) * dist_n
			if perlin_value > (PERLIN_CHAMBER_THRESHOLD + bonus) and is_replaceable(grid[x][y]):
				grid[x][y] = Util.tile.AIR

func generate_path_noise(grid: Array) -> void:
	for x: int in range(WIDTH):
		for y: int in range(HEIGHT):
			var perlin_value: float = path_noise.get_noise_2d(x, y)
			var dist:         float = sqrt((x - WIDTH / 2.0) ** 2 + (y - HEIGHT / 2.0) ** 2)
			var dist_n:       float = dist / ((WIDTH - BUFFER_TILES) / 2.0)
			var bonus:        float = 0.0
			if dist > 2.0 * (WIDTH - BUFFER_TILES) / 5.0:
				bonus = PERLIN_PATH_THRESHOLD * dist_n
			if absf(perlin_value) < (PERLIN_PATH_THRESHOLD - bonus) and is_replaceable(grid[x][y]):
				grid[x][y] = Util.tile.AIR

func count_neighbors(grid: Array, x: int, y: int) -> int:
	var count: int = 0
	for nx: int in range(x - 1, x + 2):
		for ny: int in range(y - 1, y + 2):
			if nx == x and ny == y:
				continue
			if nx >= 0 and nx < WIDTH and ny >= 0 and ny < HEIGHT:
				if grid[nx][ny] == Util.tile.AIR:
					count += 1
	return count

func cellular_step(grid: Array) -> Array[Array]:
	var new_grid: Array[Array] = []
	for x: int in range(WIDTH):
		new_grid.append([])
		for y: int in range(HEIGHT):
			var alive:     bool = grid[x][y] == Util.tile.AIR
			var neighbors: int  = count_neighbors(grid, x, y)
			if alive:
				if neighbors < CELL_DEATH_THRESHOLD:
					var neighbor_value: Variant = null
					for _x: int in range(-1, 2):
						for _y: int in range(-1, 2):
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
	for x: int in range(x_mid - STARTING_AREA_RADIUS, x_mid + STARTING_AREA_RADIUS + 1):
		for y: int in range(y_mid - STARTING_AREA_RADIUS, y_mid + STARTING_AREA_RADIUS + 1):
			if sqrt((x - x_mid) ** 2 + (y - y_mid) ** 2) <= STARTING_AREA_RADIUS:
				grid[x][y] = Util.tile.AIR

func generate_ores(grid: Array) -> void:
	place_gold(grid)
	place_copper(grid)

func place_gold(grid: Array) -> void:
	@warning_ignore("integer_division")
	for chunk_x: int in range(WIDTH / CHUNK_SIZE):
		@warning_ignore("integer_division")
		for chunk_y: int in range(HEIGHT / CHUNK_SIZE):
			if randf() >= CHUNK_CHANCE:
				continue
			var points: Array[Vector2i] = []
			for _x: int in range(CHUNK_SIZE):
				for _y: int in range(CHUNK_SIZE):
					if randf() < ADD_POINT_CHANCE:
						points.append(Vector2i(_x, _y))
			if points.size() < 2:
				continue
			if randf() < 0.5:
				points.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
			else:
				points.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y)
			for i: int in range(points.size() - 1):
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
	for i: int in range(length):
		if randf() < turn_chance:
			dir = dir.rotated(randf_range(-0.6, 0.6))
		current += dir.snapped(Vector2(1, 1))
		tiles.append(current)
	return tiles

func generate_rock_variation(grid: Array) -> void:
	for x: int in range(WIDTH):
		for y: int in range(HEIGHT):
			var perlin_value: float = rock_variation_noise.get_noise_2d(x, y)
			var dist:         float = sqrt((x - WIDTH / 2.0) ** 2 + (y - HEIGHT / 2.0) ** 2)
			var dist_n:       float = dist / ((WIDTH - BUFFER_TILES) / 2.0)
			var bonus:        float = 0.0
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

	var m:         float   = randf_range(-2.0, 2.0)
	var fault_dir: Vector2 = Vector2(1.0 / sqrt(1.0 + m ** 2), m / sqrt(1.0 + m ** 2))
	var magnitude: float   = randf_range(16.0, 32.0)
	print("Fault magnitude: %.2f" % magnitude)

	for x: int in range(WIDTH):
		new_grid.append([])
		var y_fault: float = m * (x - fault_point.x) + fault_point.y
		for y: int in range(HEIGHT):
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
	for x: int in range(WIDTH):
		var y_fault: float = m * (x - fault_point.x) + fault_point.y
		var y:       int   = int(floor(y_fault))
		var dist:    float = sqrt((x - WIDTH / 2.0) ** 2 + (y - HEIGHT / 2.0) ** 2)
		var radius:  float = (WIDTH - BUFFER_TILES) / 2.0
		if dist < radius and dist > radius - 16.0:
			candidates.append(Vector2i(x, y))
	for i: int in range(2):
		if candidates.is_empty(): break
		var loc: Vector2i = candidates.pop_at(randi_range(0, candidates.size() - 1))
		if new_grid[loc.x][loc.y] != Util.tile.AIR:
			new_grid[loc.x][loc.y] = Util.tile.CRYSTAL
		print("Crystal %d: %d, %d" % [i + 1, loc.x, loc.y])
	return new_grid

func place_copper(grid: Array) -> void:
	for chunk_x: int in range(0, WIDTH, CHUNK_SIZE):
		for chunk_y: int in range(0, HEIGHT, CHUNK_SIZE):
			if randf() > COPPER_CHANCE:
				continue
			var seeds: Array[Vector2i] = []
			for x: int in range(chunk_x, chunk_x + CHUNK_SIZE):
				for y: int in range(chunk_y, chunk_y + CHUNK_SIZE):
					if x >= WIDTH or y >= HEIGHT: continue
					if grid[x][y] == null: continue
					if randf() < COPPER_ADD_CHANCE:
						seeds.append(Vector2i(x, y))
			for center: Vector2i in seeds:
				var rx: int = randi_range(COPPER_MIN_RADIUS, COPPER_MAX_RADIUS)
				var ry: int = randi_range(COPPER_MIN_RADIUS, COPPER_MAX_RADIUS)
				for dx: int in range(-rx, rx + 1):
					for dy: int in range(-ry, ry + 1):
						var px: int   = center.x + dx
						var py: int   = center.y + dy
						if px < 0 or px >= WIDTH or py < 0 or py >= HEIGHT: continue
						var nx: float = float(dx) / float(rx)
						var ny: float = float(dy) / float(ry)
						if nx * nx + ny * ny <= 1.0 and grid[px][py] != Util.tile.AIR:
							grid[px][py] = Util.tile.COPPER

func is_replaceable(t: Variant) -> bool:
	return t != null and t != Util.tile.AIR and t != Util.tile.CRYSTAL and t != Util.tile.COPPER
