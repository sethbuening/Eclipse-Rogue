# navigation_manager.gd
# Autoloaded as "NavManager"
extends Node

@export var agent_radius: float = 8.0
@export var chunk_size:   int   = 16

const REBAKE_DELAY: float = 0.05

var _tilemap_ref:    Node              = null
var _built:          bool              = false
var _map_rid:        RID
var _region:         NavigationRegion2D = null
var _apply_pending:  bool              = false
var _rebake_timer:   float             = 0.0
var _rebake_requested: bool            = false

# chunk_coord → Array[PackedVector2Array]
var _chunk_outlines:  Dictionary = {}
# chunk_coord → float (remaining delay)
var _dirty_chunks:    Dictionary = {}
# chunk_coord → Thread
var _chunk_threads:   Dictionary = {}
var _pending_threads: Dictionary = {}

# ── debug ─────────────────────────────────────────────────────────────────────
var _debug_draw: bool   = false
var _debug_node: Node2D = null

# ── public API ────────────────────────────────────────────────────────────────

func build(tilemap: Node) -> void:
	_tilemap_ref = tilemap
	print("NavManager: initial bake...")
	var cw: int = ceili(float(tilemap.WIDTH)  / chunk_size)
	var ch: int = ceili(float(tilemap.HEIGHT) / chunk_size)

	var threads: Array[Thread] = []
	for cy in range(ch):
		for cx in range(cw):
			var chunk   := Vector2i(cx, cy)
			var thread  := Thread.new()
			var tile_x0 := chunk.x * chunk_size
			var tile_y0 := chunk.y * chunk_size
			var tile_x1 := mini(tile_x0 + chunk_size, tilemap.WIDTH)
			var tile_y1 := mini(tile_y0 + chunk_size, tilemap.HEIGHT)
			var tile_size: Vector2    = Vector2(tilemap.TILE_SIZE)
			var tile_map:  Dictionary = tilemap.tile_types.duplicate()
			var world_map: Dictionary = {}
			for y in range(tile_y0, tile_y1):
				for x in range(tile_x0, tile_x1):
					world_map[Vector2i(x, y)] = tilemap.map_to_world(Vector2i(x, y))
			thread.start(_thread_build_chunk_geometry.bind(
				chunk, tile_x0, tile_y0, tile_x1, tile_y1, tile_size, tile_map, world_map
			))
			threads.append(thread)

	for thread: Thread in threads:
		var result:   Array                     = thread.wait_to_finish()
		var chunk:    Vector2i                  = result[0]
		var outlines: Array[PackedVector2Array] = result[1]
		_chunk_outlines[chunk] = outlines

	await _apply_all_outlines()
	print("NavManager: initial bake done — %d chunks" % _chunk_outlines.size())

func query_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if not _built:
		return PackedVector2Array()
	var params := NavigationPathQueryParameters2D.new()
	params.map              = _map_rid
	params.start_position   = from
	params.target_position  = to
	params.simplify_path    = true
	params.simplify_epsilon = agent_radius * 0.5
	params.metadata_flags   = NavigationPathQueryParameters2D.PathMetadataFlags.PATH_METADATA_INCLUDE_ALL
	var result := NavigationPathQueryResult2D.new()
	NavigationServer2D.query_path(params, result)
	return result.path

func on_tile_removed(map_pos: Vector2i) -> void:
	var chunk := Vector2i(map_pos.x / chunk_size, map_pos.y / chunk_size)
	_dirty_chunks[chunk] = REBAKE_DELAY

func request_rebake() -> void:
	_rebake_requested = true
	_rebake_timer     = REBAKE_DELAY

func toggle_debug_draw() -> void:
	_debug_draw = not _debug_draw
	_draw_navmesh()

# ── process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	for chunk: Vector2i in _dirty_chunks.keys():
		_dirty_chunks[chunk] -= delta
		if _dirty_chunks[chunk] <= 0.0:
			_dirty_chunks.erase(chunk)
			_rebuild_chunk(chunk)

	var any_done: bool = false
	for chunk: Vector2i in _pending_threads.keys():
		var thread: Thread = _pending_threads[chunk]
		if not thread.is_alive():
			var result:   Array                     = thread.wait_to_finish()
			var outlines: Array[PackedVector2Array] = result[1]
			_chunk_outlines[chunk] = outlines
			_chunk_threads.erase(chunk)
			_pending_threads.erase(chunk)
			any_done = true

	if any_done and not _apply_pending:
		_apply_all_outlines()

	if _rebake_requested and _built:
		_rebake_timer -= delta
		if _rebake_timer <= 0.0:
			_rebake_requested = false
			_apply_all_outlines()

# ── partial rebuild ───────────────────────────────────────────────────────────

func _rebuild_chunk(chunk: Vector2i) -> void:
	if _chunk_threads.has(chunk):
		var old_thread: Thread = _chunk_threads[chunk]
		if old_thread.is_started():
			old_thread.wait_to_finish()
		_chunk_threads.erase(chunk)

	var tile_x0:   int        = chunk.x * chunk_size
	var tile_y0:   int        = chunk.y * chunk_size
	var tile_x1:   int        = mini(tile_x0 + chunk_size, _tilemap_ref.WIDTH)
	var tile_y1:   int        = mini(tile_y0 + chunk_size, _tilemap_ref.HEIGHT)
	var tile_size: Vector2    = Vector2(_tilemap_ref.TILE_SIZE)
	var tile_map:  Dictionary = _tilemap_ref.tile_types.duplicate()
	var world_map: Dictionary = {}
	for y in range(tile_y0, tile_y1):
		for x in range(tile_x0, tile_x1):
			world_map[Vector2i(x, y)] = _tilemap_ref.map_to_world(Vector2i(x, y))

	var thread := Thread.new()
	_chunk_threads[chunk]  = thread
	_pending_threads[chunk] = thread
	thread.start(_thread_build_chunk_geometry.bind(
		chunk, tile_x0, tile_y0, tile_x1, tile_y1, tile_size, tile_map, world_map
	))

# ── bake ──────────────────────────────────────────────────────────────────────

func _apply_all_outlines() -> void:
	if _apply_pending:
		return
	_apply_pending = true

	var nav_poly := NavigationPolygon.new()
	nav_poly.agent_radius         = agent_radius
	nav_poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN

	for outlines: Array in _chunk_outlines.values():
		for outline: PackedVector2Array in outlines:
			nav_poly.add_outline(outline)

	# Obstacle cutouts — reversed to CCW so the baker treats them as holes
	for obs in get_tree().get_nodes_in_group("nav_obstacles"):
		if not obs.has_method("get_world_outline"):
			continue
		var outline: PackedVector2Array = obs.get_world_outline()
		if outline.size() < 3:
			continue
		outline.reverse()
		nav_poly.add_outline(outline)

	NavigationServer2D.bake_from_source_geometry_data(
		nav_poly,
		NavigationMeshSourceGeometryData2D.new()
	)

	if _region == null or not is_instance_valid(_region):
		_region      = NavigationRegion2D.new()
		_region.name = "NavRegion"
		add_child(_region)

	_region.navigation_polygon = nav_poly

	await get_tree().process_frame

	_map_rid       = _region.get_navigation_map()
	_built         = true
	_apply_pending = false

	print("NavManager: applied — polygons: %d  map valid: %s" % [
		nav_poly.get_polygon_count(), _map_rid.is_valid()
	])
	_draw_navmesh()

# ── threaded geometry build ───────────────────────────────────────────────────

func _thread_build_chunk_geometry(
	chunk:     Vector2i,
	x0:        int,
	y0:        int,
	x1:        int,
	y1:        int,
	tile_size: Vector2,
	tile_map:  Dictionary,
	world_map: Dictionary
) -> Array:
	var half:     Vector2                   = tile_size * 0.5
	var covered:  Dictionary                = {}
	var outlines: Array[PackedVector2Array] = []

	for y in range(y0, y1):
		var x: int = x0
		while x < x1:
			var pos := Vector2i(x, y)
			if tile_map.has(pos) or covered.has(pos):
				x += 1
				continue

			var rx1: int = x
			while rx1 < x1 and not tile_map.has(Vector2i(rx1, y)) and not covered.has(Vector2i(rx1, y)):
				rx1 += 1

			var ry1: int = y + 1
			while ry1 < y1:
				var row_clear: bool = true
				for cx in range(x, rx1):
					if tile_map.has(Vector2i(cx, ry1)) or covered.has(Vector2i(cx, ry1)):
						row_clear = false
						break
				if not row_clear:
					break
				ry1 += 1

			for cy in range(y, ry1):
				for cx in range(x, rx1):
					covered[Vector2i(cx, cy)] = true

			var world_tl: Vector2 = world_map[Vector2i(x,       y)]       - half
			var world_br: Vector2 = world_map[Vector2i(rx1 - 1, ry1 - 1)] + half
			outlines.append(PackedVector2Array([
				world_tl,
				Vector2(world_br.x, world_tl.y),
				world_br,
				Vector2(world_tl.x, world_br.y),
			]))
			x = rx1

	return [chunk, outlines]

# ── debug draw ────────────────────────────────────────────────────────────────

class NavDebugDraw extends Node2D:
	var poly_verts: PackedVector2Array = PackedVector2Array()
	var polygons:   Array              = []

	func _draw() -> void:
		for p_idx in range(polygons.size()):
			var poly:   PackedInt32Array   = polygons[p_idx]
			var points: PackedVector2Array = PackedVector2Array()
			for vi in poly:
				points.append(poly_verts[vi])
			draw_colored_polygon(points, Color(0.0, 0.8, 1.0, 0.08))
			for e in range(points.size()):
				draw_line(
					points[e],
					points[(e + 1) % points.size()],
					Color(0.0, 1.0, 1.0, 0.4),
					1.0
				)

func _draw_navmesh() -> void:
	if _debug_node != null:
		_debug_node.queue_free()
		_debug_node = null

	if not _debug_draw or not _built or _region == null or _region.navigation_polygon == null:
		return

	var nav_poly: NavigationPolygon = _region.navigation_polygon
	var drawer := NavDebugDraw.new()
	drawer.name          = "NavMeshDebug"
	drawer.z_index       = 4096
	drawer.z_as_relative = false
	drawer.poly_verts    = nav_poly.get_vertices()
	drawer.polygons      = []
	for p in range(nav_poly.get_polygon_count()):
		drawer.polygons.append(nav_poly.get_polygon(p))

	_debug_node = drawer
	get_tree().root.add_child(_debug_node)
