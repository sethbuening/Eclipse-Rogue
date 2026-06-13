# upgrade_add_relic.gd
# ---------------------------------------------------------------------------
# A LevelUpUpgrade that adds a new relic from the item pool to the player's
# inventory. Mirrors UpgradeAddAbilityToOrb.
#
# Candidate relics are drawn from ItemManager._relic_pool, excluding any the
# player already owns. If the player's inventory is at relic_max, this
# upgrade type will not be offered.
# ---------------------------------------------------------------------------
class_name UpgradeAddRelic
extends LevelUpUpgrade

var new_relic: RelicData = null

static func build(
	player: CharacterBody2D,
	rarity: int = 0
) -> UpgradeAddRelic:
	var inventory: Node   = player.get_node("Inventory")
	var p_stats: PlayerStats = player.stats

	# Don't offer if inventory is already full.
	if p_stats.relic_max > 0:
		var current_count: int = 0
		for r: RelicData in inventory.relics:
			current_count += inventory.relics[r]
		if current_count >= p_stats.relic_max:
			return null

	# Build candidate pool: all relics not already owned.
	var owned_ids: Array[String] = []
	for r: RelicData in inventory.relics:
		owned_ids.append(r.id)

	var candidates: Array[RelicData] = []
	for r: RelicData in ItemManager._relic_pool:
		if r.id not in owned_ids:
			candidates.append(r)

	if candidates.is_empty():
		return null

	candidates.shuffle()
	var picked: RelicData = candidates[0]

	var u := UpgradeAddRelic.new()
	u.new_relic = picked
	u.rarity    = rarity

	u.display_name = "New Relic\n%s" % picked.display_name
	u.description  = picked.description if picked.description != "" else "A powerful relic."
	u.icon         = picked.icon

	return u

func apply(player: CharacterBody2D) -> void:
	if new_relic == null:
		return
	player.get_node("Inventory").add_relic(new_relic, 1)
