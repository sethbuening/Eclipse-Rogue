class_name MissionContent
extends RefCounted

## Content for the biome/class steps of mission setup.
##
## To add a biome: create a new Resource in the editor, set its script to
## res://scripts/data/biome_data.gd, fill in the fields, and save it as a
## .tres file inside res://data/biomes/ (create that folder if needed).
## It'll show up automatically -- no code changes required.
## Classes work the same way under res://data/classes/ with class_data.gd.
##
## If either folder is missing/empty, the hardcoded stubs below are used
## instead so the flow still works before you've made any resources.

const BIOME_DIR: String = "res://data/biomes/"
const CLASS_DIR: String = "res://data/classes/"

const DEPTH_MIN: int = 1
const DEPTH_MAX: int = 5

static func get_biomes() -> Array[BiomeData]:
	var loaded: Array[BiomeData] = []
	loaded.assign(_load_resources(BIOME_DIR))
	if not loaded.is_empty():
		return loaded
	return _stub_biomes()

static func get_classes() -> Array[ClassData]:
	var loaded: Array[ClassData] = []
	loaded.assign(_load_resources(CLASS_DIR))
	if not loaded.is_empty():
		return loaded
	return _stub_classes()

## Loads every .tres/.res file in `dir_path` and returns the ones that
## resolve to a Resource of the expected type (BiomeData or ClassData).
static func _load_resources(dir_path: String) -> Array:
	var results: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return results
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			var res: Resource = load(dir_path + file_name)
			if res is BiomeData or res is ClassData:
				results.append(res)
		file_name = dir.get_next()
	dir.list_dir_end()
	return results

# ── fallback stub content (used until you add real .tres resources) ────────
static func _stub_biomes() -> Array[BiomeData]:
	var list: Array[BiomeData] = []

	var ferrous := BiomeData.new()
	ferrous.id           = &"ferrous_hollow"
	ferrous.display_name = "Ferrous Hollow"
	ferrous.description  = "Rust-streaked tunnels thick with scrap-metal vermin."
	ferrous.tint         = Color("#b06a3a")
	list.append(ferrous)

	var brine := BiomeData.new()
	brine.id           = &"brine_trench"
	brine.display_name = "Brine Trench"
	brine.description  = "Flooded fissures crawling with bioluminescent predators."
	brine.tint         = Color("#3a8eb0")
	list.append(brine)

	var magma := BiomeData.new()
	magma.id           = &"magma_vein"
	magma.display_name = "Magma Vein"
	magma.description  = "Molten rock channels where the heat itself fights back."
	magma.tint         = Color("#d05a2a")
	list.append(magma)

	var crystal := BiomeData.new()
	crystal.id           = &"crystal_caverns"
	crystal.display_name = "Crystal Caverns"
	crystal.description  = "Resonant geode chambers, gorgeous and unstable."
	crystal.tint         = Color("#8a6ad0")
	list.append(crystal)

	var void_rift := BiomeData.new()
	void_rift.id           = &"void_rift"
	void_rift.display_name = "Void Rift"
	void_rift.description  = "Gravity-warped corridors where physics misbehaves."
	void_rift.tint         = Color("#2a4a8a")
	list.append(void_rift)

	return list

static func _stub_classes() -> Array[ClassData]:
	var list: Array[ClassData] = []

	var driller := ClassData.new()
	driller.id           = &"driller"
	driller.display_name = "Driller"
	driller.description  = "Close-range mining brute; high armor pen, low range."
	list.append(driller)

	var prospector := ClassData.new()
	prospector.id           = &"prospector"
	prospector.display_name = "Prospector"
	prospector.description  = "Ranged marksman built around crit and ore yield."
	list.append(prospector)

	var engineer := ClassData.new()
	engineer.id           = &"engineer"
	engineer.display_name = "Engineer"
	engineer.description  = "Turrets and deployables; sustained area control."
	list.append(engineer)

	var pyromancer := ClassData.new()
	pyromancer.id           = &"pyromancer"
	pyromancer.display_name = "Pyromancer"
	pyromancer.description  = "DoT-stacking caster; thrives on long encounters."
	list.append(pyromancer)

	return list
