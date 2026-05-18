# forge.gd
class_name Forge
extends Node2D

@export var base_forge_duration: float = 30.0
@export var heat_duration_scale: float = 2.0
@export var base_wave_interval:  float = 60.0
@export var min_wave_interval:   float = 10.0
@export var max_wave_interval:   float = 45.0
@export var interaction_radius:  float = 48.0

enum State { IDLE, OPEN, FORGING, COMPLETE }

var state:          State            = State.IDLE
var input_orbs:     Array[Orb]       = []
var metal_counts:   Dictionary       = {}
var result:         ForgeResult      = null
var forge_timer:    float            = 0.0
var forge_duration: float            = 0.0
var wave_timer:     float            = 0.0
var wave_interval:  float            = 0.0

signal forge_complete(result: ForgeResult)
signal forge_opened(forge: Forge)
signal forge_closed
signal player_in_range(forge: Forge)
signal player_out_of_range(forge: Forge)

# ── ready/init ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	$InteractArea.body_entered.connect(_on_body_entered)
	$InteractArea.body_exited.connect(_on_body_exited)

func init() -> void:
	player_in_range.connect(%Player._on_forge_in_range)
	player_out_of_range.connect(%Player._on_forge_out_of_range)
	
# ── proximity ─────────────────────────────────────────────────────────────────

func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		emit_signal("player_in_range", self)
		$InteractPrompt.show()

func _on_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		emit_signal("player_out_of_range", self)
		$InteractPrompt.hide()

# ── interaction ───────────────────────────────────────────────────────────────

func try_interact(player: Node2D) -> void:
	if state != State.IDLE:
		return
	if player.global_position.distance_to(global_position) > interaction_radius:
		return
	_open(player)

func _open(_player: Node2D) -> void:
	if state != State.IDLE:
		return
	state = State.OPEN
	$InteractPrompt.hide()
	emit_signal("forge_opened", self)

func deposit_orb(orb: Orb) -> void:
	input_orbs.append(orb)

func deposit_metal(metal: MetalData, count: int) -> void:
	metal_counts[metal] = metal_counts.get(metal, 0) + count

func withdraw_orb(orb: Orb) -> void:
	input_orbs.erase(orb)

func withdraw_metal(metal: MetalData, count: int) -> void:
	metal_counts[metal] = maxi(0, metal_counts.get(metal, 0) - count)
	if metal_counts[metal] == 0:
		metal_counts.erase(metal)

func compute_heat() -> int:
	var heat: int = 0
	for metal: MetalData in metal_counts:
		heat += metal.rarity * metal_counts[metal]
	return heat

func can_activate() -> bool:
	return not input_orbs.is_empty() or not metal_counts.is_empty()

func activate() -> void:
	if not can_activate():
		return
	result         = ForgeResult.compute(input_orbs, metal_counts)
	forge_duration = base_forge_duration + result.heat * heat_duration_scale
	forge_timer    = 0.0
	wave_interval  = clampf(base_wave_interval / result.heat, min_wave_interval, max_wave_interval)
	wave_timer     = 0.0
	state          = State.FORGING
	WaveManager.pause_waves()
	emit_signal("forge_closed")

# ── process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if state != State.FORGING:
		return
	forge_timer += delta
	wave_timer  += delta
	if wave_timer >= wave_interval:
		wave_timer = 0.0
		_spawn_forge_wave()
	if forge_timer >= forge_duration:
		_complete()

func _spawn_forge_wave() -> void:
	var budget:    int              = result.heat
	var squad:     Array[EnemyData] = []
	var remaining: int              = budget

	var total_metals: int = 0
	for metal: MetalData in metal_counts:
		total_metals += metal_counts[metal]

	while remaining > 0:
		var metal: MetalData = _pick_weighted_metal(total_metals)
		if metal == null:
			break
		var affordable: Array = metal.enemy_pool.filter(
			func(e: EnemyData): return e.cost <= remaining
		)
		if affordable.is_empty():
			break
		affordable.shuffle()
		var pick: EnemyData = affordable[0]
		squad.append(pick)
		remaining -= pick.cost

	if not squad.is_empty():
		EnemyManager.spawn_squad(squad, Util.Modifier.NONE)

func _pick_weighted_metal(total: int) -> MetalData:
	if total == 0:
		return null
	var roll:       int = randi() % total
	var cumulative: int = 0
	for metal: MetalData in metal_counts:
		cumulative += metal_counts[metal]
		if roll < cumulative:
			return metal
	return null

func _complete() -> void:
	state = State.COMPLETE
	WaveManager.resume_waves()
	emit_signal("forge_complete", result)
