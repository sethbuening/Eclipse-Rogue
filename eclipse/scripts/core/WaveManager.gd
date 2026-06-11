# wave_manager.gd
extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  DESIGN — DRG Survivor style
#
#  Instead of anonymous random spawning, pressure arrives as named ENCOUNTERS
#  that the player can read and respond to:
#
#  TRICKLE   — constant low-level background pressure; never stops.
#  SWARM     — a large fast wave from one direction; telegraphed by direction.
#  PATROL    — a tight squad of mid-cost enemies that march across the map.
#  TITAN     — one or two high-cost elite enemies, possibly with bodyguards.
#  CROSSFIRE — two simultaneous smaller squads from opposite directions.
#  HORDE     — periodic mass event; cheap enemies flood the screen.
#  FORGE     — forge-exclusive enemies layered on top while forging.
#
#  Encounters are drawn from a weighted deck that evolves over time.
#  Early game: mostly Swarms and Patrols.
#  Mid game:   Crossfires and Titans unlock.
#  Late game:  all encounter types, higher budgets, faster trickle.
#
#  Time is the only difficulty axis — no wave counter.
# ─────────────────────────────────────────────────────────────────────────────

@export_group("Roster")
@export var roster_path: String = "res://data/enemies/"

@export_group("Trickle")
## Spawn interval at t=0.
@export var trickle_interval_start: float = 1.2
## Fastest trickle interval (floor).
@export var trickle_interval_min:   float = 0.18
## Minutes until trickle reaches its minimum.
@export var trickle_ramp_minutes:   float = 12.0
@export var trickle_variance:       float = 0.08

@export_group("Encounters")
## How often an encounter event is triggered (seconds).
@export var encounter_period:          float = 18.0
@export var encounter_period_variance: float = 4.0

@export_group("Horde Events")
@export var horde_every_minutes: float = 2.0
@export var horde_size:          int   = 80
@export var horde_spawn_step:    float = 0.03

@export_group("Budget / Scaling")
@export var base_budget:         int   = 5
@export var budget_per_minute:   float = 2.2
@export var budget_cap:          int   = 80

@export_group("Forging")
@export var forge_spawn_interval: float = 0.22
@export var forge_budget_mult:    float = 2.5

@export_group("Timing")
@export var first_spawn_delay:    float = 3.0

# ── encounter types ───────────────────────────────────────────────────────────

enum Encounter {
	SWARM,      # Large fast mob from one direction
	PATROL,     # Tight mid-cost squad, marches through
	TITAN,      # 1-2 elite enemies + optional bodyguards
	CROSSFIRE,  # Two squads from opposite directions simultaneously
	HORDE,      # Mass cheap flood (also fires on timer)
}

# ── internal state ────────────────────────────────────────────────────────────

var _normal_roster: Array[EnemyData] = []
var _forge_roster:  Array[EnemyData] = []

var _elapsed:          float = 0.0
var _spawn_timer:      float = 0.0
var _encounter_timer:  float = 0.0
var _horde_timer:      float = 0.0
var _horde_queue:      int   = 0
var _horde_step_acc:   float = 0.0
var _is_forging:       bool  = false
var _paused:           bool  = false
var _enemies_alive:    int   = 0

# ── signals ───────────────────────────────────────────────────────────────────

signal encounter_started(type: Encounter)
signal horde_started()
signal forging_wave_started()
signal forging_wave_ended()

# ── lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	EnemyManager.enemy_died.connect(_on_enemy_died)
	_build_rosters()
	_spawn_timer     = first_spawn_delay
	_encounter_timer = encounter_period + randf_range(-encounter_period_variance, encounter_period_variance)
	_horde_timer     = horde_every_minutes * 60.0

func _build_rosters() -> void:
	_normal_roster.clear()
	_forge_roster.clear()
	for res: Resource in Util.load_resources(roster_path):
		if not res is EnemyData:
			push_warning("WaveManager: skipping non-EnemyData at " + res.resource_path)
			continue
		if res.cost == 0:
			continue
		if res.is_forge_exclusive:
			_forge_roster.append(res)
		else:
			_normal_roster.append(res)
	Log("Rosters built — normal: %d  forge: %d" % [_normal_roster.size(), _forge_roster.size()])

# ── main loop ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _paused:
		return
	_elapsed += delta
	_tick_trickle(delta)
	_tick_encounter(delta)
	_tick_horde(delta)

# ── trickle ───────────────────────────────────────────────────────────────────

func _tick_trickle(delta: float) -> void:
	_spawn_timer += delta
	var interval := _trickle_interval()
	if _is_forging:
		interval = forge_spawn_interval
	interval += randf_range(-trickle_variance, trickle_variance)
	interval  = maxf(0.1, interval)
	if _spawn_timer >= interval:
		_spawn_timer = 0.0
		_do_trickle_spawn()

func _trickle_interval() -> float:
	var t := clampf(_elapsed / (trickle_ramp_minutes * 60.0), 0.0, 1.0)
	return lerpf(trickle_interval_start, trickle_interval_min, t)

func _do_trickle_spawn() -> void:
	var pool := _eligible_pool()
	if pool.is_empty():
		return
	# Trickle always spawns a single cheap enemy — background noise, not a threat
	pool.sort_custom(func(a: EnemyData, b: EnemyData): return a.cost < b.cost)
	var affordable := pool.filter(func(e: EnemyData): return e.cost <= 2)
	if affordable.is_empty():
		affordable = pool
	var pick: EnemyData = affordable[randi() % affordable.size()]
	var modifier := Util.Modifier.NONE
	if _is_forging:
		modifier = Util.Modifier.ALERTED
	EnemyManager.spawn_enemy(pick, modifier)
	_enemies_alive += 1

# ── encounter scheduling ──────────────────────────────────────────────────────

func _tick_encounter(delta: float) -> void:
	_encounter_timer -= delta
	if _encounter_timer <= 0.0:
		_fire_encounter()
		_encounter_timer = encounter_period \
			+ randf_range(-encounter_period_variance, encounter_period_variance)

func _fire_encounter() -> void:
	var type := _pick_encounter()
	emit_signal("encounter_started", type)
	Log("ENCOUNTER — %s at %.1fs" % [Encounter.keys()[type], _elapsed])
	match type:
		Encounter.SWARM:     _encounter_swarm()
		Encounter.PATROL:    _encounter_patrol()
		Encounter.TITAN:     _encounter_titan()
		Encounter.CROSSFIRE: _encounter_crossfire()
		Encounter.HORDE:     _trigger_horde()

func _pick_encounter() -> Encounter:
	var minutes := _elapsed / 60.0
	# Weighted deck — options unlock progressively
	# [encounter_type, weight]
	var deck: Array = [
		[Encounter.SWARM,  3.0],
		[Encounter.PATROL, 2.0],
	]
	if minutes >= 3.0:
		deck.append([Encounter.TITAN,     1.5])
	if minutes >= 5.0:
		deck.append([Encounter.CROSSFIRE, 1.5])
		deck[0][1] = 2.5  # swarm weight drops slightly once crossfire is live
	if minutes >= 8.0:
		deck.append([Encounter.HORDE,     1.0])

	# Increase TITAN weight in late game
	if minutes >= 10.0:
		for entry in deck:
			if entry[0] == Encounter.TITAN:
				entry[1] = 2.5

	var total: float = 0.0
	for entry in deck:
		total += entry[1]
	var roll := randf() * total
	var cumul: float = 0.0
	for entry in deck:
		cumul += entry[1]
		if roll < cumul:
			return entry[0]
	return Encounter.SWARM

# ── encounter implementations ─────────────────────────────────────────────────

func _encounter_swarm() -> void:
	# Large wave from a single direction — high count, cheap enemies, FAST modifier
	var pool   := _eligible_pool()
	if pool.is_empty(): return
	var budget := _current_budget() * 6
	var squad  := _build_squad(budget, pool, "cheapest")
	EnemyManager.spawn_squad(squad, Util.Modifier.FAST)
	_enemies_alive += squad.size()
	Log("Swarm — %d units" % squad.size())

func _encounter_patrol() -> void:
	# Mid-cost enemies in CLUSTERED formation — feels like a squad moving through
	var pool   := _eligible_pool()
	if pool.is_empty(): return
	var budget := _current_budget() * 4
	# Prefer mid-cost enemies (cost 2-4)
	var mid_pool := pool.filter(func(e: EnemyData): return e.cost >= 2 and e.cost <= 4)
	if mid_pool.is_empty(): mid_pool = pool
	var squad  := _build_squad(budget, mid_pool, "random")
	EnemyManager.spawn_squad(squad, Util.Modifier.CLUSTERED)
	_enemies_alive += squad.size()
	Log("Patrol — %d units" % squad.size())

func _encounter_titan() -> void:
	# 1-2 expensive enemies, plus cheap bodyguards
	var pool   := _eligible_pool()
	if pool.is_empty(): return

	# Pick an elite (most expensive affordable)
	pool.sort_custom(func(a: EnemyData, b: EnemyData): return a.cost > b.cost)
	var budget := _current_budget() * 4
	var elite: EnemyData = pool[0]
	EnemyManager.spawn_enemy(elite, Util.Modifier.ALERTED)
	_enemies_alive += 1
	budget -= elite.cost

	# Optional second elite if budget allows
	if budget >= elite.cost:
		EnemyManager.spawn_enemy(elite, Util.Modifier.ALERTED)
		_enemies_alive += 1
		budget -= elite.cost

	# Fill remainder with cheap bodyguards
	var cheap := pool.filter(func(e: EnemyData): return e.cost <= 2)
	if not cheap.is_empty() and budget > 0:
		var guards := _build_squad(budget, cheap, "cheapest")
		EnemyManager.spawn_squad(guards, Util.Modifier.NONE)
		_enemies_alive += guards.size()
	Log("Titan — elite + %d bodyguards" % _enemies_alive)

func _encounter_crossfire() -> void:
	# Two separate squads spawned back-to-back — EnemyManager handles direction
	# by varying spawn side. We just spawn two affordable squads with ALERTED.
	var pool   := _eligible_pool()
	if pool.is_empty(): return
	var half   := maxi(1, _current_budget() * 2)
	var squad_a := _build_squad(half, pool, "random")
	var squad_b := _build_squad(half, pool, "cheapest")
	EnemyManager.spawn_squad(squad_a, Util.Modifier.ALERTED)
	EnemyManager.spawn_squad(squad_b, Util.Modifier.FAST)
	_enemies_alive += squad_a.size() + squad_b.size()
	Log("Crossfire — %d + %d units" % [squad_a.size(), squad_b.size()])

# ── horde ─────────────────────────────────────────────────────────────────────

func _tick_horde(delta: float) -> void:
	if _horde_queue > 0:
		_horde_step_acc += delta
		while _horde_step_acc >= horde_spawn_step and _horde_queue > 0:
			_horde_step_acc -= horde_spawn_step
			_spawn_horde_unit()
			_horde_queue -= 1
		return
	_horde_timer -= delta
	if _horde_timer <= 0.0:
		_trigger_horde()

func _trigger_horde() -> void:
	_horde_queue    = horde_size
	_horde_step_acc = 0.0
	_horde_timer    = horde_every_minutes * 60.0
	emit_signal("horde_started")
	Log("HORDE — %d incoming" % horde_size)

func _spawn_horde_unit() -> void:
	var pool := _eligible_pool()
	if pool.is_empty(): return
	pool.sort_custom(func(a: EnemyData, b: EnemyData): return a.cost < b.cost)
	EnemyManager.spawn_enemy(pool[0], Util.Modifier.CLUSTERED)
	_enemies_alive += 1

# ── squad building ────────────────────────────────────────────────────────────

func _build_squad(budget: int, pool: Array, style: String) -> Array[EnemyData]:
	var squad:     Array[EnemyData] = []
	var remaining: int              = budget
	var sorted := pool.duplicate()
	match style:
		"cheapest":  sorted.sort_custom(func(a, b): return a.cost < b.cost)
		"costliest": sorted.sort_custom(func(a, b): return a.cost > b.cost)
		"random":    sorted.shuffle()

	while remaining > 0:
		var affordable: Array = sorted.filter(func(e: EnemyData): return e.cost <= remaining)
		if affordable.is_empty():
			break
		squad.append(affordable[0])
		remaining -= affordable[0].cost
	return squad

# ── pool ──────────────────────────────────────────────────────────────────────

# WaveManager.gd — _eligible_pool()
func _eligible_pool() -> Array[EnemyData]:
	var minutes := _elapsed / 60.0
	var pool: Array[EnemyData] = _normal_roster.filter(
		# min_wave 0 or 1 = available immediately; higher values gate by time
		func(e: EnemyData): return minutes >= float(maxi(0, e.min_wave - 1)) * 1.5
	)
	if _is_forging:
		for e: EnemyData in _forge_roster:
			pool.append(e)
	return pool

# ── budget ────────────────────────────────────────────────────────────────────

func _current_budget() -> int:
	var minutes := _elapsed / 60.0
	var b := float(base_budget) + minutes * budget_per_minute
	if _is_forging:
		b *= forge_budget_mult
	return mini(budget_cap, maxi(1, int(b)))

# ── forging ───────────────────────────────────────────────────────────────────

func begin_forging() -> void:
	if _is_forging: return
	_is_forging = true
	emit_signal("forging_wave_started")
	Log("Forging started")

func end_forging() -> void:
	if not _is_forging: return
	_is_forging = false
	emit_signal("forging_wave_ended")
	Log("Forging ended")

## Permanently adds enemies from a forged metal's enemy_pool to the normal
## roster for the rest of the run.  Duplicates (same resource) are ignored.
func add_to_normal_roster(enemies: Array[EnemyData]) -> void:
	for enemy: EnemyData in enemies:
		if enemy.cost == 0:
			continue
		if _normal_roster.has(enemy):
			continue
		_normal_roster.append(enemy)
		Log("Added to roster: %s" % enemy.display_name)

# ── enemy tracking ────────────────────────────────────────────────────────────

func _on_enemy_died(_enemy: Enemy) -> void:
	_enemies_alive = maxi(0, _enemies_alive - 1)

# ── level lifecycle ───────────────────────────────────────────────────────────

func on_level_changed() -> void:
	_elapsed       = 0.0
	_enemies_alive = 0
	_is_forging    = false
	_horde_queue   = 0
	_horde_timer   = horde_every_minutes * 60.0
	_spawn_timer   = first_spawn_delay
	_encounter_timer = encounter_period + randf_range(-encounter_period_variance, encounter_period_variance)
	EnemyManager.on_level_changed()

# ── pause ─────────────────────────────────────────────────────────────────────

func pause_waves() -> void:  _paused = true
func resume_waves() -> void: _paused = false

# ── util ──────────────────────────────────────────────────────────────────────

func Log(msg: Variant) -> void:
	print("[WaveManager] " + str(msg))
