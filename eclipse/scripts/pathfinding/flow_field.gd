# flow_field.gd
# Autoloaded as "FlowField"
# Dijkstra expansion from the player outward, rebuilt on a background thread.
# All standard enemies call get_direction() — O(1) per enemy per frame.
extends Node

const UPDATE_INTERVAL: float = 0.15
const MAX_CELLS:       int   = 2500

var _flow:     Dictionary = {}
var _timer:    float      = 0.0
var _target:   Vector2    = Vector2.ZERO
var _built:    bool       = false
var _tilemap:  Node       = null

var _rebuild_thread: Thread     = null
var _rebuilding:     bool       = false

# ── public API ────────────────────────────────────────────────────────────────

func initialize(tilemap: Node) -> void:
	_tilemap = tilemap
	_built   = false

func set_target(world_pos: Vector2) -> void:
	_target = world_pos

func is_ready() -> bool:
	return _built

func get_direction(world_pos: Vector2) -> Vector2:
	if not _built:
		return Vector2.ZERO
	return _flow.get(_world_to_cell(world_pos), Vector2.ZERO)

# ── process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _rebuilding and _rebuild_thread != null and not _rebuild_thread.is_alive():
		_flow       = _rebuild_thread.wait_to_finish()
		_built      = true
		_rebuilding = false
		_rebuild_thread = null

	_timer += delta
	if _timer >= UPDATE_INTERVAL and not _rebuilding:
		_timer = 0.0
		if _tilemap != null:   # ← removed NavManager._built check
			_rebuilding     = true
			_rebuild_thread = Thread.new()
			_rebuild_thread.start(_rebuild.bind(
				_target,
				_tilemap.tile_types.duplicate(),
				_tilemap.TILE_SIZE.x
			))

# ── threaded rebuild ──────────────────────────────────────────────────────────

func _rebuild(target: Vector2, tile_snapshot: Dictionary, tile_size: float) -> Dictionary:
	var origin: Vector2i   = _world_to_cell_s(target, tile_size)
	var cost:   Dictionary = { origin: 0.0 }
	var heap:   Array      = []
	_heap_push(heap, [0.0, origin])

	var count: int = 0
	while heap.size() > 0 and count < MAX_CELLS:
		var entry             = _heap_pop(heap)
		var cur_cost: float   = entry[0]
		var cur:  Vector2i    = entry[1]
		if cur_cost > cost.get(cur, INF) + 0.001:
			continue   # stale entry
		count += 1

		for nb in _neighbours_s(cur, tile_snapshot, tile_size):
			var move_cost: float = 1.0 if nb.x == cur.x or nb.y == cur.y else 1.414
			var new_cost:  float = cur_cost + move_cost
			if new_cost < cost.get(nb, INF):
				cost[nb] = new_cost
				_heap_push(heap, [new_cost, nb])

	# build direction lookup from cost gradient
	var new_flow: Dictionary = {}
	for cell: Vector2i in cost.keys():
		var best_dir:  Vector2 = Vector2.ZERO
		var best_cost: float   = cost[cell]
		for nb in _neighbours_s(cell, tile_snapshot, tile_size):
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
		var tmp        = heap[parent]
		heap[parent]   = heap[i]
		heap[i]        = tmp
		i              = parent

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
			if l < heap.size() and heap[l][0] < heap[s][0]:
				s = l
			if r < heap.size() and heap[r][0] < heap[s][0]:
				s = r
			if s == i:
				break
			var tmp  = heap[i]
			heap[i]  = heap[s]
			heap[s]  = tmp
			i        = s
	return top

# ── thread-safe helpers ───────────────────────────────────────────────────────

func _neighbours_s(cell: Vector2i, tile_snapshot: Dictionary, tile_size: float) -> Array:
	var result: Array = []
	for offset in [
		Vector2i( 1,  0), Vector2i(-1,  0),
		Vector2i( 0,  1), Vector2i( 0, -1),
		Vector2i( 1,  1), Vector2i(-1,  1),
		Vector2i( 1, -1), Vector2i(-1, -1),
	]:
		var nb: Vector2i = cell + offset
		# diagonal: both cardinal neighbours must also be clear (no corner cutting)
		if offset.x != 0 and offset.y != 0:
			if tile_snapshot.has(Vector2i(cell.x + offset.x, cell.y)) or \
			   tile_snapshot.has(Vector2i(cell.x, cell.y + offset.y)):
				continue
		if not tile_snapshot.has(nb):
			result.append(nb)
	return result

func _world_to_cell_s(world: Vector2, tile_size: float) -> Vector2i:
	return Vector2i(int(floor(world.x / tile_size)), int(floor(world.y / tile_size)))

# ── main-thread helpers (used by get_direction) ───────────────────────────────

func _world_to_cell(world: Vector2) -> Vector2i:
	var ts: float = _tilemap.TILE_SIZE.x
	return Vector2i(int(floor(world.x / ts)), int(floor(world.y / ts)))
