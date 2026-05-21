extends CharacterBody2D

var movement_enabled: bool = true
@onready var speed: float  = 100.0 * get_parent().scale.x

@export_group("Procedural Animation")
@export var head_offset: Vector2 = Vector2(1, -28)
@export var body_offset: Vector2 = Vector2(1, -15)
@export var bob_amount:  float   = 2.5

@export_group("Orb Orbit")
@export var orb_orbit_center: Vector2 = Vector2(1, -15)
@export var orb_orbit_radius: float   = 24.0
@export var orb_orbit_speed:  float   = 1.25
@export var orb_bob_amount:   float   = 1.5
@export var orb_reform_flash: float   = 0.2

@export_group("Focus Animation")
@export var focus_orbit_speed: float = 8.0

@export_group("Starting Orbs/Abilities")
@export var basic_ability: AbilityData = preload("res://data/abilities/ability_basic_attack.tres")
const starting_orb:   Orb = preload("res://data/orbs/orb_focus_mine.tres")
const starting_orb_2: Orb = preload("res://data/orbs/orb_gold_bomb.tres")
const starting_orb_3: Orb = preload("res://data/orbs/orb_lightning_chain.tres")
const starting_orb_4: Orb = preload("res://data/orbs/orb_conductor_post.tres")

# -------------------------------------------------------------------- crit ---
var guaranteed_crits: int = 0

# ------------------------------------------------------ light (health) bar ---
@onready var light_bar = $"../HUD/health bar"
var light: float = 100.0:
	set(value):
		light = clampf(value, 0.0, 100.0)
		if light_bar:
			light_bar.set_light(light)

# ----------------------------------------------------------------- forging ---
var _nearby_forge: Forge = null

# ---------------------------------------------------------------- textures ---
var head_up:    Texture2D = preload("res://art/player/head_up.png")
var head_right: Texture2D = preload("res://art/player/head_right.png")
var head_down:  Texture2D = preload("res://art/player/head_down.png")
var head_left:  Texture2D = preload("res://art/player/head_left.png")
var body_up:    Texture2D = preload("res://art/player/body_up.png")
var body_right: Texture2D = preload("res://art/player/body_right.png")
var body_down:  Texture2D = preload("res://art/player/body_down.png")
var body_left:  Texture2D = preload("res://art/player/body_left.png")

# --------------------------------------------------------------- constants ---
const FOCUS_BLOOM_MIN:     float = 0.0
const FOCUS_BLOOM_MAX:     float = 0.75
const FOCUS_GLOW_MIN:      float = 0.3
const FOCUS_GLOW_MAX:      float = 1.25
const FOCUS_DECAY:         float = 4.0
const CHANNEL_TIME:        float = 5.0
const CHANNEL_LIGHT_COST:  float = 80.0
const CHANNEL_POWER_BONUS: float = 0.15

# ------------------------------------------------------------------- state ---
var time:             float = 0.0
var env_t:            float = 0.0
var channeling_orb_index: int   = -1
var channel_charge:   float = 0.0

var direction: Vector2i = Vector2i.DOWN:
	set(value):
		if direction == value:
			return
		direction = value
		match value:
			Vector2i.UP:    $head.texture = head_up;    $body.texture = body_up
			Vector2i.RIGHT: $head.texture = head_right; $body.texture = body_right
			Vector2i.DOWN:  $head.texture = head_down;  $body.texture = body_down
			Vector2i.LEFT:  $head.texture = head_left;  $body.texture = body_left
	get():
		return direction

# -------------------------------------------------------------- orb visuals ---
class OrbVisual:
	var sprite:        Sprite2D
	var shattered:     bool  = false
	var cooldown_age:  float = 0.0
	var cooldown:      float = 0.0
	var reform_flash:  float = 0.0
	var current_angle: float = 0.0
	var glow:          float = 0.0
	var glow_target: float = 0.0
	var angle_offset:  float = 0.0
	var reforming:     bool  = false

var orb_visuals:      Array[OrbVisual] = []
var orbit_time:       float            = 0.0
var orbit_speed_mult: float            = 1.0
var display_count:    float            = 0.0

# ------------------------------------------------------------------- ready ---
func _ready() -> void:
	$Inventory.orb_added.connect(_on_orb_added)
	$Inventory.orb_removed.connect(_on_orb_removed)
	$Inventory.add_orb(starting_orb.clone())
	$Inventory.add_orb(starting_orb_2.clone())
	$Inventory.add_orb(starting_orb_3.clone())
	$Inventory.add_orb(starting_orb_4.clone())

# --------------------------------------------------------- orb management ---
func _on_orb_added(orb: Orb) -> void:
	var ov              := OrbVisual.new()
	ov.sprite            = Sprite2D.new()
	ov.sprite.texture    = orb.sprite_texture
	ov.sprite.centered   = true
	ov.sprite.visible    = false
	ov.sprite.z_as_relative = false
	ov.sprite.z_index       = 4096
	add_child(ov.sprite)
	orb_visuals.append(ov)
	_auto_assign_slot(orb)

func _auto_assign_slot(orb: Orb) -> void:
	var taken: Dictionary = {}
	for o: Orb in $Inventory.orbs:
		if o != orb and o.input_action != "":
			taken[o.input_action] = true
	for n in range(1, 8):
		var action: String = "orb_%d" % n
		if not taken.has(action):
			orb.input_action = action
			return
	orb.input_action = ""

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
	ov.shattered    = true
	ov.glow         = 0.0
	ov.cooldown_age = 0.0
	if orb.cooldown != 0.0:
		ov.cooldown = orb.cooldown
	else:
		var total_cooldown: float = 0.0
		var ability_count:  int   = 0
		for ability: AbilityData in orb.abilities:
			if ability.stats != null:
				total_cooldown += ability.stats.cooldown
				ability_count  += 1
		ov.cooldown = total_cooldown / ability_count if ability_count > 0 else 1.0
	ov.sprite.visible = false
	var phase: float  = (float(orb_index) / float(orb_visuals.size())) * TAU
	ov.current_angle  = orbit_time + phase
	ParticleManager.spawn_focus_spark(global_position + ov.sprite.position)

func store_light_in_orb(orb_index: int, amount: float) -> void:
	if orb_index >= $Inventory.orbs.size():
		return
	$Inventory.orbs[orb_index].store_light(amount)
	ParticleManager.spawn_focus_particles(global_position, 1.0)

# --------------------------------------------------------------- context ---
func _make_context(delta: float, pressed: bool, orb_index: int) -> Dictionary:
	return {
		"player":        self,
		"tilemap":       %TilemapManager,
		"delta":         delta,
		"pressed":       pressed,
		"lock_movement": false,
		"orb_t":         0.0,
		"activated":     false,
		"orb_shattered": orb_visuals[orb_index].shattered,
		"orb_index":     orb_index,
		"potency":       $Inventory.orbs[orb_index].orb_potency,
	}

# _read_context is now unused and can be deleted

func _read_context(context: Dictionary, orb_index: int, max_t: float) -> float:
	if context["lock_movement"]:
		movement_enabled = false
	if orb_index < orb_visuals.size():
		orb_visuals[orb_index].glow = context["orb_t"]
	return maxf(max_t, context["orb_t"])

# ---------------------------------------------------------------- process ---
func _process(delta: float) -> void:
	time             += delta
	z_index           = %TilemapManager.get_z_for(global_position)
	movement_enabled  = true

	$head.offset = head_offset + Vector2(0, round(bob_amount * sin(time * 2.0)))
	$body.offset = body_offset + Vector2(0, round(bob_amount * sin(time * 2.0 + 0.5)))

	_tick_channel(delta)
	_update_orb_visuals(delta)
	_tick_abilities(delta)
	_tick_env(delta)
	_tick_dev_input()

func _tick_channel(delta: float) -> void:
	var channel_held: bool = Input.is_action_pressed("channel_light")
	if channeling_orb_index != -1:
		if not channel_held:
			_cancel_channel()
			return
		movement_enabled  = false
		channel_charge   += delta
		var t: float      = minf(channel_charge / CHANNEL_TIME, 1.0)
		env_t             = t
		_set_env(t)
		orb_visuals[channeling_orb_index].glow = t
		orbit_speed_mult  = lerpf(1.0, focus_orbit_speed, t)
		ParticleManager.spawn_focus_particles(global_position, t)
		if channel_charge >= CHANNEL_TIME:
			_complete_channel()
	elif channel_held:
		ParticleManager.spawn_focus_particles(global_position, 0.02)
		for i in range($Inventory.orbs.size()):
			var orb: Orb = $Inventory.orbs[i]
			if orb.input_action == "" or orb.node_index == -1 or orb_visuals[i].shattered:
				continue
			if Input.is_action_just_pressed(orb.input_action):
				channeling_orb_index = i
				channel_charge       = 0.0
				break

func _tick_abilities(delta: float) -> void:
	if channeling_orb_index != -1:
		return
		
	# basic ability — always available, not tied to any orb
	if Input.is_action_just_pressed("basic_ability"):
		var ctx := {
			"player":        self,
			"tilemap":       %TilemapManager,
			"delta":         delta,
		}
		basic_ability.activate(ctx)

	var max_orb_t: float = 0.0
	var orbs: Array[Orb] = $Inventory.orbs

	for i in range(orbs.size()):
		var orb: Orb = orbs[i]
		if orb.node_index == -1:
			continue
		if orb_visuals[i].shattered:
			continue
		if orb.input_action == "":
			continue

		var has_hold_ability:   bool  = false
		var hold_ability_count: int   = 0
		for ability: AbilityData in orb.abilities:
			if ability.trigger_type == AbilityData.TriggerType.ACTIVE and ability.requires_hold:
				has_hold_ability    = true
				hold_ability_count += 1

		var orb_activated:   bool  = false
		var nonhold_fired:   bool  = orb.nonhold_fired
		var holds_completed: int   = 0
		var hold_t_sum:      float = 0.0

		for ability: AbilityData in orb.abilities:
			var cost:       float = ability.stats.light_cost if "light_cost" in ability.stats else 0.0
			var can_afford: bool  = light >= cost

			match ability.trigger_type:
				AbilityData.TriggerType.PASSIVE:
					var ctx := _make_context(delta, false, i)
					ability.activate(ctx)
					if ctx["lock_movement"]:
						movement_enabled = false

				AbilityData.TriggerType.ACTIVE:
					if not ability.requires_hold:
						if Input.is_action_just_pressed(orb.input_action) and can_afford:
							var ctx := _make_context(delta, true, i)
							ability.activate(ctx)
							if ctx["lock_movement"]:
								movement_enabled = false
							if has_hold_ability:
								orb.nonhold_fired = true
								nonhold_fired     = true
							else:
								orb_activated = true

					else:  # requires_hold
						var just_started: bool = Input.is_action_just_pressed(orb.input_action)
						if nonhold_fired and just_started:
							pass
						elif Input.is_action_pressed(orb.input_action) and can_afford:
							var ctx := _make_context(delta, true, i)
							ability.activate(ctx)
							if ctx["lock_movement"]:
								movement_enabled = false
							if ctx["activated"]:
								holds_completed += 1
							hold_t_sum += ctx["orb_t"]
						elif Input.is_action_just_released(orb.input_action):
							var ctx := _make_context(delta, false, i)
							ability.activate(ctx)
							if ctx["lock_movement"]:
								movement_enabled = false

		# resolve glow and shatter
		if has_hold_ability:
			var released: bool = Input.is_action_just_released(orb.input_action)
			if released and nonhold_fired:
				orb_visuals[i].glow_target = 1.0
				orb.nonhold_fired          = false
				orb_activated              = true
			elif holds_completed >= hold_ability_count and hold_ability_count > 0:
				orb_visuals[i].glow_target = 1.0
				orb.nonhold_fired          = false
				orb_activated              = true
			elif Input.is_action_pressed(orb.input_action):
				orb_visuals[i].glow_target = hold_t_sum / float(hold_ability_count)
			elif released and not nonhold_fired:
				orb_visuals[i].glow_target = 0.0
		else:
			if orb_activated:
				orb_visuals[i].glow_target = 1.0

		max_orb_t = maxf(max_orb_t, orb_visuals[i].glow)

		if orb_activated:
			shatter_orb(i)
			_trigger_connections(i, delta)

	var body_glow := Color(lerpf(1.0, 2.0, max_orb_t), lerpf(1.0, 2.0, max_orb_t), lerpf(1.0, 2.0, max_orb_t))
	%body.self_modulate = body_glow if max_orb_t > 0.0 else Color.WHITE
	%head.self_modulate = body_glow if max_orb_t > 0.0 else Color.WHITE

func _tick_env(delta: float) -> void:
	if channeling_orb_index == -1 and env_t > 0.0:
		env_t = maxf(0.0, env_t - delta * FOCUS_DECAY)
		_set_env(env_t)

# ----------------------------------------------------------- dev functions ---
func _tick_dev_input() -> void:
	if Input.is_action_just_pressed("dev_mode"):
		if $CollisionShape2D.disabled:
			speed /= 10.0
			$CollisionShape2D.disabled = false
			%CanvasModulate.color = Color("101010")
			heal(100)
		else:
			speed *= 10.0
			$CollisionShape2D.disabled = true
			%CanvasModulate.color = Color.WHITE
			_dev_reset_cooldowns()
	if Input.is_action_just_pressed("dev_call_wave"):
		WaveManager.timer = 0.0
		WaveManager._launch_wave()
	if Input.is_action_just_pressed("interact") and _nearby_forge != null:
		_try_open_forge()
	if Input.is_action_just_pressed("zoom_in"):
		%Camera2D.zoom *= 2
	if Input.is_action_just_pressed("zoom_out"):
		%Camera2D.zoom /= 2

func _dev_reset_cooldowns() -> void:
	for orb: Orb in $Inventory.orbs:
		for ability: AbilityData in orb.abilities:
			ability.reset_cooldown()
	for ov: OrbVisual in orb_visuals:
		ov.shattered    = false
		ov.cooldown_age = 0.0
		ov.cooldown     = 0.0
		ov.reform_flash = orb_reform_flash
		ov.reforming    = true
		ov.glow_target  = 0.0

# ------------------------------------------------------ physics process ---
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

# ---------------------------------------------------------- orb visuals ---
func _update_orb_visuals(delta: float) -> void:
	var total: int = orb_visuals.size()
	if total == 0:
		display_count = 0.0
		return
	var max_glow: float = 0.0
	for ov: OrbVisual in orb_visuals:
		max_glow = maxf(max_glow, ov.glow)
	orbit_time += delta * orb_orbit_speed * orbit_speed_mult

	# pass 1 — active slot assignments
	var active_indices: Array[int] = []
	for i in range(total):
		if not orb_visuals[i].shattered and $Inventory.orbs[i].node_index != -1:
			active_indices.append(i)
	var active_count: int = active_indices.size()

	# lerp display_count toward real count
	if display_count == 0.0:
		display_count = float(active_count)
	else:
		display_count = lerpf(display_count, float(active_count), minf(10.0 * delta, 1.0))

	# pass 2 — resolve cooldowns
	for i in range(total):
		var ov: OrbVisual = orb_visuals[i]
		if not ov.shattered:
			continue
		ov.cooldown_age += delta
		if ov.cooldown_age < ov.cooldown:
			continue
		ov.shattered      = false
		ov.reforming      = true
		ov.reform_flash   = orb_reform_flash
		ov.cooldown_age   = 0.0
		ov.glow           = 0.0
		ov.glow_target    = 0.0
		ov.sprite.visible = false
		for ability: AbilityData in $Inventory.orbs[i].abilities:
			ability.reset_cooldown()
			if ability is AbilityFocusMine:
				(ability as AbilityFocusMine).reset_exploded()

	# pass 3 — position and visibility
	for i in range(total):
		var ov:  OrbVisual = orb_visuals[i]
		var orb: Orb       = $Inventory.orbs[i]

		ov.glow = lerpf(ov.glow, ov.glow_target, minf(12.0 * delta, 1.0))
		if absf(ov.glow - ov.glow_target) < 0.01:
			ov.glow = ov.glow_target

		if orb.node_index == -1 or ov.shattered:
			ov.sprite.visible = false
			continue
		var angle: float   = orbit_time + ov.angle_offset
		ov.current_angle   = angle
		ov.sprite.position = _angle_to_orbit_pos(ov.current_angle)
		ov.sprite.scale    = Vector2.ONE
		if ov.reforming:
			ov.reforming = false
			continue
		if not ov.sprite.visible:
			ov.sprite.reset_physics_interpolation()
			ov.sprite.visible = true
		var brightness: float = 1.0
		if ov.reform_flash > 0.0:
			ov.reform_flash -= delta
			brightness       = lerpf(1.0, 4.0, ov.reform_flash / orb_reform_flash)
		elif ov.glow > 0.0:
			brightness       = lerpf(1.0, 3.0, ov.glow)
		ov.sprite.self_modulate = Color(brightness, brightness, brightness)

func _angle_to_orbit_pos(angle: float) -> Vector2:
	return Vector2(cos(angle), sin(angle)) * orb_orbit_radius + orb_orbit_center

func _recalculate_orb_offsets() -> void:
	var active: Array[int] = []
	for i in range($Inventory.orbs.size()):
		if $Inventory.orbs[i].node_index != -1:
			active.append(i)
	var count: int = active.size()
	for slot in range(count):
		orb_visuals[active[slot]].angle_offset = (float(slot) / float(count)) * TAU

# --------------------------------------------------------- channeling ---
func _cancel_channel() -> void:
	if channeling_orb_index < orb_visuals.size():
		orb_visuals[channeling_orb_index].glow = 0.0
	channeling_orb_index = -1
	channel_charge       = 0.0
	env_t                = 0.0
	orbit_speed_mult     = 1.0
	_set_env(0.0)

func _complete_channel() -> void:
	var orb: Orb    = $Inventory.orbs[channeling_orb_index]
	var cost: float = (light - 5.0) * (CHANNEL_LIGHT_COST / 100.0)
	light           = maxf(5.0, light - cost)
	for ability: AbilityData in orb.abilities:
		if ability == null or ability.stats == null:
			continue
		ability.stats.power *= (1.0 + CHANNEL_POWER_BONUS)
	if channeling_orb_index < orb_visuals.size():
		orb_visuals[channeling_orb_index].reform_flash = orb_reform_flash * 3.0
		orb_visuals[channeling_orb_index].glow         = 0.0
	channeling_orb_index = -1
	channel_charge       = 0.0
	env_t                = 0.0
	orbit_speed_mult     = 1.0
	_set_env(0.0)

# ----------------------------------------------------- forge interaction ---
func _try_open_forge() -> void:
	if _nearby_forge == null:
		Log("Error! _nearby_forge = null, while trying to forge")
		return
	if _nearby_forge.state != Forge.State.IDLE:
		Log("Error! _nearby_forge is already forging!")
		return
	_nearby_forge._open(self)
	%ForgeUI.open(self, _nearby_forge)
	Log("ForgeUI opened!")

func _on_forge_in_range(forge: Forge) -> void:
	_nearby_forge = forge

func _on_forge_out_of_range(forge: Forge) -> void:
	if _nearby_forge == forge:
		_nearby_forge = null

# --------------------------------------------------------------- helpers ---
func _set_env(t: float) -> void:
	var env: Environment = %Environment.environment
	env.glow_bloom       = lerpf(FOCUS_BLOOM_MIN, FOCUS_BLOOM_MAX, t)
	env.glow_intensity   = lerpf(FOCUS_GLOW_MIN,  FOCUS_GLOW_MAX,  t)

func _trigger_connections(orb_index: int, delta: float) -> void:
	var node_index: int = $Inventory.orbs[orb_index].node_index
	if node_index == -1:
		return
	GraphManager.on_orb_fired(node_index, {}, $Inventory.orbs[orb_index])

func heal(amount: int) -> void:
	light += float(amount)
	DamageNumbers.spawn_heal(global_position + Vector2(0, -28), amount)

func Log(msg: Variant) -> void:
	print("[player.gd] " + str(msg))

func _debug(msg: String) -> void:
	var game: Node = get_parent()
	if game and game.has_method("push_debug"):
		game.push_debug(msg)
