# ability_fortune_engine.gd
# ---------------------------------------------------------------------------
# Passive. Tracks failed crits across all Gold abilities. Each failed crit
# increments gold_manager.engine_stacks (written by every Gold projectile
# on non-crits). When any Gold ability crits, on_gold_crit() consumes all
# stacks and returns an engine_bonus multiplier.
#
# This ability's only job is to recalculate the stack cap and show the
# engine charge on the orb. The actual stack tracking and consumption
# happens in GoldManager.
#
# Stack cap
#   Base cap is a constant. When Fortune is present (King's Treasury
#   equipped), the cap also scales with current Fortune — high Fortune
#   means a lucky crit can land a much larger bonus. Without Fortune the
#   cap stays at the base, which is still fully functional.
#
# Synergies
#   → Rain of Crowns: Crowns consume engine_stacks on impact for bonus
#                     damage and larger crater radius
#   → Jackpot Wheel : high engine charge biases the Wheel toward jackpots
# ---------------------------------------------------------------------------
class_name AbilityFortuneEngine
extends AbilityData

# +1 cap per this many Fortune (only relevant when Fortune is present).
const STACKS_PER_FORTUNE: float = 0.04

const CAP_UPDATE_INTERVAL: float = 0.1
var _cap_timer: float = 0.0

func tick(context: Dictionary) -> void:
	super.tick(context)
	var delta: float        = context.get("delta", 0.0)
	var gold:  GoldManager  = context.get("gold", null)

	# Without a manager, there are no stacks to show — nothing to do.
	if gold == null:
		context["orb_t"] = 0.0
		return

	_cap_timer += delta
	if _cap_timer >= CAP_UPDATE_INTERVAL:
		_cap_timer = 0.0
		_recalculate_cap(gold)

	var cap: int = maxi(1, gold.engine_stack_cap)
	context["orb_t"] = clampf(float(gold.engine_stacks) / float(cap), 0.0, 1.0)

func _recalculate_cap(gold: GoldManager) -> void:
	var base: int = int(get_stat("engine_base_stack_cap"))
	if base <= 0:
		base = 6

	# Fortune bonus: scales stack cap upward when Fortune is available.
	var fortune_bonus: int = int(gold.fortune * STACKS_PER_FORTUNE)
	gold.engine_stack_cap = base + fortune_bonus
