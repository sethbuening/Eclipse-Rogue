# wave_manager.gd
extends Node

# ── exports ───────────────────────────────────────────────────────────────────

@export_group("Roster")
@export var roster_path: String = "res://data/enemies/"

@export_group("Continuous Spawning")
## Base seconds between individual enemy spawns during a lull.
@export var lull_spawn_interval:   float = 4.0
## Base seconds between individual enemy spawns during a swell.
@export var swell_spawn_interval:  float = 0.8
## Variance applied to each spawn interval (±).
@export var spawn_interval_variance: float = 0.25
## How long a swell lasts (seconds).
@export var swell_duration:        float = 18.0
## How long a lull lasts (seconds).
@export var lull_duration:         float = 22.0
## Variance applied to swell/lull durations (±).
@export var phase_duration_variance: float = 6.0
## Delay before the very first enemy spawns.
@export var first_spawn_delay:     float = 5.0

@export_group("Budget / Scaling")
## Starting budget per spawn event.
@export var base_budget:      int = 2
## Extra budget added per minute of elapsed time.
@export var budget_per_minute: float = 0.5
## During a swell, budget is multiplied by this.
@export var swell_budget_mult: float = 1.5

@export_group("Forging")
## Forging must be triggered externally via begin_forging() / end_forging().
## Special enemies (is_forge_exclusive = true on EnemyData) only spawn while forging is active.
## During forging, modifiers are always at least ALERTED and the spawn interval is tightened.
@export var forge_spawn_interval:  float = 0.6
@export var forge_budget_mult:     float = 2.0

# ── state ─────────────────────────────────────────────────────────────────────

enum Phase { LULL, SWELL }

var _normal_roster:  Array[EnemyData] = []  # non-forge-exclusive enemies
var _forge_roster:   Array[EnemyData] = []  # forge-exclusive enemies

var _phase:          Phase = Phase.LULL
var _phase_timer:    float = 0.0
var _phase_duration: float = 0.0

var _spawn_timer:    float = 0.0
var _spawn_interval: float = 0.0

var _elapsed:        float = 0.0   # total time since level start
var _wave_number:    int   = 0     # increments each swell (used for modifier gating)
var _enemies_alive:  int   = 0

var _is_forging:     bool  = false
var _paused:         bool  = false

# ── signals ───────────────────────────────────────────────────────────────────

signal swell_started(swell_number: int)
signal swell_ended(swell_number: int)
signal forging_wave_started()
signal forging_wave_ended()

# ── lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	EnemyManager.enemy_died.connect(_on_enemy_died)
	_build_rosters()
	_enter_lull()
	_spawn_timer = first_spawn_delay   # honour the initial delay

func _build_rosters() -> void:
	_normal_roster.clear()
	_forge_roster.clear()
	for res: Resource in Util.load_resources(roster_path):
		if not res is EnemyData:
			push_warning("WaveManager: skipping non-EnemyData resource: " + res.resource_path)
			continue
		if res.cost == 0:
			Log("Skipping %s — cost = 0" % res.id)
			continue
		if res.is_forge_exclusive:
			_forge_roster.append(res)
			Log("Forge roster  ← %s" % res.id)
		else:
			_normal_roster.append(res)
			Log("Normal roster ← %s" % res.id)
	Log("Rosters built — normal: %d  forge: %d" % [_normal_roster.size(), _forge_roster.size()])

# ── main loop ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _paused:
		return

	_elapsed      += delta
	_phase_timer  += delta
	_spawn_timer  += delta

	# Phase transitions (lull ↔ swell). Forging overrides phase visually but
	# we still tick phases so the rhythm resumes naturally after forging ends.
	if _phase_timer >= _phase_duration:
		_phase_timer = 0.0
		if _phase == Phase.LULL:
			_enter_swell()
		else:
			_enter_lull()

	# Spawn tick
	var interval: float = _current_spawn_interval()
	if _spawn_timer >= interval:
		_spawn_timer = 0.0
		_spawn_enemy()

# ── phase management ──────────────────────────────────────────────────────────

func _enter_lull() -> void:
	_phase          = Phase.LULL
	_phase_duration = lull_duration + randf_range(-phase_duration_variance, phase_duration_variance)
	Log("Phase → LULL  (%.1fs)" % _phase_duration)

func _enter_swell() -> void:
	_phase          = Phase.SWELL
	_phase_duration = swell_duration + randf_range(-phase_duration_variance, phase_duration_variance)
	_wave_number   += 1
	emit_signal("swell_started", _wave_number)
	Log("Phase → SWELL #%d  (%.1fs)" % [_wave_number, _phase_duration])

func _current_spawn_interval() -> float:
	var base: float
	if _is_forging:
		base = forge_spawn_interval
	elif _phase == Phase.SWELL:
		base = swell_spawn_interval
	else:
		base = lull_spawn_interval
	return maxf(0.1, base + randf_range(-spawn_interval_variance, spawn_interval_variance))

# ── spawning ──────────────────────────────────────────────────────────────────

func _spawn_enemy() -> void:
	var budget:   int           = _current_budget()
	var modifier: Util.Modifier = _pick_modifier()

	# Build the candidate pool
	var pool: Array[EnemyData] = _build_pool()
	if pool.is_empty():
		return

	var squad: Array[EnemyData] = _build_squad(budget, pool)
	if squad.is_empty():
		return

	_enemies_alive += squad.size()
	EnemyManager.spawn_squad(squad, modifier)
	Log("Spawned %d enemy/ies | budget %d | modifier %s | forging %s | phase %s" % [
		squad.size(), budget, Util.Modifier.keys()[modifier],
		str(_is_forging), Phase.keys()[_phase]
	])

func _build_pool() -> Array[EnemyData]:
	# Always filter by min_wave so early enemies don't flood late game.
	var pool: Array[EnemyData] = _normal_roster.filter(
		func(e: EnemyData): return e.min_wave <= _wave_number
	)
	if _is_forging and not _forge_roster.is_empty():
		# Mix forge-exclusive enemies into the pool during forging.
		for e: EnemyData in _forge_roster:
			if e.min_wave <= _wave_number:
				pool.append(e)
	return pool

func _build_squad(budget: int, roster: Array) -> Array[EnemyData]:
	var squad:     Array[EnemyData] = []
	var remaining: int              = budget
	var style:     int              = randi() % 3   # 0=cheapest-first  1=random  2=costliest-first

	match style:
		0: roster.sort_custom(func(a: EnemyData, b: EnemyData): return a.cost < b.cost)
		2: roster.sort_custom(func(a: EnemyData, b: EnemyData): return a.cost > b.cost)

	while remaining > 0:
		var affordable: Array = roster.filter(func(e: EnemyData): return e.cost <= remaining)
		if affordable.is_empty():
			break
		var pick: EnemyData
		match style:
			0, 2:
				var weights:    Array[float] = [0.6, 0.3, 0.1]
				var roll:       float        = randf()
				var cumulative: float        = 0.0
				var chosen:     int          = 0
				for i in range(mini(affordable.size(), weights.size())):
					cumulative += weights[i]
					if roll < cumulative:
						chosen = i
						break
				pick = affordable[chosen]
			1:
				affordable.shuffle()
				pick = affordable[0]
		squad.append(pick)
		remaining -= pick.cost
	return squad

# ── budget ────────────────────────────────────────────────────────────────────

func _current_budget() -> int:
	var minutes: float = _elapsed / 60.0
	var b: float       = float(base_budget) + minutes * budget_per_minute
	if _is_forging:
		b *= forge_budget_mult
	elif _phase == Phase.SWELL:
		b *= swell_budget_mult
	return maxi(1, int(b))

# ── modifiers ─────────────────────────────────────────────────────────────────

func _pick_modifier() -> Util.Modifier:
	var pool: Array[Util.Modifier] = [Util.Modifier.NONE, Util.Modifier.NONE]

	# Gate modifiers behind swell count so early game stays readable.
	if _wave_number >= 2: pool.append(Util.Modifier.FAST)
	if _wave_number >= 3: pool.append(Util.Modifier.TRICKLE)
	if _wave_number >= 4: pool.append(Util.Modifier.ALERTED)
	if _wave_number >= 5: pool.append(Util.Modifier.CLUSTERED)

	# During forging, guarantee at least ALERTED intensity.
	if _is_forging:
		pool = pool.filter(func(m): return m != Util.Modifier.NONE)
		if pool.is_empty():
			return Util.Modifier.ALERTED

	return pool[randi() % pool.size()]

# ── forging ───────────────────────────────────────────────────────────────────

## Call this when the player begins a forge action.
func begin_forging() -> void:
	if _is_forging:
		return
	_is_forging = true
	emit_signal("forging_wave_started")
	Log("Forging started — special enemies now active")

## Call this when forging completes or is cancelled.
func end_forging() -> void:
	if not _is_forging:
		return
	_is_forging = false
	emit_signal("forging_wave_ended")
	Log("Forging ended — special enemies locked out")

# ── enemy tracking ────────────────────────────────────────────────────────────

func _on_enemy_died() -> void:
	_enemies_alive = maxi(0, _enemies_alive - 1)

# ── level lifecycle ───────────────────────────────────────────────────────────

func on_level_changed() -> void:
	_elapsed      = 0.0
	_wave_number  = 0
	_enemies_alive = 0
	_is_forging   = false
	_spawn_timer  = first_spawn_delay
	_enter_lull()
	EnemyManager.on_level_changed()

# ── pause ─────────────────────────────────────────────────────────────────────

func pause_waves() -> void:
	_paused = true

func resume_waves() -> void:
	_paused = false

# ── util ──────────────────────────────────────────────────────────────────────

func Log(msg: Variant) -> void:
	print("[WaveManager] " + str(msg))
