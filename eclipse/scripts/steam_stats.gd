extends Node

# For int and float stats, store the value directly.
# For AVGRATE stats, store as a sub-dictionary: {"value": 0.0, "session_length": 0.0}
var statistics: Dictionary = {
	"equipped_orbs": 0,
	# AVGRATE example:
	# "orbs_per_minute": {"value": 0.0, "session_length": 0.0},
}

func load_steam_stats() -> void:
	if not SteamManager.steam_enabled:
		return
	for this_stat in statistics.keys():
		var local_value = statistics[this_stat]
		# AVGRATE stats are write-only via updateAvgRateStat() — skip loading them
		if local_value is Dictionary:
			print("Skipping AVGRATE stat on load (write-only): %s" % this_stat)
			continue
		var steam_stat
		if local_value is int:
			steam_stat = Steam.getStatInt(this_stat)
		elif local_value is float:
			steam_stat = Steam.getStatFloat(this_stat)
		else:
			continue
		print("Retrieved %s stat from Steam: %s" % [this_stat, steam_stat])
		if local_value != steam_stat:
			print("Stat mismatch, syncing Steam -> local: %s" % this_stat)
			statistics[this_stat] = steam_stat
	print("Steam statistics loaded")

# Handles int, float, and AVGRATE in one call.
# For AVGRATE pass a float value and a session_length in seconds.
# Examples:
#   SteamStats.set_stat("equipped_orbs", 5)
#   SteamStats.set_stat("accuracy", 0.87)
#   SteamStats.set_stat("orbs_per_minute", 12.0, 60.0)
func set_stat(this_stat: String, new_value, session_length: float = 1.0) -> void:
	if not SteamManager.steam_enabled:
		return
	if not statistics.has(this_stat):
		print("Stat does not exist locally: %s" % this_stat)
		return
	var success: bool = false
	if new_value is int:
		statistics[this_stat] = new_value
		success = Steam.setStatInt(this_stat, new_value)
	elif new_value is float:
		var local_value = statistics[this_stat]
		if local_value is Dictionary:
			# AVGRATE stat
			statistics[this_stat]["value"] = new_value
			statistics[this_stat]["session_length"] = session_length
			success = Steam.updateAvgRateStat(this_stat, new_value, session_length)
		else:
			statistics[this_stat] = new_value
			success = Steam.setStatFloat(this_stat, new_value)
	if not success:
		print("Failed to set stat %s to: %s" % [this_stat, new_value])
		return
	print("Set stat %s successfully: %s" % [this_stat, new_value])
	SteamManager.store_steam_data()

func reset_statistics() -> void:
	print("Resetting all statistics and achievements for local user")
	if not Steam.resetAllStats(true):
		print("Failed to reset statistics and achievements")

func update_equipped_orbs_stat() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var count: int = 0
	for orb in players[0].get_node("Inventory").orbs:
		if orb.node_index != -1:
			count += 1
	set_stat("equipped_orbs", count)
