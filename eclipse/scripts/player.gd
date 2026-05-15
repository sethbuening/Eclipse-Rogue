# player.gd
extends CharacterBody2D

var light: float = 100.0

var movement_enabled: bool = true
@onready var speed: float = 100.0 * get_parent().scale.x

@export_group("Procedural Animation")
@export var head_offset:      Vector2 = Vector2(1, -28)
@export var body_offset:      Vector2 = Vector2(1, -15)
@export var bob_amount:       float   = 2.5

@export_group("Orb Orbit")
@export var orb_orbit_center: Vector2 = Vector2(1, -15)
@export var orb_orbit_radius: float   = 24.0
@export var orb_orbit_speed:  float   = 1.25
@export var orb_bob_amount:   float   = 1.5
@export var orb_reform_flash: float   = 0.2

@export_group("Focus Animation")
@export var focus_orbit_speed: float = 4.0

@export_group("Starting Orbs")
@export var starting_orb: Orb = preload("res://data/orbs/orb_focus_mine.tres")

# ── directional textures ──────────────────────────────────────────────────────
var head_up:    Texture2D = preload("res://art/player/head_up.png")
var head_right: Texture2D = preload("res://art/player/head_right.png")
var head_down:  Texture2D = preload("res://art/player/head_down.png")
var head_left:  Texture2D = preload("res://art/player/head_left.png")

var body_up:    Texture2D = preload("res://art/player/body_up.png")
var body_right: Texture2D = preload("res://art/player/body_right.png")
var body_down:  Texture2D = preload("res://art/player/body_down.png")
var body_left:  Texture2D = preload("res://art/player/body_left.png")

# ── focus constants ───────────────────────────────────────────────────────────
const FOCUS_BLOOM_MIN: float = 0.0
const FOCUS_BLOOM_MAX: float = 0.75
const FOCUS_GLOW_MIN:  float = 0.3
const FOCUS_GLOW_MAX:  float = 1.25
const FOCUS_DECAY:     float = 4.0

# ── orb visuals ───────────────────────────────────────────────────────────────
class OrbVisual:
	var sprite:         Sprite2D
	var shattered:      bool  = false
	var cooldown_age:   float = 0.0
	var cooldown:       float = 0.0
	var reform_flash:   float = 0.0
	var current_angle:  float = 0.0

var orb_visuals: Array[OrbVisual] = []
var orbit_time:  float            = 0.0

# ── state ─────────────────────────────────────────────────────────────────────
var env_t: float = 0.0
var time:  float = 0.0

var direction: Vector2i = Vector2i.DOWN:
	set(value):
		if direction == value:
			return
		direction = value
		match value:
			Vector2i.UP:
				$head.texture = head_up
				$body.texture = body_up
			Vector2i.RIGHT:
				$head.texture = head_right
				$body.texture = body_right
			Vector2i.DOWN:
				$head.texture = head_down
				$body.texture = body_down
			Vector2i.LEFT:
				$head.texture = head_left
				$body.texture = body_left
	get():
		return direction

# ── ready ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	$Inventory.orb_added.connect(_on_orb_added)
	$Inventory.orb_removed.connect(_on_orb_removed)
	$Inventory.add_orb(starting_orb.duplicate(true))

# ── orb visual management ─────────────────────────────────────────────────────
func _on_orb_added(orb: Orb) -> void:
	var ov            := OrbVisual.new()
	ov.sprite          = Sprite2D.new()
	ov.sprite.texture  = orb.sprite_texture
	ov.sprite.centered = true
	add_child(ov.sprite)
	var new_count: int = orb_visuals.size() + 1
	var new_index: int = orb_visuals.size()
	ov.current_angle   = orbit_time + (float(new_index) / float(new_count)) * TAU
	orb_visuals.append(ov)

func _on_orb_removed(orb: Orb) -> void:
	var idx: int = $Inventory.orbs.find(orb)
	if idx == -1 or idx >= orb_visuals.size():
		return
	orb_visuals[idx].sprite.queue_free()
	orb_visuals.remove_at(idx)

func shatter_orb(orb_index: int) -> void:
	if orb_index >= orb_visuals.size():
		return
	var ov:  OrbVisual = orb_visuals[orb_index]
	var orb: Orb       = $Inventory.orbs[orb_index]
	if ov.shattered:
		return
	ov.shattered      = true
	ov.cooldown_age   = 0.0
	ov.cooldown       = orb.primary_ability().stats.cooldown if orb.primary_ability() else 1.0
	ov.sprite.visible = false
	# freeze current_angle so the lerp has nothing to chase while shattered
	var count: int        = orb_visuals.size()
	var phase: float      = (float(orb_index) / float(count)) * TAU
	ov.current_angle      = orbit_time + phase
	ParticleManager.spawn_focus_spark(global_position + ov.sprite.position)

func store_light_in_orb(orb_index: int, amount: float) -> void:
	if orb_index >= $Inventory.orbs.size():
		return
	$Inventory.orbs[orb_index].store_light(amount)
	ParticleManager.spawn_focus_particles(global_position, 1.0)

# ── context helpers ───────────────────────────────────────────────────────────
func _make_context(delta: float, pressed: bool, orb_index: int) -> Dictionary:
	var ov: OrbVisual = orb_visuals[orb_index]
	return {
		"player":        self,
		"tilemap":       %TilemapManager,
		"delta":         delta,
		"pressed":       pressed,
		"lock_movement": false,
		"env_target":    0.0,
		"orb_t":         0.0,
		"shatter":       false,
		"orb_shattered": ov.shattered,
	}

func _read_context(context: Dictionary, orb_index: int, max_env: float, max_t: float) -> Vector2:
	if context["shatter"]:
		shatter_orb(orb_index)
	if context["lock_movement"]:
		movement_enabled = false
	return Vector2(
		maxf(max_env, context["env_target"]),
		maxf(max_t,   context["orb_t"])
	)

# ── process ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	time            += delta
	z_index          = %TilemapManager.get_z_for(global_position)
	movement_enabled = true
	
	# ── head/body bob ───────────────────────────────────────────────────────────
	$head.offset = head_offset + Vector2(
		0,
		round(bob_amount * sin(time * 2.0))
	)
	$body.offset = body_offset + Vector2(
		0,
		round(bob_amount * sin(time * 2.0 + 0.5))
	)
	
	_update_orb_visuals(delta, env_t)

	var max_env_target: float = 0.0
	var max_orb_t:      float = 0.0
	var orbs: Array[Orb]      = $Inventory.orbs

	for i in range(orbs.size()):
		var orb:     Orb         = orbs[i]
		var ability: AbilityData = orb.primary_ability()

		# ── passive — fire every frame ────────────────────────────────────────
		var passive_ctx: Dictionary = _make_context(delta, false, i)
		orb.activate_trigger(AbilityData.TriggerType.PASSIVE, passive_ctx)
		var passive_out: Vector2 = _read_context(passive_ctx, i, max_env_target, max_orb_t)
		max_env_target = passive_out.x
		max_orb_t      = passive_out.y

		# ── active — skip if no keybind or no active ability ──────────────────
		if orb.input_action == "" or ability == null or ability.trigger_type != AbilityData.TriggerType.ACTIVE:
			continue

		if ability.requires_hold:
			# ── held ability — fire every frame while held, notify on release ─
			if Input.is_action_pressed(orb.input_action):
				var held_ctx: Dictionary = _make_context(delta, true, i)
				orb.activate_trigger(AbilityData.TriggerType.ACTIVE, held_ctx)
				var held_out: Vector2 = _read_context(held_ctx, i, max_env_target, max_orb_t)
				max_env_target = held_out.x
				max_orb_t      = held_out.y
			elif Input.is_action_just_released(orb.input_action):
				var released_ctx: Dictionary = _make_context(delta, false, i)
				ability.activate(released_ctx)
				var released_out: Vector2 = _read_context(released_ctx, i, max_env_target, max_orb_t)
				max_env_target = released_out.x
				max_orb_t      = released_out.y
		else:
			# ── instant ability — fire once on press ──────────────────────────
			if Input.is_action_just_pressed(orb.input_action):
				var instant_ctx: Dictionary = _make_context(delta, true, i)
				orb.activate_trigger(AbilityData.TriggerType.ACTIVE, instant_ctx)
				var instant_out: Vector2 = _read_context(instant_ctx, i, max_env_target, max_orb_t)
				max_env_target = instant_out.x
				max_orb_t      = instant_out.y

	# ── post-loop player effects ──────────────────────────────────────────────
	env_t = lerpf(env_t, max_env_target, FOCUS_DECAY * delta)
	_set_env(env_t)

	var t: float = max_orb_t
	if t > 0.0:
		%body.self_modulate = Color(lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t))
		%head.self_modulate = Color(lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t))
	else:
		%body.self_modulate = Color.WHITE
		%head.self_modulate = Color.WHITE

	if Input.is_action_just_pressed("dev_mode"):
		if $CollisionShape2D.disabled:
			speed /= 10.0
			$CollisionShape2D.disabled = false
		else:
			speed *= 10.0
			$CollisionShape2D.disabled = true
	if Input.is_action_just_pressed("zoom_in"):
		$"../Camera2D".zoom *= 2.0
	if Input.is_action_just_pressed("zoom_out"):
		$"../Camera2D".zoom *= 0.5
	if Input.is_action_just_pressed("dev_call_wave"):
		WaveManager.timer = 0.0
		WaveManager._launch_wave()

# ── orb visual update ─────────────────────────────────────────────────────────
func _update_orb_visuals(delta: float, focus_t: float = 0.0) -> void:
	var total: int = orb_visuals.size()
	if total == 0:
		return

	var orbit_speed_mult: float = lerpf(1.0, focus_orbit_speed, focus_t) if focus_t > 0.0 else 1.0
	orbit_time += delta * orb_orbit_speed * orbit_speed_mult

	# build active index list — shattered orbs are excluded from the formation
	var active_indices: Array[int] = []
	for i in range(total):
		if not orb_visuals[i].shattered:
			active_indices.append(i)

	var active_count: int = active_indices.size()

	for i in range(total):
		var ov:  OrbVisual = orb_visuals[i]
		var orb: Orb       = $Inventory.orbs[i]

		# ── shatter / cooldown ────────────────────────────────────────────────
		if ov.shattered:
			ov.cooldown_age  += delta
			ov.sprite.visible = false
			if ov.cooldown_age >= ov.cooldown:
				ov.shattered     = false
				ov.reform_flash  = orb_reform_flash
				ov.sprite.visible  = true
				for ability: AbilityData in orb.abilities:
					if ability is AbilityFocusMine:
						(ability as AbilityFocusMine).reset_exploded()
			continue

		# ── active: find this orb's slot in the active formation ──────────────
		var slot:         int   = active_indices.find(i)
		var target_angle: float = orbit_time + (float(slot) / float(active_count)) * TAU

		# ── lerp angle toward target ──────────────────────────────────────────
		var angle_diff:  float = wrapf(target_angle - ov.current_angle, -PI, PI)
		ov.current_angle      += angle_diff * minf(10.0 * delta, 1.0)

		# ── modulate ──────────────────────────────────────────────────────────
		if ov.reform_flash > 0.0:
			ov.reform_flash        -= delta
			var flash_t: float      = ov.reform_flash / orb_reform_flash
			ov.sprite.self_modulate = Color(lerpf(1.0, 4.0, flash_t), lerpf(1.0, 4.0, flash_t), lerpf(1.0, 4.0, flash_t))
		elif focus_t > 0.0:
			ov.sprite.self_modulate = Color(lerpf(1.0, 3.0, focus_t), lerpf(1.0, 3.0, focus_t), lerpf(1.0, 3.0, focus_t))
		else:
			ov.sprite.self_modulate = Color.WHITE

		# ── position ──────────────────────────────────────────────────────────
		ov.sprite.position = _angle_to_orbit_pos(ov.current_angle)
		ov.sprite.scale    = Vector2.ONE

func _angle_to_orbit_pos(angle: float) -> Vector2:
	return Vector2(cos(angle), sin(angle)) * orb_orbit_radius + orb_orbit_center

# ── physics process ───────────────────────────────────────────────────────────
func _physics_process(_delta: float) -> void:
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if input_vector != Vector2.ZERO:
		input_vector = input_vector.normalized()

	if movement_enabled:
		if input_vector != Vector2.ZERO:
			direction = Util.nearest_direction(input_vector)
		velocity = input_vector * speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()

# ── helpers ───────────────────────────────────────────────────────────────────
func _set_env(t: float) -> void:
	var env: Environment = %Environment.environment
	env.glow_bloom       = lerpf(FOCUS_BLOOM_MIN, FOCUS_BLOOM_MAX, t)
	env.glow_intensity   = lerpf(FOCUS_GLOW_MIN,  FOCUS_GLOW_MAX,  t)

func mine_around(world_pos: Vector2, radius: int = 1) -> void:
	var center: Vector2i = %TilemapManager.world_to_map(world_pos)
	for x: int in range(-radius, radius + 1):
		for y: int in range(-radius, radius + 1):
			%TilemapManager.damage_tile(center + Vector2i(x, y), 1)

func Log(msg: Variant) -> void:
	print("[player.gd] " + str(msg))

func _debug(msg: String) -> void:
	var game: Node = get_parent()
	if game and game.has_method("push_debug"):
		game.push_debug(msg)
