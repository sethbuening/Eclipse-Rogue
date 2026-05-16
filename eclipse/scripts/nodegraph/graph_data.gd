# graph_data.gd
class_name GraphData
extends Resource

@export var nodes:       Array[GraphNodeData]      = []
@export var connections: Array[GraphConnectionData] = []

func get_connections_for(node_index: int) -> Array[GraphConnectionData]:
	return connections.filter(func(c: GraphConnectionData) -> bool:
		return c.from_node == node_index or (c.bidirectional and c.to_node == node_index)
	)

func get_node_at(world_pos: Vector2, radius: float = 32.0) -> int:
	for i in range(nodes.size()):
		if nodes[i].position.distance_to(world_pos) < radius:
			return i
	return -1
