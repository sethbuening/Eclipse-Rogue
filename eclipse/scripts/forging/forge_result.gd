# forge_result.gd
class_name ForgeResult

var abilities:    Array[AbilityData] = []
var stat_bonuses: Dictionary         = {}
var identity:     Resource           = null
var heat:         int                = 0

static func compute(
	input_orbs:   Array[Orb],
	metal_counts: Dictionary
) -> ForgeResult:
	var result := ForgeResult.new()
	for metal: MetalData in metal_counts:
		result.heat += metal.rarity * metal_counts[metal]
	if input_orbs.is_empty():
		_compute_metal_only(result, metal_counts)
	else:
		_compute_orb_merge(result, input_orbs, metal_counts)
	result.identity = _pick_identity(input_orbs, metal_counts)
	return result

static func _compute_metal_only(
	result:       ForgeResult,
	metal_counts: Dictionary
) -> void:
	for metal: MetalData in metal_counts:
		var count: int = metal_counts[metal]
		if not metal.ability_pool.is_empty():
			result.abilities.append(
				metal.ability_pool[randi() % metal.ability_pool.size()].duplicate(true)
			)
		for i in range(metal.stat_names.size()):
			var stat:   String = metal.stat_names[i]
			var amount: float  = metal.stat_amounts[i] if i < metal.stat_amounts.size() else 0.1
			result.stat_bonuses[stat] = \
				result.stat_bonuses.get(stat, 0.0) + amount * count * metal.rarity

static func _compute_orb_merge(
	result:       ForgeResult,
	input_orbs:   Array[Orb],
	metal_counts: Dictionary
) -> void:
	for orb: Orb in input_orbs:
		for ability: AbilityData in orb.abilities:
			result.abilities.append(ability.duplicate(true))
	for metal: MetalData in metal_counts:
		var count: int = metal_counts[metal]
		for i in range(metal.stat_names.size()):
			var stat:   String = metal.stat_names[i]
			var amount: float  = metal.stat_amounts[i] if i < metal.stat_amounts.size() else 0.1
			result.stat_bonuses[stat] = \
				result.stat_bonuses.get(stat, 0.0) + amount * count * metal.rarity

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
