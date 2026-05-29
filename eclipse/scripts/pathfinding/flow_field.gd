# flow_field.gd
# Autoloaded as "FlowField"
# Dijkstra expansion from the player outward, rebuilt on a background thread.
# All standard enemies call get_direction() — O(1) per enemy per frame.
extends Node

const UPDATE_INTERVAL: float = 0.3

var _flow:     Dictionary = {}
var _timer:    float      = 0.0
var _target:   Vector2    = Vector2.ZERO
var _built:    bool       = false
var _tilemap:  Node       = null

var _rebuild_thread: Thread = null
var _rebuilding:     bool   = false

# ── public API ────────────────────────────────────────────────────────────────

func initialize(tilemap: Node) -> void:
	_tilemap = tilemap
	_built   = false

func set_target(world_pos: Vector2) -> void:
	_target = world_pos

func is_ready() -> bool:
	return _built

func get_direction(world_pos: Vector2, radius: float = 0.0) -> Vector2:
	if not _built:
		return Vector2.ZERO

	var sample: Vector2 = world_pos
	if radius > 0.0:
		var current_dir: Vector2 = _flow.get(_world_to_cell(world_pos), Vector2.ZERO)
		if current_dir != Vector2.ZERO:
			sample = world_pos + current_dir * radius * 0.5

	var dir: Vector2 = _flow.get(_world_to_cell(sample), Vector2.ZERO)
	if dir == Vector2.ZERO:
		dir = _flow.get(_world_to_cell(world_pos), Vector2.ZERO)
	return dir

# ── process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _rebuilding and _rebuild_thread != null and not _rebuild_thread.is_alive():
		_flow       = _rebuild_thread.wait_to_finish()
		_built      = true
		_rebuilding = false
		_rebuild_thread = null
		_draw_flow_field()

	_timer += delta
	if _timer >= UPDATE_INTERVAL and not _rebuilding:
		_timer = 0.0
		_start_rebuild()

func _start_rebuild() -> void:
	if _tilemap == null or _rebuilding:
		return
	_rebuilding     = true
	_rebuild_thread = Thread.new()
	_rebuild_thread.start(_rebuild.bind(
		_target,
		_tilemap.tile_types.duplicate(),
		_tilemap.TILE_SIZE.x,
		Vector2i(_tilemap.WIDTH / 2, _tilemap.HEIGHT / 2),
		_tilemap.WIDTH,
		_tilemap.HEIGHT,
		_tilemap.BUFFER_TILES
	))

func _rebuild(target: Vector2, tile_snapshot: Dictionary, tile_size: float, origin_offset: Vector2i, map_w: int, map_h: int, buffer: int) -> Dictionary:
	var origin: Vector2i   = _world_to_cell_s(target, tile_size, origin_offset)
	var cost:   Dictionary = { origin: 0.0 }
	var heap:   Array      = []
	_heap_push(heap, [0.0, origin])

	while heap.size() > 0:
		var entry           = _heap_pop(heap)
		var cur_cost: float = entry[0]
		var cur: Vector2i   = entry[1]
		if cur_cost > cost.get(cur, INF) + 0.001:
			continue
		for nb in _neighbours_s(cur, tile_snapshot, map_w, map_h, buffer):
			var move_cost: float = 1.0 if nb.x == cur.x or nb.y == cur.y else 1.414
			var new_cost:  float = cur_cost + move_cost
			if new_cost < cost.get(nb, INF):
				cost[nb] = new_cost
				_heap_push(heap, [new_cost, nb])

	var new_flow: Dictionary = {}
	for cell: Vector2i in cost.keys():
		var best_dir:  Vector2 = Vector2.ZERO
		var best_cost: float   = cost[cell]
		for nb in _neighbours_s(cell, tile_snapshot, map_w, map_h, buffer):
			var nb_cost: float = cost.get(nb, INF)
			if nb_cost < best_cost:
				best_cost = nb_cost
				best_dir  = Vector2(nb - cell).normalized()
		new_flow[cell] = best_dir

	return new_flow

# ── binary min-heap ───────────────────────────────────────────────────────────

func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i: int = heap.size() - 1
	while i > 0:
		var parent: int = (i - 1) / 2
		if heap[parent][0] <= heap[i][0]:
			break
		var tmp      = heap[parent]
		heap[parent] = heap[i]
		heap[i]      = tmp
		i            = parent

func _heap_pop(heap: Array) -> Array:
	var top:  Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.size() > 0:
		heap[0] = last
		var i: int = 0
		while true:
			var l: int = 2 * i + 1
			var r: int = 2 * i + 2
			var s: int = i
			if l < heap.size() and heap[l][0] < heap[s][0]: s = l
			if r < heap.size() and heap[r][0] < heap[s][0]: s = r
			if s == i:
				break
			var tmp  = heap[i]
			heap[i]  = heap[s]
			heap[s]  = tmp
			i        = s
	return top

# ── thread-safe helpers ───────────────────────────────────────────────────────

func _neighbours_s(cell: Vector2i, tile_snapshot: Dictionary, map_w: int, map_h: int, buffer: int) -> Array:
	var result:    Array = []
	var half_w:    int   = map_w / 2
	var half_h:    int   = map_h / 2
	var play_radius: float = (map_w - buffer) / 2.0   # matches tilemap exactly
	for offset in [
		Vector2i( 1,  0), Vector2i(-1,  0),
		Vector2i( 0,  1), Vector2i( 0, -1),
		Vector2i( 1,  1), Vector2i(-1,  1),
		Vector2i( 1, -1), Vector2i(-1, -1),
	]:
		var nb: Vector2i = cell + offset
		if nb.x < 0 or nb.y < 0 or nb.x >= map_w or nb.y >= map_h:
			continue
		var dx: float = float(nb.x - half_w)
		var dy: float = float(nb.y - half_h)
		if sqrt(dx * dx + dy * dy) >= play_radius:   # same test as tilemap: dist >= play_radius is outside
			continue
		if offset.x != 0 and offset.y != 0:
			if tile_snapshot.has(Vector2i(cell.x + offset.x, cell.y)) or \
			   tile_snapshot.has(Vector2i(cell.x, cell.y + offset.y)):
				continue
		if not tile_snapshot.has(nb):
			result.append(nb)
	return result

func _world_to_cell_s(world: Vector2, tile_size: float, offset: Vector2i = Vector2i.ZERO) -> Vector2i:
	return Vector2i(int(floor(world.x / tile_size)), int(floor(world.y / tile_size))) + offset

# ── main-thread helpers ───────────────────────────────────────────────────────

func _world_to_cell(world: Vector2) -> Vector2i:
	var ts: float = _tilemap.TILE_SIZE.x
	return Vector2i(int(floor(world.x / ts)), int(floor(world.y / ts))) + Vector2i(_tilemap.WIDTH / 2, _tilemap.HEIGHT / 2)

# ── debug draw ────────────────────────────────────────────────────────────────

var _debug_node: Node2D = null
var _debug_draw: bool   = false

func _draw_flow_field() -> void:
	if is_instance_valid(_debug_node):
		_debug_node.free()
		_debug_node = null
	if not _debug_draw or not _built or _tilemap == null:
		return
	var drawer        := FlowDebugDraw.new()
	drawer.z_index     = 4096
	drawer.z_as_relative = false
	drawer.flow        = _flow.duplicate()
	drawer.tilemap_ref = _tilemap
	_debug_node        = drawer
	get_tree().current_scene.add_child(_debug_node)

class FlowDebugDraw extends Node2D:
	var flow:        Dictionary = {}
	var tilemap_ref: Node       = null

	func _draw() -> void:
		if tilemap_ref == null:
			return
		for cell: Vector2i in flow:
			var dir:          Vector2 = flow[cell]
			var world_center: Vector2 = tilemap_ref.map_to_world(cell)
			if dir == Vector2.ZERO:
				draw_circle(world_center, 2.0, Color(1.0, 0.0, 0.0, 0.5))
			else:
				var tip: Vector2 = world_center + dir * tilemap_ref.TILE_SIZE.x * 0.4
				draw_line(world_center, tip, Color(0.0, 1.0, 0.4, 0.6), 1.0)
				draw_circle(tip, 2.0, Color(0.0, 1.0, 0.4, 0.8))
