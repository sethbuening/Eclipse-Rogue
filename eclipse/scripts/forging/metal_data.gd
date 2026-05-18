# metal_data.gd
class_name MetalData
extends Resource

@export var id:              String             = ""
@export var display_name:    String             = ""
@export var rarity:          int                = 1
@export var tile_type:       Util.tile          = Util.tile.GOLD
@export var stat_names:      Array[String]      = []
@export var stat_amounts:    Array[float]       = []
@export var ability_pool:    Array[AbilityData] = []
@export var enemy_pool:      Array[EnemyData]   = []
@export var sprite_texture:  Texture2D          = null
