# graph_connection_data.gd
class_name GraphConnectionData
extends Resource

enum ConnectionType { CHARGES, OVERHEATS, RESONATOR, DRAINS, SILENCE }

@export var connection_type: ConnectionType = ConnectionType.CHARGES
@export var from_node:       int            = 0   # index into graph nodes array
@export var to_node:         int            = 0
@export var bidirectional:   bool           = false

# runtime state
var charge_stacks:    int   = 0
var overheat_count:   int   = 0
var silence_age:      float = 0.0
var drain_power:      float = 1.0

static func is_bidirectional_type(t: ConnectionType) -> bool:
	return t == ConnectionType.RESONATOR or t == ConnectionType.SILENCE
