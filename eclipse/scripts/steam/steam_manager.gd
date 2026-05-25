extends Node

const APP_ID: int    = 4775380
const DEV_MODE: bool = false
var steam_enabled: bool = false

func _ready() -> void:
	#initialize_steam()
	if DEV_MODE:
		print("DEV_MODE: resetting all stats and achievements")
		SteamAchievements.reset_all_achievements()
		SteamStats.reset_statistics()
		store_steam_data()

func _process(_delta: float) -> void:
	if steam_enabled:
		Steam.run_callbacks()
		#SteamInputManager.tick()

func initialize_steam() -> void:
	var initialize_response: Dictionary = Steam.steamInitEx(APP_ID, false)
	print("Steam init response: %s" % initialize_response)
	if initialize_response['status'] != Steam.STEAM_API_INIT_RESULT_OK:
		print("Failed to initialize Steam, disabling Steam functionality: %s" % initialize_response)
		return
	steam_enabled = true
	print("Steam initialized successfully")
	#SteamInputManager.initialize()
	SteamStats.load_steam_stats()
	SteamAchievements.load_steam_achievements()

func store_steam_data() -> void:
	if not steam_enabled:
		print("Steam is not enabled, data will not be stored on steam")
		return
	if not Steam.storeStats():
		print("Failed to store data on Steam")
		return
	print("Data successfully sent to Steam")
