# player.gd
extends CharacterBody2D

var movement_enabled: bool = true
@onready var speed: float = 100.0 * get_parent().scale.x

@export_group("Procedural Animation")
@export var head_offset:       Vector2 = Vector2(1, -28)
@export var body_offset:       Vector2 = Vector2(1, -15)
@export var hand_orbit_radius: float   = 18.0
@export var hand_orbit_speed:  float   = 1.25
@export var hand_bob_amount:   float   = 2.5

@export_group("Focus Animation")
@export var focus_hand_lerp:   float = 10.0
@export var focus_orbit_speed: float = 4.0

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
const FOCUS_CHARGE_TIME: float = 1.5
const FOCUS_BLOOM_MIN:   float = 0.0
const FOCUS_BLOOM_MAX:   float = 0.75
const FOCUS_GLOW_MIN:    float = 0.3
const FOCUS_GLOW_MAX:    float = 1.25
const FOCUS_DECAY:       float = 4.0

# ── state ─────────────────────────────────────────────────────────────────────
var hand_orbit_time: float = 0.0
var focus_charge:    float = 0.0
var focus_charging:  bool  = false
var focus_exploded:  bool  = false
var env_target:      float = 0.0
var env_t:           float = 0.0
var targeted_tiles:  Array[Vector2i] = []
var time:            float = 0.0

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
	add_to_group("player")

# ── process ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	time += delta
	z_index = %TilemapManager.get_z_for(global_position)

	# focus charging
	if Input.is_action_pressed("attack_interact"):
		if not focus_exploded:
			if not focus_charging:
				targeted_tiles = _get_focus_tiles(global_position)

			if targeted_tiles.size() != 0:
				movement_enabled = false
				focus_charging   = true
				focus_charge    += delta
				env_target       = focus_charge / FOCUS_CHARGE_TIME

				for tile: Vector2i in targeted_tiles:
					%TilemapManager.set_tile_color(
						tile,
						Color(1.0 + env_target, 1.0 + env_target, 1.0 + env_target)
					)

				if focus_charge >= FOCUS_CHARGE_TIME:
					ability_focus()
					targeted_tiles.clear()
					focus_charge     = 0.0
					focus_charging   = false
					focus_exploded   = true
					env_target       = 0.0
					movement_enabled = true
	else:
		_clear_targeted_tiles()
		focus_charge     = 0.0
		focus_charging   = false
		focus_exploded   = false
		env_target       = 0.0
		movement_enabled = true

	# smooth env lerp
	env_t = lerpf(env_t, env_target, FOCUS_DECAY * delta)
	_set_env(env_t)

	# body bob
	$head.offset = head_offset + Vector2(0, round(hand_bob_amount * sin(time * 2.0)))
	$body.offset = body_offset + Vector2(0, round(hand_bob_amount * sin(time * 2.0 + 0.5)))

	# hand orbit — speed scales with focus charge
	var orbit_speed_mult: float = lerpf(1.0, focus_orbit_speed, focus_charge / FOCUS_CHARGE_TIME) if focus_charging else 1.0
	hand_orbit_time += delta * hand_orbit_speed * orbit_speed_mult

	var right_orbit: Vector2 = Vector2(cos(hand_orbit_time),      sin(hand_orbit_time))      * hand_orbit_radius
	var left_orbit:  Vector2 = Vector2(cos(hand_orbit_time + PI), sin(hand_orbit_time + PI)) * hand_orbit_radius

	var right_target: Vector2 = right_orbit
	var left_target:  Vector2 = left_orbit

	# hand color during focus
	if focus_charging:
		var t: float = focus_charge / FOCUS_CHARGE_TIME
		ParticleManager.spawn_focus_particles(global_position, t)
		%hand_right.self_modulate = Color(lerpf(1.0, 5.0, t), lerpf(1.0, 5.0, t), lerpf(1.0, 5.0, t))
		%hand_left.self_modulate  = Color(lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t))
		%body.self_modulate       = Color(lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t))
		%head.self_modulate       = Color(lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t))
	else:
		%hand_right.self_modulate = Color.WHITE
		%hand_left.self_modulate  = Color.WHITE
		%body.self_modulate       = Color.WHITE
		%head.self_modulate       = Color.WHITE

	# apply bob
	right_target.y += round(hand_bob_amount * sin(time * 2.0 + 0.75))
	left_target.y  += round(hand_bob_amount * sin(time * 2.0 + 0.25))

	%hand_right.position = %hand_right.position.lerp(right_target, focus_hand_lerp * delta)
	%hand_left.position  = %hand_left.position.lerp(left_target,   focus_hand_lerp * delta)

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

func _get_focus_tiles(world_pos: Vector2, power: int = 3) -> Array[Vector2i]:
	var start: Vector2i = %TilemapManager.world_to_map(world_pos) + direction
	var limit: int      = power * 4 - 1

	if %TilemapManager.is_air(start):
		return []

	var visited: Dictionary     = { start: true }
	var queue:   Array[Vector2i] = [start]
	var result:  Array[Vector2i] = []

	while queue.size() > 0 and result.size() < limit:
		var current: Vector2i = queue.pop_front()
		result.append(current)

		for neighbor: Vector2i in [
			current + Vector2i( 0, -1),
			current + Vector2i( 0,  1),
			current + Vector2i(-1,  0),
			current + Vector2i( 1,  0),
		]:
			if not visited.has(neighbor) and %TilemapManager.tile_exists(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)

	return result

func _clear_targeted_tiles() -> void:
	for tile: Vector2i in targeted_tiles:
		%TilemapManager.set_tile_color(tile, Color.WHITE)
	targeted_tiles.clear()

func ability_focus(power: int = 3) -> void:
	for tile: Vector2i in targeted_tiles:
		%TilemapManager.damage_tile(tile, power)
		ParticleManager.spawn_focus_spark(%TilemapManager.map_to_world(tile))

	Log("Focus exploded! tiles hit: " + str(targeted_tiles.size()) + " facing: " + str(direction))

func mine_around(world_pos: Vector2, radius: int = 1) -> void:
	var center: Vector2i = %TilemapManager.world_to_map(world_pos)
	for x: int in range(-radius, radius + 1):
		for y: int in range(-radius, radius + 1):
			%TilemapManager.damage_tile(center + Vector2i(x, y), 1)

func Log(msg: Variant) -> void:
	print("[player.gd] " + str(msg))
