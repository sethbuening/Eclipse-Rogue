class_name Forge
extends Node2D

@export var base_forge_duration:   float = 30.0
@export var heat_duration_scale:   float = 2.0
@export var base_wave_interval:    float = 60.0
@export var min_wave_interval:     float = 10.0
@export var max_wave_interval:     float = 45.0
@export var interaction_radius:    float = 48.0
@export var HEAT_MULTIPLIER:       float = 0.5

# ── proximity forging ─────────────────────────────────────────────────────────
# Radius the player must stay inside for forging to progress.
@export var forge_proximity_radius: float = 180.0
# How long (seconds) the forge can sit stalled before it cancels.
@export var forge_stall_cancel_time: float = 8.0

enum State { IDLE, OPEN, FORGING, COMPLETE, CANCELLED }

var state:         State         = State.IDLE
var input_orbs:    Array[Orb]    = []
var metal_counts:  Dictionary    = {}
var result:        ForgeResult   = null

var forge_timer:   float = 0.0
var forge_duration:float = 0.0
var wave_timer:    float = 0.0
var wave_interval: float = 0.0

# Stall tracking
var _stall_timer:  float = 0.0   # accumulates while player is out of range
var _player_in_forge_range: bool = true

# ── player + interaction ─────────────────────────────────────────────
var _player: CharacterBody2D = null
var _interactable: bool = false

# ── prompt UI ────────────────────────────────────────────────────────
var _prompt_box:   HBoxContainer = null
var _prompt_icon:  TextureRect   = null
var _prompt_label: Label         = null

const PROMPT_OFFSET := Vector2(-60, -60)

# ── signals ──────────────────────────────────────────────────────────
signal forge_complete(result: ForgeResult)
signal forge_cancelled
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

	if not player_in_range.is_connected(_player._on_forge_in_range):
		player_in_range.connect(_player._on_forge_in_range)

	if not player_out_of_range.is_connected(_player._on_forge_out_of_range):
		player_out_of_range.connect(_player._on_forge_out_of_range)

	_build_prompt()
	Util.input_device_changed.connect(_update_prompt_icon)

# ── READY ─────────────────────────────────────────────────────────────
func _ready() -> void:
	$InteractArea.body_entered.connect(_on_body_entered)
	$InteractArea.body_exited.connect(_on_body_exited)

	# Draw on top of tilemaps
	z_index = 10

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
		if _prompt_box and state == State.IDLE:
			_prompt_box.visible = true

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

	_stall_timer = 0.0
	_player_in_forge_range = _is_player_in_forge_range()

	state = State.FORGING
	WaveManager.begin_forging()

	if _prompt_box:
		_prompt_box.visible = false

	emit_signal("forge_closed")

# ── PROCESS ───────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")

	# ── prompt (ONLY IDLE) ───────────────────────────────────────────
	if state != State.IDLE:
		if _prompt_box:
			_prompt_box.visible = false

	# ── forging ──────────────────────────────────────────────────────
	if state != State.FORGING:
		return

	# Update proximity
	_player_in_forge_range = _is_player_in_forge_range()

	if _player_in_forge_range:
		# Player is in range — progress normally, reset stall timer
		_stall_timer = 0.0
		forge_timer += delta
		wave_timer  += delta

		if wave_timer >= wave_interval:
			wave_timer = 0.0
			_spawn_forge_wave()

		if forge_timer >= forge_duration:
			_complete()
	else:
		# Player is out of range — stall progress, count down to cancel
		_stall_timer += delta
		if _stall_timer >= forge_stall_cancel_time:
			_cancel()

	# Redraw the proximity ring every frame while forging
	if state == State.FORGING:
		queue_redraw()

# ── helpers ───────────────────────────────────────────────────────────
func _is_player_in_forge_range() -> bool:
	if _player == null:
		return false
	return _player.global_position.distance_to(global_position) <= forge_proximity_radius

# Returns 0–1 fraction of stall cancel progress (0 = fresh, 1 = about to cancel)
func get_stall_fraction() -> float:
	if forge_stall_cancel_time <= 0.0:
		return 0.0
	return clampf(_stall_timer / forge_stall_cancel_time, 0.0, 1.0)

func is_player_in_forge_range() -> bool:
	return _player_in_forge_range

# ── WAVE SPAWNING ────────────────────────────────────────────────────
func _spawn_forge_wave() -> void:
	var budget := result.heat
	var squad:  Array[EnemyData] = []
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
		var pick: EnemyData = affordable[0]

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

# ── COMPLETE / CANCEL ─────────────────────────────────────────────────
func _complete() -> void:
	state = State.COMPLETE
	WaveManager.end_forging()

	if _prompt_box:
		_prompt_box.visible = false

	emit_signal("forge_complete", result)

func _cancel() -> void:
	state = State.CANCELLED
	WaveManager.end_forging()

	if _prompt_box:
		_prompt_box.visible = false

	emit_signal("forge_cancelled")

# ── DRAW — proximity ring ────────────────────────────────────────────
func _draw() -> void:
	if state != State.FORGING:
		return

	var in_range: bool = _player_in_forge_range

	if in_range:
		# Soft green ring: player is inside
		draw_arc(Vector2.ZERO, forge_proximity_radius, 0.0, TAU, 64,
			Color(0.3, 0.9, 0.4, 0.45), 2.0)
		# Very faint fill
		var fill_col := Color(0.3, 0.9, 0.4, 0.07)
		# Draw filled circle as a polygon
		var pts := PackedVector2Array()
		for i in 48:
			var a: float = (float(i) / 48.0) * TAU
			pts.append(Vector2(cos(a), sin(a)) * forge_proximity_radius)
		draw_colored_polygon(pts, fill_col)
	else:
		# Red/orange ring + stall bar warning
		var stall_frac: float = get_stall_fraction()
		var ring_col := Color(0.9, 0.35, 0.2, 0.55).lerp(Color(1.0, 0.15, 0.1, 0.85), stall_frac)
		draw_arc(Vector2.ZERO, forge_proximity_radius, 0.0, TAU, 64, ring_col, 3.0)

		# Dashed "come back" arc to show how much time is left before cancel
		# Draw the remaining-time arc in a dimmer red going clockwise from top
		var remain_frac: float = 1.0 - stall_frac
		if remain_frac > 0.01:
			var start_a: float = -PI * 0.5
			draw_arc(Vector2.ZERO, forge_proximity_radius + 6.0,
				start_a, start_a + remain_frac * TAU,
				max(8, int(remain_frac * 64)),
				Color(1.0, 0.6, 0.1, 0.75), 4.0)

# ── EXTERNAL HOOK ────────────────────────────────────────────────────
func set_interactable(enabled: bool) -> void:
	_interactable = enabled
	if _prompt_box:
		_prompt_box.visible = false
