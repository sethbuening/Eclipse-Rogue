class_name BiomeData
extends Resource

## Stub biome definition used by the mission setup flow (main_menu -> NEW MISSION).
## TODO: migrate to res://data/json/biomes.json via DataLoader once content is final,
## mirroring how abilities/enemies/relics are loaded.

@export var id:           StringName = &""
@export var display_name: String     = ""
@export var description:  String     = ""
@export var icon:         Texture2D  = null
@export var tint:         Color      = Color.WHITE
## Max depth this biome currently supports (all stubs allow the full 1-5 range).
@export var max_depth:    int        = 5
