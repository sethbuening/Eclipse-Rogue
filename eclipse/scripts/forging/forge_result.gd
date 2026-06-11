# forge_result.gd
class_name ForgeResult

var abilities:    Array[AbilityData] = []
var stat_bonuses: Dictionary         = {}
var identity:     Resource           = null
var heat:         int                = 0

# Whether this was a pure-metal forge (true) or orb merge (false).
# Determines whether the player picks an ability at all.
var is_metal_only: bool = false

# The raw metal_counts snapshot kept for weighted stat selection.
var metal_counts_snapshot: Dictionary = {}

static func compute(
	input_orbs:   Array[Orb],
	metal_counts: Dictionary
) -> ForgeResult:
	var result := ForgeResult.new()
	result.metal_counts_snapshot = metal_counts.duplicate()
	for metal: MetalData in metal_counts:
		result.heat += metal.rarity * metal_counts[metal]

	if input_orbs.is_empty():
		result.is_metal_only = true
		_compute_metal_only(result, metal_counts)
	else:
		result.is_metal_only = false
		_compute_orb_merge(result, input_orbs, metal_counts)

	result.identity = _pick_identity(input_orbs, metal_counts)
	return result

# Metal-only: abilities are NOT auto-assigned here anymore.
# We just compute heat so the UI can drive the choice flow.
static func _compute_metal_only(
	_result:      ForgeResult,
	_metal_counts: Dictionary
) -> void:
	pass   # abilities chosen interactively; stats chosen interactively

# Orb merge: inherit all abilities from input orbs, no new ability added.
static func _compute_orb_merge(
	result:     ForgeResult,
	input_orbs: Array[Orb],
	_metal_counts: Dictionary
) -> void:
	for orb: Orb in input_orbs:
		for ability: AbilityData in orb.abilities:
			result.abilities.append(ability.duplicate(true))

static func _pick_identity(
	input_orbs:   Array[Orb],
	metal_counts: Dictionary
) -> Resource:
	if not input_orbs.is_empty():
		var dominant: Orb = input_orbs[0]
		for orb: Orb in input_orbs:
			if orb.abilities.size() > dominant.abilities.size():
				dominant = orb
		return dominant
	var dominant_metal: MetalData = null
	var dominant_score: int       = 0
	for metal: MetalData in metal_counts:
		var score: int = metal_counts[metal] * metal.rarity
		if score > dominant_score:
			dominant_score = score
			dominant_metal = metal
	return dominant_metal

# ── Weighted helpers used by ForgeUI for interactive choice ──────────────────

# Build a weighted pool of AbilityData options drawn from the metal ability pools.
# Returns `count` items sampled with replacement (duplicated) based on metal weights.
static func build_weighted_ability_options(
	metal_counts: Dictionary,
	count: int = 3
) -> Array[AbilityData]:
	# Build flat weighted list: each ability entry appears (metal_count * rarity) times
	var pool: Array[AbilityData] = []
	for metal: MetalData in metal_counts:
		if metal.ability_pool.is_empty():
			continue
		var weight: int = metal_counts[metal] * metal.rarity
		for _i in range(weight):
			for ability: AbilityData in metal.ability_pool:
				pool.append(ability)

	if pool.is_empty():
		return []

	pool.shuffle()

	# Pick `count` distinct abilities (by type, not instance)
	var chosen:   Array[AbilityData] = []
	var seen_ids: Array[String]      = []

	for ability: AbilityData in pool:
		var id: String = ability.get_script().get_path() if ability.get_script() else ability.display_name
		if id in seen_ids:
			continue
		seen_ids.append(id)
		chosen.append(ability.duplicate(true))
		if chosen.size() >= count:
			break

	# If pool was small, pad by reusing (avoidable duplicates)
	if chosen.size() < count and not pool.is_empty():
		var i: int = 0
		while chosen.size() < count:
			chosen.append(pool[i % pool.size()].duplicate(true))
			i += 1

	return chosen

# Build a weighted pool of stat upgrade options for a given ability.
# Returns `count` stat name strings sampled based on metal weights.
# Each option is a { stat: String, amount: float } dict.
static func build_weighted_stat_options(
	metal_counts: Dictionary,
	ability: AbilityData,
	count: int = 3
) -> Array[Dictionary]:
	# Collect stats the ability actually uses (value != -1 means the stat is active).
	# AbilityStats is a Resource, not a Dictionary — use get_property_list() to iterate.
	var ability_stats: Array[String] = []
	var filter_by_ability: bool = false
	if ability != null and ability.stats != null:
		for prop in ability.stats.get_property_list():
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
				continue
			var val = ability.stats.get(prop.name)
			if val != null and val != -1:
				ability_stats.append(prop.name)
		filter_by_ability = not ability_stats.is_empty()

	# Build weighted pool: metal contributes its stats weighted by count * rarity,
	# but only for stats that the ability actually owns
	var pool: Array[Dictionary] = []
	for metal: MetalData in metal_counts:
		var weight: int = metal_counts[metal] * metal.rarity
		for i in range(metal.stat_names.size()):
			var stat: String   = metal.stat_names[i]
			var amount: float  = metal.stat_amounts[i] if i < metal.stat_amounts.size() else 0.1
			if filter_by_ability and stat not in ability_stats:
				continue
			for _w in range(weight):
				pool.append({ "stat": stat, "amount": amount * metal.rarity })

	if pool.is_empty():
		# Fallback: all ability stats equally weighted
		for stat: String in ability_stats:
			pool.append({ "stat": stat, "amount": 0.1 })

	pool.shuffle()

	var chosen:    Array[Dictionary] = []
	var seen_stats: Array[String]    = []

	for entry: Dictionary in pool:
		if entry.stat in seen_stats:
			continue
		seen_stats.append(entry.stat)
		chosen.append(entry)
		if chosen.size() >= count:
			break

	# Pad if needed
	if chosen.size() < count and not pool.is_empty():
		var i: int = 0
		while chosen.size() < count:
			chosen.append(pool[i % pool.size()])
			i += 1

	return chosen

# How many stat upgrade picks the player gets, based on total metal input.
static func stat_pick_count(metal_counts: Dictionary) -> int:
	var total: int = 0
	for metal: MetalData in metal_counts:
		total += metal_counts[metal]
	# 1 pick per metal up to 5. If no metal was input, 0 stat picks.
	return clampi(total, 0, 5)
