class_name Forge
extends Node2D

@export var base_forge_duration: float = 30.0
@export var heat_duration_scale: float = 2.0
@export var base_wave_interval:  float = 60.0
@export var min_wave_interval:   float = 10.0
@export var max_wave_interval:   float = 45.0
@export var interaction_radius:  float = 48.0
@export var HEAT_MULTIPLIER:     float = 0.5

enum State { IDLE, OPEN, FORGING, COMPLETE }

var state: State = State.IDLE
var input_orbs: Array[Orb] = []
var metal_counts: Dictionary = {}
var result: ForgeResult = null

var forge_timer: float = 0.0
var forge_duration: float = 0.0
var wave_timer: float = 0.0
var wave_interval: float = 0.0

# ── player + interaction ─────────────────────────────────────────────
var _player: CharacterBody2D = null
var _interactable: bool = false

# ── prompt UI ────────────────────────────────────────────────────────
var _prompt_box: HBoxContainer = null
var _prompt_icon: TextureRect = null
var _prompt_label: Label = null

const PROMPT_OFFSET := Vector2(-60, -60)

# ── signals ──────────────────────────────────────────────────────────
signal forge_complete(result: ForgeResult)
signal forge_opened(forge: Forge)
signal forge_closed
signal player_in_range(forge: Forge)
signal player_out_of_range(forge: Forge)

# ── INIT (MUST be called by Game.gd) ────────────────────────────────
func init(player_ref: CharacterBody2D) -> void:
	_player = player_ref
	if _player == null:
		push_error("Forge.init(): player_ref is null")
		return

	# connect safely
	if not player_in_range.is_connected(_player._on_forge_in_range):
		player_in_range.connect(_player._on_forge_in_range)

	if not player_out_of_range.is_connected(_player._on_forge_out_of_range):
		player_out_of_range.connect(_player._on_forge_out_of_range)

	_build_prompt()
	Util.input_device_changed.connect(_update_prompt_icon)

# ── READY (no gameplay assumptions here anymore) ─────────────────────
func _ready() -> void:
	$InteractArea.body_entered.connect(_on_body_entered)
	$InteractArea.body_exited.connect(_on_body_exited)

	# ONLY fallback: do NOT connect signals here
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")

	if _prompt_box == null:
		_build_prompt()

# ── PROMPT SETUP ─────────────────────────────────────────────────────
func _build_prompt() -> void:
	_prompt_box = HBoxContainer.new()
	_prompt_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt_box.add_theme_constant_override("separation", 6)
	_prompt_box.visible = false
	add_child(_prompt_box)

	_prompt_icon = TextureRect.new()
	_prompt_icon.custom_minimum_size = Vector2(24, 24)
	_prompt_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_prompt_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_prompt_box.add_child(_prompt_icon)

	_prompt_label = Label.new()
	_prompt_label.text = "Open Forge"
	_prompt_box.add_child(_prompt_label)

	_prompt_box.position = PROMPT_OFFSET
	_prompt_box.z_as_relative = false
	_prompt_box.z_index = 4096

	_update_prompt_icon()

func _update_prompt_icon() -> void:
	if _prompt_icon == null:
		return
	_prompt_icon.texture = Util.get_action_icon("interact")

# ── INTERACTION AREA SIGNALS ────────────────────────────────────────
func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		emit_signal("player_in_range", self)

func _on_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		emit_signal("player_out_of_range", self)
		if _prompt_box:
			_prompt_box.visible = false

# ── INTERACTION ──────────────────────────────────────────────────────
func interact_request() -> void:
	if _player == null:
		return
	try_interact(_player)

func try_interact(player: Node2D) -> void:
	if state != State.IDLE:
		return
	if player.global_position.distance_to(global_position) > interaction_radius:
		return
	_open(player)

func _open(_player: Node2D) -> void:
	state = State.OPEN
	if _prompt_box:
		_prompt_box.visible = false
	emit_signal("forge_opened", self)

func _close() -> void:
	state = State.IDLE
	emit_signal("forge_closed")

# ── DEPOSIT / WITHDRAW ──────────────────────────────────────────────
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

# ── FORGE LOGIC ──────────────────────────────────────────────────────
func compute_heat() -> int:
	var heat := 0.0
	for metal: MetalData in metal_counts:
		heat += metal.rarity * metal_counts[metal] * HEAT_MULTIPLIER
	return int(heat)

func can_activate() -> bool:
	return not input_orbs.is_empty() or not metal_counts.is_empty()

func activate() -> void:
	if not can_activate():
		return

	result = ForgeResult.compute(input_orbs, metal_counts)

	forge_duration = base_forge_duration + result.heat * heat_duration_scale
	forge_timer = 0.0

	wave_interval = clampf(
		base_wave_interval / max(result.heat, 1),
		min_wave_interval,
		max_wave_interval
	)
	wave_timer = 0.0

	state = State.FORGING
	WaveManager.pause_waves()

	if _prompt_box:
		_prompt_box.visible = false

	emit_signal("forge_closed")

# ── PROCESS ───────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")

	# ── prompt (ONLY IDLE) ───────────────────────────────────────────
	if state == State.IDLE and _player != null:
		var dist := global_position.distance_to(_player.global_position)
		var nearby := dist <= interaction_radius

		if _prompt_box:
			_prompt_box.visible = nearby
	else:
		if _prompt_box:
			_prompt_box.visible = false

	# ── forging ──────────────────────────────────────────────────────
	if state != State.FORGING:
		return

	forge_timer += delta
	wave_timer += delta

	if wave_timer >= wave_interval:
		wave_timer = 0.0
		_spawn_forge_wave()

	if forge_timer >= forge_duration:
		_complete()

# ── WAVE SPAWNING ────────────────────────────────────────────────────
func _spawn_forge_wave() -> void:
	var budget := result.heat
	var squad: Array[EnemyData] = []
	var remaining := budget

	var total_metals := 0
	for metal: MetalData in metal_counts:
		total_metals += metal_counts[metal]

	while remaining > 0:
		var metal := _pick_weighted_metal(total_metals)
		if metal == null:
			break

		var affordable := metal.enemy_pool.filter(
			func(e: EnemyData): return e.cost <= remaining
		)

		if affordable.is_empty():
			break

		affordable.shuffle()
		var pick : Enemy = affordable[0]

		squad.append(pick)
		remaining -= pick.cost

	if not squad.is_empty():
		EnemyManager.spawn_squad(squad, Util.Modifier.NONE)

func _pick_weighted_metal(total: int) -> MetalData:
	if total <= 0:
		return null

	var roll := randi() % total
	var cumulative := 0

	for metal: MetalData in metal_counts:
		cumulative += metal_counts[metal]
		if roll < cumulative:
			return metal

	return null

# ── COMPLETE ─────────────────────────────────────────────────────────
func _complete() -> void:
	state = State.COMPLETE
	WaveManager.resume_waves()

	if _prompt_box:
		_prompt_box.visible = false

	emit_signal("forge_complete", result)

# ── EXTERNAL HOOK ────────────────────────────────────────────────────
func set_interactable(enabled: bool) -> void:
	_interactable = enabled
	if _prompt_box:
		_prompt_box.visible = false
