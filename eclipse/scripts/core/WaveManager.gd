# wave_manager.gd
extends Node

@export var roster_path:        String = "res://data/enemies/"
@export var first_wave_delay:   float  = 120.0
@export var between_wave_time:  float  = 150.0
@export var wave_time_variance: float  = 30.0
@export var base_budget:        int    = 4
@export var budget_per_wave:    int    = 2

var enemy_roster:      Array[EnemyData] = []
var wave_number:       int              = 0
var enemies_alive:     int              = 0
var timer:             float            = 0.0
var current_threshold: float            = 0.0
var _paused:           bool             = false

signal wave_started(wave_number: int, modifier: Util.Modifier)
signal wave_cleared(wave_number: int)

func _ready() -> void:
	EnemyManager.enemy_died.connect(_on_enemy_died)
	_build_roster()
	current_threshold = first_wave_delay + randf_range(-wave_time_variance, wave_time_variance)

func _build_roster() -> void:
	enemy_roster.clear()
	for res: Resource in Util.load_resources(roster_path):
		if res is EnemyData:
			if (res.cost == 0):
				Log("Loaded enemy: " + res.id + " :and skipping because cost = 0")
				continue
			enemy_roster.append(res)
			Log("Loaded enemy: " + res.id)
		else:
			push_warning("WaveManager: skipping non-EnemyData resource: " + res.resource_path)
	Log("Roster built — %d enemies loaded" % enemy_roster.size())

func _process(delta: float) -> void:
	if _paused:
		return
	timer += delta
	if timer >= current_threshold:
		timer = 0.0
		_launch_wave()

func _launch_wave() -> void:
	wave_number      += 1
	current_threshold = between_wave_time + randf_range(-wave_time_variance, wave_time_variance)

	var budget:   int           = base_budget + (wave_number - 1) * budget_per_wave
	var modifier: Util.Modifier = _pick_modifier(wave_number)
	var roster:   Array         = enemy_roster.filter(func(e: EnemyData): return e.min_wave <= wave_number)
	var squad:    Array         = _build_squad(budget, roster)
	enemies_alive = squad.size()
	emit_signal("wave_started", wave_number, modifier)
	EnemyManager.spawn_squad(squad, modifier)
	Log("Wave " + str(wave_number) + " launched | budget: " + str(budget) + " | enemies: " + str(squad.size()) + " | modifier: " + str(modifier) + " | next wave in: " + str(snappedf(current_threshold, 0.1)) + "s")

func _build_squad(budget: int, roster: Array) -> Array[EnemyData]:
	var squad:     Array[EnemyData] = []
	var remaining: int              = budget
	var style:     int              = randi() % 3
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
				var weights:      Array[float] = [0.6, 0.3, 0.1]
				var roll:         float        = randf()
				var cumulative:   float        = 0.0
				var chosen_index: int          = 0
				for i in range(min(affordable.size(), weights.size())):
					cumulative += weights[i]
					if roll < cumulative:
						chosen_index = i
						break
				pick = affordable[chosen_index]
			1:
				affordable.shuffle()
				pick = affordable[0]
		squad.append(pick)
		remaining -= pick.cost
	return squad

func _pick_modifier(wave: int) -> Util.Modifier:
	if wave < 3:
		return Util.Modifier.NONE
	var pool: Array[Util.Modifier] = [Util.Modifier.NONE, Util.Modifier.NONE]
	if wave >= 3: pool.append(Util.Modifier.FAST)
	if wave >= 4: pool.append(Util.Modifier.TRICKLE)
	if wave >= 5: pool.append(Util.Modifier.ALERTED)
	if wave >= 6: pool.append(Util.Modifier.CLUSTERED)
	return pool[randi() % pool.size()]

func _on_enemy_died() -> void:
	enemies_alive -= 1
	if enemies_alive <= 0:
		emit_signal("wave_cleared", wave_number)
		Log("Wave " + str(wave_number) + " cleared")

func on_level_changed() -> void:
	timer             = 0.0
	wave_number       = 0
	current_threshold = first_wave_delay + randf_range(-wave_time_variance, wave_time_variance)
	EnemyManager.on_level_changed()

func pause_waves() -> void:
	_paused = true

func resume_waves() -> void:
	_paused = false

func Log(msg: Variant) -> void:
	print("[WaveManager.gd] " + str(msg))
