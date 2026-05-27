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

@export_group("Starting Orbs")
const starting_orb:   Orb = preload("res://data/orbs/orb_focus_mine.tres")
const starting_orb_2: Orb = preload("res://data/orbs/orb_gold_bomb.tres")
const starting_orb_3: Orb = preload("res://data/orbs/orb_lightning_chain.tres")
const starting_orb_4: Orb = preload("res://data/orbs/orb_conductor_post.tres")

@export_group("Basic Attacks")
## Abilities in this array fire automatically whenever their cooldown expires.
## They cost no light and are independent of the orb system.
@export var basic_attacks: Array[AbilityBasicAttack] = []

@export_group("Health")
@export var max_health: int = 100
## Flat damage absorbed per hit before percentage reduction.
## Effective damage = max(1, raw - max(0, armor - attacker_pen)) * (1 - damage_reduction)
@export var armor:      int = 0


# ================================================================ constants ==

const FOCUS_BLOOM_MIN:      float = 0.0
const FOCUS_BLOOM_MAX:      float = 0.75
const FOCUS_GLOW_MIN:       float = 0.3
const FOCUS_GLOW_MAX:       float = 1.25
const FOCUS_DECAY:          float = 4.0

const MINE_PRESS_DELAY:     float = 0.05
const MINE_TICK_INTERVAL:   float = 0.33
const MINE_BOUNCE_AMOUNT:   float = 6.0
const MINE_BOUNCE_FALLOFF:  float = 0.85
const MINE_AOE_RADIUS:      int   = 1
var MINE_BOUNCE_DURATION: float:
	get: return MINE_TICK_INTERVAL * 0.75


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

var health: int:
	set(value):
		health = clampi(value, 0, max_health)
		var health_bar = $"../HUD/health bar"
		if health_bar:
			health_bar.set_health(float(health), float(max_health))
		if health <= 0:
			_on_died()

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

@onready var light_bar = $"../HUD/power bar"

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

const ORB_READY_DELAY: float = 0.25

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
	var ready_delay:   float = 0.0

var orb_visuals:     Array[OrbVisual] = []
var _orb_visual_map: Dictionary       = {}
var orbit_time:      float            = 0.0
var orbit_speed_mult: float           = 1.0


# ============================================================ pending activations ==

class PendingActivation:
	var orb_index:     int
	var abilities:     Array[AbilityData]
	var stagger_timer: float = 0.0
	var any_activated: bool  = false

var _pending: Array[PendingActivation] = []

class PendingMineDamage:
	var pos:    Vector2i
	var damage: int
	var timer:  float

var _pending_mine_damage: Array[PendingMineDamage] = []


# ================================================================== mining ==

var _mine_press_timer:    float    = 0.0
var _mine_target:         Vector2i = Vector2i(-1, -1)
var _mine_cooldown_timer: float    = 0.0
var _mining_enabled:      bool     = true


# ================================================================== forging ==

var _nearby_forge: Forge = null


# ==================================================================== ready ==

func _ready() -> void:
	health = max_health   # triggers the setter so the bar initialises correctly
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

	_update_orb_visuals(delta)
	_tick_abilities(delta)
	_tick_basic_attacks(delta)
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


# ================================================================== combat ==

## Called by enemies when they deal damage to the player.
##
## armor_penetration — flat armor the attacker ignores (from EnemyData).
## is_crit           — whether the hit was a crit (shown on damage number).
##
## Pipeline (mirrors enemy take_damage):
##   1. Subtract armor offset by penetration. Minimum 1 so armor can't negate.
##   2. Result shown as a damage number; health reduced.
func take_damage(amount: int, armor_penetration: int = 0, is_crit: bool = false) -> void:
	var after_armor: int = amount - maxi(0, armor - armor_penetration)
	after_armor = maxi(1, after_armor)
	DamageNumbers.spawn(global_position + Vector2(0, -28), after_armor, is_crit)
	health -= after_armor

func _on_died() -> void:
	Log("Player died.")
	# TODO: trigger death screen / respawn


# ============================================================ basic attacks ==

## Ticks every AbilityBasicAttack in basic_attacks[].
## Each ability manages its own cooldown and fires when ready — no light cost.
func _tick_basic_attacks(delta: float) -> void:
	if basic_attacks.is_empty():
		return
	var ctx: Dictionary = {
		"player": self,
		"delta":  delta,
	}
	for attack: AbilityBasicAttack in basic_attacks:
		attack.tick(ctx)


# ================================================================ abilities ==

func _tick_abilities(delta: float) -> void:
	var orbs: Array[Orb] = $Inventory.orbs

	if orbs.size() != orb_visuals.size():
		return

	for i in range(orbs.size()):
		# reset glow target each frame — abilities write upward from here
		orb_visuals[i].glow_target = 0.0

		var orb: Orb = orbs[i]
		if orb.node_index == -1:
			continue
		if orb_visuals[i].shattered:
			continue
		if orb_visuals[i].ready_delay > 0.0:
			continue
		if not _can_afford_orb(i):
			continue

		var ctx := _make_context(delta, i)

		for ability: AbilityData in orb.abilities:
			ability.tick(ctx)

		if ctx["activated"] and not orb_visuals[i].shattered:
			light -= _orb_cost(i)
			shatter_orb(i)
			_trigger_connections(i, delta)

		if ctx["lock_movement"]:
			movement_enabled = false

		orb_visuals[i].glow_target = ctx["orb_t"]

	_update_body_glow_from_visuals()


# ── context helpers ───────────────────────────────────────────────────────

func _make_context(delta: float, orb_index: int) -> Dictionary:
	return {
		"player":        self,
		"tilemap":       %TilemapManager,
		"delta":         delta,
		"lock_movement": false,
		"orb_t":         0.0,
		"activated":     false,
		"orb_shattered": orb_visuals[orb_index].shattered,
		"orb_index":     orb_index,
		"potency":       $Inventory.orbs[orb_index].orb_potency,
	}


func _orb_cost(orb_index: int) -> float:
	return _compute_orb_light_cost($Inventory.orbs[orb_index])


func _can_afford_orb(orb_index: int) -> bool:
	return light >= _orb_cost(orb_index)


func _update_body_glow_from_visuals() -> void:
	var max_t: float = 0.0
	for ov: OrbVisual in orb_visuals:
		max_t = maxf(max_t, ov.glow)
	_update_body_glow(max_t)


func _update_body_glow(t: float) -> void:
	var glow: Color = Color(lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t))
	%body.self_modulate = glow if t > 0.0 else Color.WHITE
	%head.self_modulate = glow if t > 0.0 else Color.WHITE


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
		ov.ready_delay = ORB_READY_DELAY if ov.ready_delay <= 0.0 else ov.ready_delay
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

		if ov.ready_delay > 0.0:
			ov.ready_delay = maxf(0.0, ov.ready_delay - delta)

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
	var ov               := OrbVisual.new()
	ov.sprite             = Sprite2D.new()
	ov.sprite.texture     = orb.sprite_texture
	ov.sprite.centered    = true
	ov.sprite.visible     = false
	ov.sprite.z_as_relative = false
	ov.sprite.z_index     = 4096
	add_child(ov.sprite)
	orb_visuals.append(ov)
	_orb_visual_map[orb] = ov


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

	if not _mining_enabled:
		_mine_cooldown_timer -= delta
		if _mine_cooldown_timer <= 0.0:
			_mine_cooldown_timer = 0.0
			_mining_enabled      = true
		else:
			var still_pending: Array[PendingMineDamage] = []
			for pd: PendingMineDamage in _pending_mine_damage:
				pd.timer -= delta
				if pd.timer <= 0.0:
					tilemap.damage_tile(pd.pos, pd.damage, false)
				else:
					still_pending.append(pd)
			_pending_mine_damage = still_pending
			return

	var still_pending: Array[PendingMineDamage] = []
	for pd: PendingMineDamage in _pending_mine_damage:
		pd.timer -= delta
		if pd.timer <= 0.0:
			tilemap.damage_tile(pd.pos, pd.damage, false)
		else:
			still_pending.append(pd)
	_pending_mine_damage = still_pending

	if _mine_target == Vector2i(-1, -1):
		_mine_press_timer = 0.0
		return

	if not tilemap.tile_exists(_mine_target):
		_mine_press_timer = 0.0
		_mine_target      = Vector2i(-1, -1)
		return

	_mine_press_timer += delta
	if _mine_press_timer < MINE_PRESS_DELAY:
		return

	var max_hp: int      = tilemap.get_tile_max_health(tilemap.tile_types.get(_mine_target, Util.tile.STONE))
	var cur_hp: int      = tilemap.tile_health.get(_mine_target, max_hp)
	var dmg_ratio: float = 1.0 - clampf(float(cur_hp - 6) / float(max_hp), 0.0, 1.0)
	var bounce_px: float = lerpf(MINE_BOUNCE_AMOUNT * 0.5, MINE_BOUNCE_AMOUNT, dmg_ratio)
	var dig_dir:   Vector2 = Vector2(direction)

	var world_pos: Vector2   = tilemap.map_to_world(_mine_target)
	var base_type: Util.tile = tilemap.tile_types.get(_mine_target, Util.tile.STONE)
	ParticleManager.spawn_mining_chunks(world_pos, base_type, dig_dir, 1.0)

	var bounce_dur: float = MINE_BOUNCE_DURATION
	tilemap.bounce_tile(_mine_target, bounce_px, 0.0, bounce_dur)
	_schedule_mine_damage(_mine_target, 4, bounce_dur)

	for dx: int in range(-MINE_AOE_RADIUS, MINE_AOE_RADIUS + 1):
		for dy: int in range(-MINE_AOE_RADIUS, MINE_AOE_RADIUS + 1):
			if dx == 0 and dy == 0:
				continue
			var nb: Vector2i = _mine_target + Vector2i(dx, dy)
			if Vector2i(dx, dy).length() > MINE_AOE_RADIUS:
				continue
			var dist:  int   = absi(dx) + absi(dy)
			var delay: float = float(dist) * 0.06
			tilemap.bounce_tile(nb, bounce_px * MINE_BOUNCE_FALLOFF, delay, bounce_dur)
			_schedule_mine_damage(nb, 2, delay + bounce_dur)
			if tilemap.tile_exists(nb):
				var nb_world:     Vector2   = tilemap.map_to_world(nb)
				var nb_type:      Util.tile = tilemap.tile_types.get(nb, Util.tile.STONE)
				var nb_intensity: float     = 0.5 / float(dist)
				ParticleManager.spawn_mining_chunks(nb_world, nb_type, dig_dir, nb_intensity)

	%Camera2D.shake(0.2)

	_mine_cooldown_timer = MINE_TICK_INTERVAL
	_mining_enabled      = false


func _schedule_mine_damage(pos: Vector2i, damage: int, delay: float) -> void:
	var pd    := PendingMineDamage.new()
	pd.pos     = pos
	pd.damage  = damage
	pd.timer   = delay
	_pending_mine_damage.append(pd)


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
	if env_t > 0.0:
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
		WaveManager._spawn_enemy()
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
		ov.ready_delay  = 0.0
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
