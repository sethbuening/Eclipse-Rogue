extends Node

var achievements: Dictionary = {
	"triple_threat": false,
}

func load_steam_achievements() -> void:
	if not SteamManager.steam_enabled:
		return
	for this_achievement in achievements.keys():
		var steam_achievement: Dictionary = Steam.getAchievement(this_achievement)
		if not steam_achievement['ret']:
			print("Steam does not have this achievement, ignoring it: %s" % this_achievement)
			continue
		if achievements[this_achievement] == steam_achievement['achieved']:
			print("Achievement matches, skipping: %s" % this_achievement)
			continue
		print("Achievement mismatch, syncing Steam -> local: %s" % this_achievement)
		achievements[this_achievement] = steam_achievement['achieved']
	print("Steam achievements loaded")

func set_achievement(this_achievement: String) -> void:
	if not SteamManager.steam_enabled:
		return
	if not achievements.has(this_achievement):
		print("Achievement does not exist locally: %s" % this_achievement)
		return
	if achievements[this_achievement]:
		print("Achievement already unlocked: %s" % this_achievement)
		return
	achievements[this_achievement] = true
	if not Steam.setAchievement(this_achievement):
		print("Failed to set achievement: %s" % this_achievement)
		return
	print("Set achievement: %s" % this_achievement)
	SteamManager.store_steam_data()

func reset_achievement(this_achievement: String) -> void:
	print("Resetting achievement %s" % this_achievement)
	if not Steam.clearAchievement(this_achievement):
		print("Failed to reset achievement: %s" % this_achievement)

func reset_all_achievements() -> void:
	for this_achievement in achievements.keys():
		reset_achievement(this_achievement)
