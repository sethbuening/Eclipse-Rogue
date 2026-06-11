# ability_jackpot_wheel.gd
# ---------------------------------------------------------------------------
# Passive. Spins a hidden wheel on a fixed interval. The next Gold ability
# to crit after a spin receives the outcome.
#
# Without King's Treasury
#   Still works — the Wheel spins on its own timer and outcomes are applied
#   to crits. Engine-stack biasing is zero (no stacks without a manager),
#   so the table uses uniform weights. The wheel is a straightforward crit
#   modifier in this configuration.
#
# With Fortune Engine
#   High engine_stacks relative to cap biases the table toward jackpots.
#
# Outcomes are processed by whichever Gold projectile lands the next crit.
# Outcomes that projectile can't use are put back for the next crit.
#
# Synergies
#   → Coinstorm   : EXTRA_COINSTORM doubles projectile count for next volley
#   → Midas Curse : BONUS_MARK creates a second temporary mark
#   → Gilded Shot : GUARANTEED_CRITS and crit-mult outcomes apply here
#   ← Fortune Engine: high engine charge biases toward jackpots
# ---------------------------------------------------------------------------
class_name AbilityJackpotWheel
extends AbilityData

var _spin_timer: float = 0.0

func tick(context: Dictionary) -> void:
	super.tick(context)
	var delta: float        = context.get("delta", 0.0)
	var gold:  GoldManager  = context.get("gold", null)

	# No manager: spin using a local timer with no engine biasing.
	# Manager present: use shared wheel state so other abilities can react.
	if gold == null:
		_tick_standalone(delta, context)
		return

	if gold.wheel_ready:
		context["orb_t"] = 1.0
		return

	_spin_timer += delta
	var interval: float = _get_interval()
	context["orb_t"] = clampf(_spin_timer / interval, 0.0, 1.0)

	if _spin_timer >= interval:
		_spin_timer = 0.0
		var outcome: GoldManager.WheelOutcome = _roll_outcome(gold)
		gold.wheel_outcome = outcome
		gold.wheel_ready   = true
		gold.emit_signal("wheel_spun", outcome)

## Standalone spin path: no GoldManager, no engine biasing.
## Outcomes are written to context["wheel_outcome"] for projectiles to read.
func _tick_standalone(delta: float, context: Dictionary) -> void:
	if context.get("wheel_outcome", GoldManager.WheelOutcome.NONE) != GoldManager.WheelOutcome.NONE:
		context["orb_t"] = 1.0
		return

	_spin_timer += delta
	var interval: float = _get_interval()
	context["orb_t"] = clampf(_spin_timer / interval, 0.0, 1.0)

	if _spin_timer >= interval:
		_spin_timer = 0.0
		context["wheel_outcome"] = _roll_outcome(null)

func _get_interval() -> float:
	var interval: float = get_stat("wheel_spin_interval")
	return interval if interval > 0.0 else 5.0

func _roll_outcome(gold: GoldManager) -> GoldManager.WheelOutcome:
	var engine_charge_t: float = 0.0
	if gold != null:
		var cap: int = maxi(1, gold.engine_stack_cap)
		engine_charge_t = clampf(float(gold.engine_stacks) / float(cap), 0.0, 1.0)

	var jackpot_w: float = lerp(1.0, 6.0, engine_charge_t)
	var minor_w:   float = lerp(6.0, 1.0, engine_charge_t)

	var table: Array = [
		{ "outcome": GoldManager.WheelOutcome.DOUBLE_CRIT,      "weight": lerp(4.0, 2.0, engine_charge_t) },
		{ "outcome": GoldManager.WheelOutcome.TRIPLE_CRIT,      "weight": jackpot_w },
		{ "outcome": GoldManager.WheelOutcome.FORTUNE_BURST,    "weight": lerp(3.0, 2.0, engine_charge_t) },
		{ "outcome": GoldManager.WheelOutcome.GUARANTEED_CRITS, "weight": lerp(3.0, 4.0, engine_charge_t) },
		{ "outcome": GoldManager.WheelOutcome.EXTRA_COINSTORM,  "weight": lerp(2.0, 3.0, engine_charge_t) },
		{ "outcome": GoldManager.WheelOutcome.BONUS_MARK,       "weight": minor_w },
	]

	var total: float = 0.0
	for entry in table:
		total += entry["weight"]

	var roll:  float = randf() * total
	var accum: float = 0.0
	for entry in table:
		accum += entry["weight"]
		if roll <= accum:
			return entry["outcome"]

	return GoldManager.WheelOutcome.DOUBLE_CRIT
