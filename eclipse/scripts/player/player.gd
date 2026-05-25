extends CharacterBody2D

# ================================================================== exports ==

@export_group("Procedural Animation")
@export var head_offset: Vector2 = Vector2(1, -28)
@export var body_offset: Vector2 = Vector2(1, -15)
@export var bob_amount:  float   = 2.5

@export_group("Orb Orbit")
@export var orb_orbit_center: Vector2 = Vector2(1, -15)
@export var orb_orbit_radius: float   = 24.0
@export var orb_orbit_speed:  float   = 1.25
@export var orb_reform_flash: float   = 0.2

@export_group("Focus Animation")
@export var focus_orbit_speed: float = 8.0

@export_group("Starting Orbs")
const starting_orb:   Orb = preload("res://data/orbs/orb_focus_mine.tres")
const starting_orb_2: Orb = preload("res://data/orbs/orb_gold_bomb.tres")
const starting_orb_3: Orb = preload("res://data/orbs/orb_lightning_chain.tres")
const starting_orb_4: Orb = preload("res://data/orbs/orb_conductor_post.tres")

var max_orb_inputs: int = 5


# ================================================================ constants ==

const FOCUS_BLOOM_MIN:      float = 0.0
const FOCUS_BLOOM_MAX:      float = 0.75
const FOCUS_GLOW_MIN:       float = 0.3
const FOCUS_GLOW_MAX:       float = 1.25
const FOCUS_DECAY:          float = 4.0
const CHANNEL_TIME:         float = 5.0
const CHANNEL_LIGHT_COST:   float = 0.80
const CHANNEL_POWER_BONUS:  float = 0.5

const ABILITY_STAGGER_SEC:  float = 0.05

const MINE_PRESS_DELAY:     float = 0.0   # seconds of pushing before mining begins
const MINE_TICK_INTERVAL:   float = 0.22   # seconds between damage ticks while held


# ================================================================= textures ==

var head_up:    Texture2D = preload("res://art/player/head_up.png")
var head_right: Texture2D = preload("res://art/player/head_right.png")
var head_down:  Texture2D = preload("res://art/player/head_down.png")
var head_left:  Texture2D = preload("res://art/player/head_left.png")
var body_up:    Texture2D = preload("res://art/player/body_up.png")
var body_right: Texture2D = preload("res://art/player/body_right.png")
var body_down:  Texture2D = preload("res://art/player/body_down.png")
var body_left:  Texture2D = preload("res://art/player/body_left.png")


# ===================================================================== state ==

var time:             float = 0.0
var env_t:            float = 0.0
var movement_enabled: bool  = true

@onready var speed: float = 100.0 * get_parent().scale.x

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


# ==================================================================== light ==

@onready var light_bar = $"../HUD/health bar"

var light: float = 100.0:
	set(value):
		light = clampf(value, 0.0, 100.0)
		if light_bar:
			light_bar.set_light(light)

var guaranteed_crits: int = 0

func heal(amount: int) -> void:
	light += float(amount)
	DamageNumbers.spawn_heal(global_position + Vector2(0, -28), amount)


# ================================================================= orb orbit ==

class OrbVisual:
	var sprite:        Sprite2D
	var shattered:     bool  = false
	var cooldown_age:  float = 0.0
	var cooldown:      float = 0.0
	var reform_flash:  float = 0.0
	var current_angle: float = 0.0
	var glow:          float = 0.0
	var glow_target:   float = 0.0
	var angle_offset:  float = 0.0
	var reforming:     bool  = false

var orb_visuals:      Array[OrbVisual] = []
var _orb_visual_map: Dictionary = {}   # Orb → OrbVisual
var orbit_time:       float            = 0.0
var orbit_speed_mult: float            = 1.0


# =============================================================== channeling ==

var channeling_orb_index: int   = -1
var channel_charge:       float = 0.0


# ============================================================ pending activations ==

class PendingActivation:
	var orb_index:     int
	var abilities:     Array[AbilityData]
	var stagger_timer: float = 0.0
	var any_activated: bool  = false

var _pending: Array[PendingActivation] = []


# ================================================================== mining ==

var _mine_press_timer: float    = 0.0
var _mine_tick_timer:  float    = 0.0
var _mine_target:      Vector2i = Vector2i(-1, -1)


# ================================================================== forging ==

var _nearby_forge: Forge = null


# ==================================================================== ready ==

func _ready() -> void:
	add_to_group("player")
	$Inventory.orb_added.connect(_on_orb_added)
	$Inventory.orb_removed.connect(_on_orb_removed)
	$Inventory.relic_added.connect(_on_relic_added)
	$Inventory.add_orb(starting_orb_2.clone())
	$Inventory.add_orb(starting_orb_3.clone())
	$Inventory.add_orb(starting_orb_4.clone())


# ================================================================== process ==

func _process(delta: float) -> void:
	time            += delta
	z_index          = %TilemapManager.get_z_for(global_position)
	movement_enabled = true

	$head.offset = head_offset + Vector2(0, round(bob_amount * sin(time * 2.0)))
	$body.offset = body_offset + Vector2(0, round(bob_amount * sin(time * 2.0 + 0.5)))

	_tick_channel(delta)
	_update_orb_visuals(delta)
	_tick_abilities(delta)
	_tick_relics(delta)
	_tick_env(delta)
	_tick_mining(delta)
	_tick_dev_input()


func _physics_process(delta: float) -> void:
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

	var new_target := Vector2i(-1, -1)
	var tilemap: Node = %TilemapManager
	if input_vector != Vector2.ZERO:
		for i in get_slide_collision_count():
			var col: KinematicCollision2D = get_slide_collision(i)
			# only mine if the player is actively pushing into this surface
			var pushing: bool = input_vector.dot(-col.get_normal()) > 0.5
			if not pushing:
				continue
			var hit_world: Vector2 = col.get_position() - col.get_normal() * (tilemap.TILE_SIZE.x * 0.5)
			var candidate: Vector2i = tilemap.world_to_map(hit_world)
			if tilemap.tile_exists(candidate):
				new_target = candidate
				break

	if new_target != _mine_target:
		_mine_target      = new_target
		_mine_press_timer = MINE_PRESS_DELAY
		_mine_tick_timer  = 0.0


# ================================================================ abilities ==

func _tick_abilities(delta: float) -> void:
	if channeling_orb_index != -1:
		return

	var orbs:      Array[Orb] = $Inventory.orbs
	var max_orb_t: float      = 0.0

	_queue_new_orb_presses(orbs)
	_tick_passive_and_hold_abilities(orbs, delta, max_orb_t)
	_advance_pending_activations(delta)
	_update_body_glow(max_orb_t)


func _queue_new_orb_presses(orbs: Array[Orb]) -> void:
	for i in range(orbs.size()):
		var orb: Orb = orbs[i]
		if not _orb_is_usable(i):
			_log_blocked_orb(i, orb)
			continue
		if not Input.is_action_just_pressed(orb.input_action):
			continue
		if _orb_already_pending(i):
			continue

		var pa          := PendingActivation.new()
		pa.orb_index     = i
		pa.stagger_timer = 0.0
		pa.any_activated = false
		for ability: AbilityData in orb.abilities:
			if ability.trigger_type == AbilityData.TriggerType.ACTIVE and not ability.requires_hold:
				pa.abilities.append(ability)
		_pending.append(pa)


func _orb_already_pending(orb_index: int) -> bool:
	for p: PendingActivation in _pending:
		if p.orb_index == orb_index:
			return true
	return false


func _tick_passive_and_hold_abilities(orbs: Array[Orb], delta: float, max_orb_t: float) -> void:
	for i in range(orbs.size()):
		if not _orb_is_usable(i):
			continue
		var orb: Orb = orbs[i]
		for ability: AbilityData in orb.abilities:
			if ability.trigger_type == AbilityData.TriggerType.PASSIVE:
				_activate_free(ability, _make_context(delta, false, i))
			elif ability.trigger_type == AbilityData.TriggerType.ACTIVE and ability.requires_hold:
				_tick_hold_ability(ability, delta, i)
		max_orb_t = maxf(max_orb_t, orb_visuals[i].glow)


func _advance_pending_activations(delta: float) -> void:
	var finished: Array[PendingActivation] = []

	for pa: PendingActivation in _pending:
		if pa.abilities.is_empty():
			finished.append(pa)
			continue

		pa.stagger_timer -= delta
		if pa.stagger_timer > 0.0:
			continue

		var ability: AbilityData = pa.abilities[0]
		var ctx                 := _make_context(delta, true, pa.orb_index)
		if _activate_free(ability, ctx):
			if not pa.any_activated:
				light -= _orb_cost(pa.orb_index)
			pa.any_activated = true
		_advance_ability_queue(pa)

	for pa: PendingActivation in finished:
		if pa.any_activated:
			shatter_orb(pa.orb_index)
			_trigger_connections(pa.orb_index, delta)
		_pending.erase(pa)


func _tick_hold_ability(ability: AbilityData, delta: float, orb_index: int) -> void:
	var orb: Orb = $Inventory.orbs[orb_index]
	if Input.is_action_pressed(orb.input_action):
		var ctx := _make_context(delta, true, orb_index)
		if _activate_free(ability, ctx):
			orb_visuals[orb_index].glow_target = 1.0
			shatter_orb(orb_index)
			_trigger_connections(orb_index, delta)
	elif Input.is_action_just_released(orb.input_action):
		_activate_free(ability, _make_context(delta, false, orb_index))
		orb_visuals[orb_index].glow_target = 0.0


func _advance_ability_queue(pa: PendingActivation) -> void:
	pa.abilities.pop_front()
	pa.stagger_timer = ABILITY_STAGGER_SEC


# ── context / cost helpers ─────────────────────────────────────────────────

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
		"targets":       [],
	}


func _activate_free(ability: AbilityData, ctx: Dictionary) -> bool:
	ability.activate(ctx)
	if ctx["lock_movement"]:
		movement_enabled = false
	return ctx["activated"]


func _orb_cost(orb_index: int) -> float:
	return _compute_orb_light_cost($Inventory.orbs[orb_index])


func _can_afford_orb(orb_index: int) -> bool:
	return light >= _orb_cost(orb_index)


func _orb_is_usable(i: int) -> bool:
	var orb: Orb = $Inventory.orbs[i]
	return orb.node_index != -1 and not orb_visuals[i].shattered and orb.input_action != "" and _can_afford_orb(i)


func _log_blocked_orb(i: int, orb: Orb) -> void:
	if orb.input_action == "" or not Input.is_action_just_pressed(orb.input_action):
		return
	if not _can_afford_orb(i):
		print("[orb %d] blocked: can't afford (cost %.1f, have %.1f)" % [
			i, _orb_cost(i), light])
	if orb.node_index == -1:
		print("[orb %d] blocked: not placed in graph" % i)
	elif orb_visuals[i].shattered:
		print("[orb %d] blocked: shattered (%.2fs remaining)" % [i,
			orb_visuals[i].cooldown - orb_visuals[i].cooldown_age])


func _update_body_glow(t: float) -> void:
	var glow: Color = Color(lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t))
	%body.self_modulate = glow if t > 0.0 else Color.WHITE
	%head.self_modulate = glow if t > 0.0 else Color.WHITE


# ================================================================ channeling ==

func _tick_channel(delta: float) -> void:
	var channel_held: bool = Input.is_action_pressed("channel_light")

	if channeling_orb_index != -1:
		if not channel_held:
			_cancel_channel()
			return
		movement_enabled  = false
		channel_charge   += delta
		var t: float       = minf(channel_charge / CHANNEL_TIME, 1.0)
		env_t              = t
		_set_env(t)
		orb_visuals[channeling_orb_index].glow = t
		orbit_speed_mult   = lerpf(1.0, focus_orbit_speed, t)
		ParticleManager.spawn_focus_particles(global_position, t)
		if channel_charge >= CHANNEL_TIME:
			_complete_channel()
		return

	if not channel_held:
		return

	ParticleManager.spawn_focus_particles(global_position, 0.02)
	for i in range($Inventory.orbs.size()):
		var orb: Orb = $Inventory.orbs[i]
		if orb.input_action == "" or orb.node_index == -1 or orb_visuals[i].shattered:
			continue
		if Input.is_action_just_pressed(orb.input_action):
			channeling_orb_index = i
			channel_charge       = 0.0
			break


func _cancel_channel() -> void:
	if channeling_orb_index < orb_visuals.size():
		orb_visuals[channeling_orb_index].glow = 0.0
	channeling_orb_index = -1
	channel_charge       = 0.0
	env_t                = 0.0
	orbit_speed_mult     = 1.0
	_set_env(0.0)


func _complete_channel() -> void:
	var orb: Orb = $Inventory.orbs[channeling_orb_index]
	light        = maxf(5.0, light - (light - 5.0) * CHANNEL_LIGHT_COST)
	for ability: AbilityData in orb.abilities:
		if ability != null and ability.stats != null:
			ability.stats.power *= (1.0 + CHANNEL_POWER_BONUS)
	if channeling_orb_index < orb_visuals.size():
		orb_visuals[channeling_orb_index].reform_flash = orb_reform_flash * 3.0
		orb_visuals[channeling_orb_index].glow         = 0.0
	channeling_orb_index = -1
	channel_charge       = 0.0
	env_t                = 0.0
	orbit_speed_mult     = 1.0
	_set_env(0.0)


# ================================================================ orb visuals ==

func _update_orb_visuals(delta: float) -> void:
	if orb_visuals.is_empty():
		return

	orbit_time += delta * orb_orbit_speed * orbit_speed_mult

	for i in range(orb_visuals.size()):
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
			if ability is AbilityFocusMine:
				(ability as AbilityFocusMine).reset_exploded()

	for i in range(orb_visuals.size()):
		var ov:  OrbVisual = orb_visuals[i]
		var orb: Orb       = $Inventory.orbs[i]

		ov.glow = lerpf(ov.glow, ov.glow_target, minf(12.0 * delta, 1.0))
		if absf(ov.glow - ov.glow_target) < 0.01:
			ov.glow = ov.glow_target

		if orb.node_index == -1 or ov.shattered:
			ov.sprite.visible = false
			continue

		ov.current_angle   = orbit_time + ov.angle_offset
		ov.sprite.position = _angle_to_orbit_pos(ov.current_angle)
		ov.sprite.scale    = Vector2.ONE

		if ov.reforming:
			ov.reforming = false
			continue

		if not ov.sprite.visible:
			ov.sprite.reset_physics_interpolation()
			ov.sprite.visible = true

		ov.sprite.self_modulate = Color.WHITE * _orb_brightness(ov, delta)


func _orb_brightness(ov: OrbVisual, delta: float) -> float:
	if ov.reform_flash > 0.0:
		ov.reform_flash -= delta
		return lerpf(1.0, 4.0, ov.reform_flash / orb_reform_flash)
	if ov.glow > 0.0:
		return lerpf(1.0, 3.0, ov.glow)
	return 1.0


func _angle_to_orbit_pos(angle: float) -> Vector2:
	return Vector2(cos(angle), sin(angle)) * orb_orbit_radius + orb_orbit_center


func _recalculate_orb_offsets() -> void:
	var active: Array[int] = []
	for i in range($Inventory.orbs.size()):
		if $Inventory.orbs[i].node_index != -1:
			active.append(i)
	for slot in range(active.size()):
		orb_visuals[active[slot]].angle_offset = (float(slot) / float(active.size())) * TAU


# ============================================================= orb management ==

func _on_orb_added(orb: Orb) -> void:
	var ov          := OrbVisual.new()
	ov.sprite        = Sprite2D.new()
	ov.sprite.texture              = orb.sprite_texture
	ov.sprite.centered             = true
	ov.sprite.visible              = false
	ov.sprite.z_as_relative        = false
	ov.sprite.z_index              = 4096
	add_child(ov.sprite)
	orb_visuals.append(ov)
	_orb_visual_map[orb] = ov
	_auto_assign_slot(orb)

func _on_orb_removed(orb: Orb) -> void:
	if not _orb_visual_map.has(orb):
		return
	var ov: OrbVisual = _orb_visual_map[orb]
	ov.sprite.queue_free()
	orb_visuals.erase(ov)
	_orb_visual_map.erase(orb)


func _on_relic_added(relic: RelicData, _qty: int) -> void:
	relic.on_equip(self)


func _tick_relics(delta: float) -> void:
	for relic: RelicData in $Inventory.relics:
		relic.tick(delta, self)


func _auto_assign_slot(orb: Orb) -> void:
	var taken: Dictionary = {}
	for o: Orb in $Inventory.orbs:
		if o != orb and o.input_action != "":
			taken[o.input_action] = true
	for n in range(1, max_orb_inputs + 1):
		var action: String = "orb_%d" % n
		if not taken.has(action):
			orb.input_action = action
			return
	orb.input_action = ""


func shatter_orb(orb_index: int) -> void:
	if orb_index >= orb_visuals.size():
		return
	var ov:  OrbVisual = orb_visuals[orb_index]
	var orb: Orb       = $Inventory.orbs[orb_index]
	if ov.shattered:
		return
	ov.shattered      = true
	ov.glow           = 0.0
	ov.cooldown_age   = 0.0
	ov.cooldown       = _compute_orb_cooldown(orb)
	ov.sprite.visible = false
	ov.current_angle  = orbit_time + (float(orb_index) / float(orb_visuals.size())) * TAU
	ParticleManager.spawn_focus_spark(global_position + ov.sprite.position)


func _compute_orb_light_cost(orb: Orb) -> float:
	if orb.light_cost != 0.0:
		return orb.light_cost
	var total: float = 0.0
	var count: int   = 0
	for ability: AbilityData in orb.abilities:
		if ability.stats != null and "light_cost" in ability.stats:
			total += ability.stats.light_cost
			count += 1
	orb.light_cost = total / count if count > 0 else 0.0
	return orb.light_cost


func _compute_orb_cooldown(orb: Orb) -> float:
	if orb.cooldown != 0.0:
		return orb.cooldown
	var total: float = 0.0
	var count: int   = 0
	for ability: AbilityData in orb.abilities:
		if ability.stats != null:
			total += ability.stats.cooldown
			count += 1
	return total / count if count > 0 else 1.0


func store_light_in_orb(orb_index: int, amount: float) -> void:
	if orb_index >= $Inventory.orbs.size():
		return
	$Inventory.orbs[orb_index].store_light(amount)
	ParticleManager.spawn_focus_particles(global_position, 1.0)


# ================================================================== mining ==

func _tick_mining(delta: float) -> void:
	var tilemap: Node = %TilemapManager

	if _mine_target == Vector2i(-1, -1):
		_mine_press_timer = 0.0
		_mine_tick_timer  = 0.0
		return

	if not tilemap.tile_exists(_mine_target):
		_mine_press_timer = 0.0
		_mine_tick_timer  = 0.0
		_mine_target      = Vector2i(-1, -1)
		return

	_mine_press_timer += delta
	if _mine_press_timer < MINE_PRESS_DELAY:
		return

	if _mine_tick_timer <= 0.0:
		# ── squish animation ──────────────────────────────────────────
		# squish_tile handles the primary tile AND sends a smaller delayed
		# bounce to the 4 NESW neighbours, so neighbour damage_tile calls
		# below suppress their own bounce.
		tilemap.squish_tile(_mine_target)

		# ── particles ────────────────────────────────────────────────
		var world_pos: Vector2   = tilemap.map_to_world(_mine_target)
		var base_type: Util.tile = tilemap.tile_types.get(_mine_target, Util.tile.STONE)
		var dig_dir:   Vector2   = Vector2(direction)
		ParticleManager.spawn_mine_dust(world_pos, base_type)
		ParticleManager.spawn_mine_chunk_directional(
			world_pos,
			ParticleManager._tile_dust_color(base_type),
			dig_dir * 40.0
		)

		# ── damage ───────────────────────────────────────────────────
		var tile_died: bool = tilemap.damage_tile(_mine_target, 3, false)
		for dx: int in range(-1, 2):
			for dy: int in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				tilemap.damage_tile(_mine_target + Vector2i(dx, dy), 1, false)

		_mine_tick_timer = MINE_TICK_INTERVAL
	else:
		_mine_tick_timer -= delta


# ================================================================== forging ==

func _on_forge_in_range(forge: Forge) -> void:
	_nearby_forge = forge


func _on_forge_out_of_range(forge: Forge) -> void:
	if _nearby_forge == forge:
		_nearby_forge = null


func _try_open_forge() -> void:
	if _nearby_forge == null:
		Log("Error! _nearby_forge = null, while trying to forge")
		return
	if _nearby_forge.state != Forge.State.IDLE:
		Log("Error! _nearby_forge is already forging!")
		return
	_nearby_forge.interact_request()
	%ForgeUI.open(self, _nearby_forge)
	Log("ForgeUI opened!")


# =============================================================== environment ==

func _tick_env(delta: float) -> void:
	if channeling_orb_index == -1 and env_t > 0.0:
		env_t = maxf(0.0, env_t - delta * FOCUS_DECAY)
		_set_env(env_t)


func _set_env(t: float) -> void:
	var env: Environment = %Environment.environment
	env.glow_bloom       = lerpf(FOCUS_BLOOM_MIN, FOCUS_BLOOM_MAX, t)
	env.glow_intensity   = lerpf(FOCUS_GLOW_MIN,  FOCUS_GLOW_MAX,  t)


# ================================================================= dev tools ==

func _tick_dev_input() -> void:
	if Input.is_action_just_pressed("dev_mode"):
		if $CollisionShape2D.disabled:
			speed /= 10.0
			$CollisionShape2D.disabled = false
			%CanvasModulate.color      = Color("101010")
			heal(100)
		else:
			speed *= 10.0
			$CollisionShape2D.disabled = true
			%CanvasModulate.color      = Color.WHITE
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
	for ov: OrbVisual in orb_visuals:
		ov.shattered    = false
		ov.cooldown_age = 0.0
		ov.cooldown     = 0.0
		ov.reform_flash = orb_reform_flash
		ov.reforming    = true
		ov.glow_target  = 0.0


# =================================================================== helpers ==

func _trigger_connections(orb_index: int, delta: float) -> void:
	var node_index: int = $Inventory.orbs[orb_index].node_index
	if node_index == -1:
		return
	%GraphManager.on_orb_fired(node_index, {}, $Inventory.orbs[orb_index])

func Log(msg: Variant) -> void:
	print("[player.gd] " + str(msg))
