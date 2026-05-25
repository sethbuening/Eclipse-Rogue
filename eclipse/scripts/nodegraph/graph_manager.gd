extends Node
const MIN_NODES:        int   = 3
const MAX_NODES:        int   = 3
const MIN_NODE_DIST:    float = 120.0
const GRAPH_RADIUS:     float = 300.0
const MIN_CONNECTIONS:  int   = 1
const MAX_CONNECTIONS:  int   = 1

var graph: GraphData = GraphData.new()

const STAT_POOL: Array[String] = [
	# core
	"power", "cooldown", "duration", "range",
	# speed
	"cast_speed", "projectile_speed", "move_speed_bonus",
	# area
	"aoe_radius", "pierce",
	# critical hits
	"crit_chance", "crit_damage", "crit_aoe",
	# light / resource
	"light_cost", "light_on_hit", "light_on_crit",
	# mining
	"mining_power", "mining_radius", "ore_yield",
	# enemy interaction
	"knockback", "stun_duration", "slow_amount", "slow_duration", "dot_damage", "dot_duration",
	# defensive
	"damage_absorb", "reflect_chance", "shield_amount",
]

# Stats where a lower value is better — the modifier is inverted so the node
# still represents a buff even though the raw value decreases.
const INVERSE_STATS: Array[String] = [
	"cooldown",
	"light_cost",
]

func is_inverse(stat_name: String) -> bool:
	return stat_name in INVERSE_STATS

const STAT_VALUE_MIN: float = 1.1
const STAT_VALUE_MAX: float = 1.5

func generate() -> void:
	graph = GraphData.new()
	var count: int = randi_range(MIN_NODES, MAX_NODES)
	_place_nodes(count)
	_generate_connections()

func _place_nodes(count: int) -> void:
	var attempts: int = 0
	while graph.nodes.size() < count and attempts < 200:
		attempts += 1
		var candidate: Vector2 = Vector2(
			randf_range(-GRAPH_RADIUS, GRAPH_RADIUS),
			randf_range(-GRAPH_RADIUS, GRAPH_RADIUS)
		)
		var too_close: bool = false
		for existing: GraphNodeData in graph.nodes:
			if existing.position.distance_to(candidate) < MIN_NODE_DIST:
				too_close = true
				break
		if too_close:
			continue
		var node       := GraphNodeData.new()
		node.position   = candidate
		node.stat_name  = STAT_POOL[randi() % STAT_POOL.size()]
		node.stat_value = randf_range(STAT_VALUE_MIN, STAT_VALUE_MAX)
		graph.nodes.append(node)

func _generate_connections() -> void:
	var node_count: int = graph.nodes.size()
	if node_count < 2:
		return

	var target: int = mini(randi_range(MIN_CONNECTIONS, MAX_CONNECTIONS), node_count * (node_count - 1) / 2)

	# Spanning tree first to guarantee all nodes are reachable.
	var connected: Array[int] = [0]
	var remaining: Array[int] = Array(range(1, node_count), TYPE_INT, "", null)
	remaining.shuffle()
	for idx: int in remaining:
		if graph.connections.size() >= target:
			break
		var from: int = connected[randi() % connected.size()]
		_add_connection(from, idx)
		connected.append(idx)

	# Add extra connections until we hit the target.
	var candidates: Array = []
	for a in range(node_count):
		for b in range(a + 1, node_count):
			if not _already_connected(a, b):
				candidates.append([a, b])
	candidates.shuffle()

	for pair in candidates:
		if graph.connections.size() >= target:
			break
		_add_connection(pair[0], pair[1])

func _add_connection(from: int, to: int) -> void:
	var c          := GraphConnectionData.new()
	c.from_node     = from
	c.to_node       = to
	c.bidirectional = false
	graph.connections.append(c)

func _already_connected(a: int, b: int) -> bool:
	for c: GraphConnectionData in graph.connections:
		if (c.from_node == a and c.to_node == b) or (c.from_node == b and c.to_node == a):
			return true
	return false

func on_orb_fired(node_index: int, context: Dictionary, source_orb: Orb) -> void:
	for conn: GraphConnectionData in graph.get_connections_for(node_index):
		var is_source:         bool = conn.from_node == node_index
		var target_node_index: int  = conn.to_node if is_source else conn.from_node
		var target_orb:        Orb  = graph.nodes[target_node_index].placed_orb
		if target_orb == null:
			continue
		if is_source:
			conn.charge_stacks += 1
			for ability: AbilityData in target_orb.abilities:
				ability.stats.power += 0.1
		else:
			for ability: AbilityData in source_orb.abilities:
				ability.stats.power -= conn.charge_stacks * 0.1
			conn.charge_stacks = 0
