# graph_manager.gd
extends Node

const MIN_NODES:        int   = 4
const MAX_NODES:        int   = 4
const MIN_NODE_DIST:    float = 120.0
const GRAPH_RADIUS:     float = 300.0
const CONNECTION_CHANCE: float = 0.4   # per eligible pair

var graph: GraphData = GraphData.new()

# stat names available for STAT nodes
const STAT_POOL: Array[String] = [
	"power", "crit_chance", "crit_damage", "aoe_radius",
	"cooldown", "mining_power", "knockback", "shield_amount"
]

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
		var node          := GraphNodeData.new()
		node.position      = candidate
		node.node_type     = _random_node_type()
		if node.node_type == GraphNodeData.NodeType.STAT:
			node.stat_name  = STAT_POOL[randi() % STAT_POOL.size()]
			node.stat_value = randf_range(0.1, 0.5)
		graph.nodes.append(node)

func _generate_connections() -> void:
	# ensure graph is connected first — span a minimum spanning path
	var connected: Array[int] = [0]
	var remaining: Array[int] = Array(range(1, graph.nodes.size()), TYPE_INT, "", null)
	remaining.shuffle()
	for idx: int in remaining:
		var from: int = connected[randi() % connected.size()]
		_add_connection(from, idx)
		connected.append(idx)

	# then add bonus connections randomly
	for a in range(graph.nodes.size()):
		for b in range(a + 1, graph.nodes.size()):
			if _already_connected(a, b):
				continue
			if randf() < CONNECTION_CHANCE:
				_add_connection(a, b)

func _add_connection(from: int, to: int) -> void:
	var c                := GraphConnectionData.new()
	c.from_node           = from
	c.to_node             = to
	c.connection_type     = _random_connection_type()
	c.bidirectional       = GraphConnectionData.is_bidirectional_type(c.connection_type)
	graph.connections.append(c)

func _already_connected(a: int, b: int) -> bool:
	for c: GraphConnectionData in graph.connections:
		if (c.from_node == a and c.to_node == b) or (c.from_node == b and c.to_node == a):
			return true
	return false

func _random_node_type() -> GraphNodeData.NodeType:
	var types: Array = GraphNodeData.NodeType.values()
	return types[randi() % types.size()]

func _random_connection_type() -> GraphConnectionData.ConnectionType:
	var types: Array = GraphConnectionData.ConnectionType.values()
	return types[randi() % types.size()]

# called when an orb ability fires — process connection effects
func on_orb_fired(node_index: int, context: Dictionary) -> void:
	for conn: GraphConnectionData in graph.get_connections_for(node_index):
		var is_source: bool = conn.from_node == node_index
		match conn.connection_type:
			GraphConnectionData.ConnectionType.CHARGES:
				if is_source:
					conn.charge_stacks += 1
					context["charge_bonus"] = conn.charge_stacks
			GraphConnectionData.ConnectionType.OVERHEATS:
				conn.overheat_count += 1
				if conn.overheat_count > 3:
					context["overheated"] = true
			GraphConnectionData.ConnectionType.SILENCE:
				context["silence_bonus"] = conn.silence_age
				conn.silence_age = 0.0
			GraphConnectionData.ConnectionType.DRAINS:
				if is_source:
					conn.drain_power = maxf(0.5, conn.drain_power - 0.1)
					context["drain_weakened"] = conn.drain_power
				else:
					context["drain_empowered"] = 1.0 + (1.0 - conn.drain_power)
					conn.drain_power = 1.0

func _process(delta: float) -> void:
	for conn: GraphConnectionData in graph.connections:
		# silence builds up over time when not triggered
		if conn.connection_type == GraphConnectionData.ConnectionType.SILENCE:
			conn.silence_age += delta
		# overheat slowly decays
		if conn.connection_type == GraphConnectionData.ConnectionType.OVERHEATS:
			conn.overheat_count = max(0, conn.overheat_count - delta * 0.5)
