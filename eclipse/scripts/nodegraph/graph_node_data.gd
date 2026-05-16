class_name GraphNodeData
extends Resource

enum NodeType { STAT, AOE, ECHO, STAT_CONVERTER, DECAYING }

@export var node_type:  NodeType = NodeType.STAT
@export var stat_name:  String   = ""
@export var stat_value: float    = 0.0
@export var position:   Vector2  = Vector2.ZERO

var placed_orb:      Orb                    = null
var baseline_stats:  Array[AbilityStats]    = []  # snapshot before node modifiers
