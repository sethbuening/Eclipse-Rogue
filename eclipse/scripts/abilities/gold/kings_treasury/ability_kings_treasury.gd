# ability_kings_treasury.gd
# ---------------------------------------------------------------------------
# Passive. The only Gold ability that creates and owns a GoldManager node.
# On its first tick it instantiates a GoldManager as a child, configures
# it from stats, and stores the reference. Every subsequent tick it:
#   • drives GoldManager.tick() for the frame
#   • writes context["gold"] so all other Gold abilities can reach the manager
#
# Without King's Treasury in the loadout, context["gold"] is null and every
# other Gold ability falls back gracefully — they work without Fortune.
#
# Royal Wealth grants
#   • Guaranteed crits (player.guaranteed_crits += 20)
#   • Fortune decay suspended
#   • Coinstorm / Halo locked to maximum radius
#   • ONE free Crown volley (GoldManager.free_crown_pending)
#   • First crit during Royal Wealth cascade-detonates all StaticFields
#
# Synergies
#   ← Gilded Shot  : steady Treasury generation
#   ← Golden Halo  : rapid Treasury generation while surrounded
#   ← Coinstorm    : can fill Treasury in one dense-crowd volley
#   → Rain of Crowns: free_crown_pending triggers an immediate free Crown
# ---------------------------------------------------------------------------
class_name AbilityKingsTreasury
extends AbilityData

# Treasury fill threshold — not exposed to the player as a tunable;
# it is always set from stats and only meaningful internally.
const DEFAULT_TREASURY_CAPACITY: float = 200.0

var _gold: GoldManager = null
var _rw_was_active: bool = false

func tick(context: Dictionary) -> void:
	super.tick(context)
	var player: CharacterBody2D = context["player"]
	var delta:  float           = context.get("delta", 0.0)

	# First tick: create the manager, configure it, attach it so it lives
	# alongside this ability's owning node.
	if _gold == null:
		_gold = GoldManager.new()
		player.get_parent().add_child(_gold)
		_configure_manager()

	# Publish the manager for every other Gold ability this frame.
	context["gold"] = _gold

	# Drive the shared state tick.
	_gold.tick(delta, player)

	# Orb glow: Treasury fill progress, or Royal Wealth pulse.
	if _gold.royal_wealth_active:
		var pulse_t: float = sin(context.get("time", 0.0) * 8.0) * 0.5 + 0.5
		context["orb_t"] = pulse_t
	else:
		var cap: float = maxf(1.0, _gold.treasury_capacity)
		context["orb_t"] = clampf(_gold.treasury_charge / cap, 0.0, 1.0)

	# One-frame "activated" flash on Royal Wealth start.
	if _gold.royal_wealth_active and not _rw_was_active:
		context["activated"] = true
	_rw_was_active = _gold.royal_wealth_active

func _configure_manager() -> void:
	var capacity:  float = get_stat("fortune_capacity")
	var rw_dur:    float = get_stat("duration")
	var decay_del: float = get_stat("fortune_decay_delay")
	var decay_r:   float = get_stat("fortune_decay_rate")
	var treas_cap: float = get_stat("treasury_capacity")
	if capacity  > 0.0: _gold.fortune_capacity     = capacity
	if rw_dur    > 0.0: _gold.royal_wealth_duration = rw_dur
	if decay_del > 0.0: _gold._decay_delay          = decay_del
	if decay_r   > 0.0: _gold._decay_rate           = decay_r
	if treas_cap > 0.0: _gold.treasury_capacity     = treas_cap
	else:               _gold.treasury_capacity     = DEFAULT_TREASURY_CAPACITY
