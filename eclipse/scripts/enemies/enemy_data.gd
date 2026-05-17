# enemy_data.gd
class_name EnemyData
extends Resource

@export var id:          String  = "grunt"
@export var display_name: String = "Grunt"
@export var max_health:  int     = 3
@export var speed:       float   = 60.0
@export var damage:      int     = 1
@export var cost:        int     = 1      # wave budget cost, mirrors roster
@export var min_wave:    int     = 1
@export var scene:       PackedScene      # the instanced scene for this enemy
