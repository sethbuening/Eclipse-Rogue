# gold_state.gd
# ---------------------------------------------------------------------------
# Autoload singleton — add as "GoldState" in Project > Autoloads.
#
# Central shared state for all Gold-metal abilities.  Individual abilities
# read and write through here rather than coupling to each other directly.
# No Gold ability class imports another Gold ability class.
#
# Game should call GoldState.reset() at the start of each run.
# King's Treasury calls GoldState.tick() every frame (it is always present
# when any Gold ability is equipped).
# ---------------------------------------------------------------------------
extends Node

# ── Fortune ───────────────────────────────────────────────────────────────────
var fortune:          float = 0.0
var fortune_capacity: float = 300.0      # set by King's Treasury stats
var _time_since_crit: float = 0.0
var _decay_delay:     float = 3.0        # set by King's Treasury stats
var _decay_rate:      float = 15.0       # set by King's Treasury stats
var decay_suspended:  bool  = false

# ── King's Treasury ───────────────────────────────────────────────────────────
var treasury_charge:       float = 0.0
var treasury_capacity:     float = 200.0
var royal_wealth_active:   bool  = false
var royal_wealth_timer:    float = 0.0
var royal_wealth_duration: float = 6.0
var _cascade_fired:        bool  = false  # guard: only cascade once per RW

# ── Fortune Engine ────────────────────────────────────────────────────────────
var engine_stacks:    int = 0
var engine_stack_cap: int = 8   # recalculated by Fortune Engine each tick

# ── Jackpot Wheel ─────────────────────────────────────────────────────────────
enum WheelOutcome {
	NONE,
	DOUBLE_CRIT,
	TRIPLE_CRIT,
	FORTUNE_BURST,
	GUARANTEED_CRITS,
	EXTRA_COINSTORM,
	BONUS_MARK,
}
var wheel_outcome: WheelOutcome = WheelOutcome.NONE
var wheel_ready:   bool         = false

# ── Midas Curse ───────────────────────────────────────────────────────────────
var marked_enemy:      Enemy = null
var bonus_mark_active: bool  = false
var _bonus_mark_timer: float = 0.0
const BONUS_MARK_DURATION: float = 4.0

# ── Rain of Crowns ────────────────────────────────────────────────────────────
var crowns_charge:      float = 0.0
var free_crown_pending: bool  = false

# ── signals ───────────────────────────────────────────────────────────────────
signal gold_crit_landed(crit_mult: float, world_pos: Vector2)
signal fortune_changed(new_value: float, capacity: float)
signal royal_wealth_started()
signal royal_wealth_ended()
signal wheel_spun(outcome: WheelOutcome)
signal mark_placed(enemy: Enemy)
signal mark_cleared()

# ── public API ────────────────────────────────────────────────────────────────

## Call after every Gold crit.  Returns engine_bonus (>= 1.0) for caller to
## multiply into their damage.  Handles: Fortune gain, treasury, engine reset,
## field consume, Royal Wealth cascade.
func on_gold_crit(
		world_pos:      Vector2,
		crit_mult:      float,
		trigger_radius: float,
		player:         CharacterBody2D
) -> float:
	_time_since_crit = 0.0
	add_fortune(crit_mult * 10.0, player)

	var engine_bonus: float = 1.0
	if engine_stacks > 0:
		engine_bonus  = 1.0 + (engine_stacks * 0.12)
		engine_stacks = 0

	treasury_charge += crit_mult * 5.0
	_check_royal_wealth(player)

	# StaticField consume: normal radius detonation every crit.
	StaticField.consume_at(world_pos, trigger_radius, crit_mult)

	# Royal Wealth: cascade ALL remaining fields simultaneously on the first crit.
	if royal_wealth_active and not _cascade_fired:
		_cascade_fired = true
		for field in StaticField._pool:
			if field._active:
				field._detonate(crit_mult)

	emit_signal("gold_crit_landed", crit_mult, world_pos)
	return engine_bonus

## Add Fortune, clamp to capacity, feed Crown charge.
func add_fortune(amount: float, player: CharacterBody2D) -> void:
	var old: float = fortune
	fortune = clampf(fortune + amount, 0.0, fortune_capacity)
	var gained: float = fortune - old
	if gained > 0.0:
		crowns_charge += gained
		emit_signal("fortune_changed", fortune, fortune_capacity)

## Spend Fortune.  Feeds Crown charge and returns amount actually spent.
func spend_fortune(amount: float) -> float:
	var spent: float = minf(fortune, amount)
	fortune = maxf(0.0, fortune - spent)
	crowns_charge += spent
	emit_signal("fortune_changed", fortune, fortune_capacity)
	return spent

## Main tick — called by King's Treasury every frame.
func tick(delta: float, player: CharacterBody2D) -> void:
	if not decay_suspended:
		_time_since_crit += delta
		if _time_since_crit > _decay_delay:
			var lost: float = _decay_rate * delta
			fortune = maxf(0.0, fortune - lost)
			crowns_charge += lost
			emit_signal("fortune_changed", fortune, fortune_capacity)

	if royal_wealth_active:
		royal_wealth_timer -= delta
		if royal_wealth_timer <= 0.0:
			_end_royal_wealth(player)

	if bonus_mark_active:
		_bonus_mark_timer -= delta
		if _bonus_mark_timer <= 0.0:
			bonus_mark_active = false

func place_mark(enemy: Enemy) -> void:
	marked_enemy = enemy
	emit_signal("mark_placed", enemy)

func clear_mark() -> void:
	marked_enemy = null
	emit_signal("mark_cleared")

func consume_wheel_outcome() -> WheelOutcome:
	var o: WheelOutcome = wheel_outcome
	wheel_outcome = WheelOutcome.NONE
	wheel_ready   = false
	return o

func reset() -> void:
	fortune = 0.0;  _time_since_crit = 0.0;  decay_suspended = false
	treasury_charge = 0.0;  royal_wealth_active = false;  royal_wealth_timer = 0.0
	_cascade_fired = false
	engine_stacks = 0;  engine_stack_cap = 8
	wheel_outcome = WheelOutcome.NONE;  wheel_ready = false
	marked_enemy = null;  bonus_mark_active = false;  _bonus_mark_timer = 0.0
	crowns_charge = 0.0;  free_crown_pending = false

# ── internal ──────────────────────────────────────────────────────────────────

func _check_royal_wealth(player: CharacterBody2D) -> void:
	if royal_wealth_active or treasury_charge < treasury_capacity:
		return
	treasury_charge = 0.0
	royal_wealth_active = true
	royal_wealth_timer  = royal_wealth_duration
	decay_suspended     = true
	_cascade_fired      = false
	player.guaranteed_crits += 20
	free_crown_pending = true
	emit_signal("royal_wealth_started")

func _end_royal_wealth(player: CharacterBody2D) -> void:
	royal_wealth_active = false
	decay_suspended     = false
	emit_signal("royal_wealth_ended")
