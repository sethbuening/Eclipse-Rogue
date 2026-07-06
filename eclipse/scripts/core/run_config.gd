# run_config.gd
# ---------------------------------------------------------------------------
# Stores the biome/depth/class chosen in mission_setup_menu.gd and fires
# mission_started so the live game scene (core/game.gd) can react. Add as an
# autoload (singleton) named "RunConfig".
# ---------------------------------------------------------------------------
extends Node

signal mission_started(biome: BiomeData, depth: int, char_class: ClassData)

var biome:      BiomeData = null
var depth:      int       = -1
var char_class: ClassData = null

func start_mission(b: BiomeData, d: int, c: ClassData) -> void:
	biome      = b
	depth      = d
	char_class = c
	mission_started.emit(biome, depth, char_class)
