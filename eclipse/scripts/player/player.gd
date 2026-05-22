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


# ================================================================ constants ==

const FOCUS_BLOOM_MIN:     float = 0.0
const FOCUS_BLOOM_MAX:     float = 0.75
const FOCUS_GLOW_MIN:      float = 0.3
const FOCUS_GLOW_MAX:      float = 1.25
const FOCUS_DECAY:         float = 4.0
const CHANNEL_TIME:        float = 5.0
const CHANNEL_LIGHT_COST:  float = 0.80  # fraction of current light
const CHANNEL_POWER_BONUS: float = 0.5


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
var orbit_time:       float            = 0.0
var orbit_speed_mult: float            = 1.0


# =============================================================== channeling ==

var channeling_orb_index: int   = -1
var channel_charge:       float = 0.0


# ================================================================ targeting ==

var _targeting_orb_index: int                = -1
var _ability_queue:        Array[AbilityData] = []
var _selected_enemies:     Array[Node]        = []
var _hovered_enemy:        Node               = null
var _queue_hold_pending:   bool               = false
var _queue_any_activated:  bool               = false


# ================================================================== forging ==

var _nearby_forge: Forge = null


# ==================================================================== ready ==

func _ready() -> void:
	add_to_group("player")
	$Inventory.orb_added.connect(_on_orb_added)
	$Inventory.orb_removed.connect(_on_orb_removed)
	$Inventory.relic_added.connect(_on_relic_added)
	$Inventory.add_orb(starting_orb.clone())
	$Inventory.add_orb(starting_orb_2.clone())
	$Inventory.add_orb(starting_orb_3.clone())
	$Inventory.add_orb(starting_orb_4.clone())


# ================================================================== process ==

func _process(delta: float) -> void:
	time             += delta
	z_index           = %TilemapManager.get_z_for(global_position)
	movement_enabled  = true

	$head.offset = head_offset + Vector2(0, round(bob_amount * sin(time * 2.0)))
	$body.offset = body_offset + Vector2(0, round(bob_amount * sin(time * 2.0 + 0.5)))

	_tick_channel(delta)
	_update_orb_visuals(delta)
	_tick_abilities(delta)
	_tick_relics(delta)
	_tick_env(delta)
	_tick_dev_input()


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


# ================================================================ abilities ==

func _activate(ability: AbilityData, ctx: Dictionary) -> bool:
	ability.activate(ctx)
	if ctx["lock_movement"]:
		movement_enabled = false
	if ctx["activated"]:
		light -= _ability_cost(ability)
	return ctx["activated"]


func _tick_abilities(delta: float) -> void:
	if channeling_orb_index != -1:
		return

	# If an orb is in targeting mode, tick its hold abilities in parallel with the queue.
	if _targeting_orb_index >= 0:
		_tick_targeting_hold_abilities(delta)

	if _ability_queue.size() > 0:
		_tick_targeting(delta)
		queue_redraw()
		return

	var max_orb_t: float    = 0.0
	var orbs:      Array[Orb] = $Inventory.orbs

	for i in range(orbs.size()):
		# Skip orbs already being handled by the targeting queue.
		if i == _targeting_orb_index:
			continue

		var orb: Orb = orbs[i]

		if not _orb_is_usable(i):
			_log_blocked_orb(i, orb)
			continue

		var hold_count:      int   = _count_hold_abilities(orb)
		var has_hold:        bool  = hold_count > 0
		var holds_completed: int   = 0
		var hold_t_sum:      float = 0.0
		var orb_activated:   bool  = false
		var any_activated:   bool  = false

		for ability: AbilityData in orb.abilities:
			match ability.trigger_type:
				AbilityData.TriggerType.PASSIVE:
					_activate(ability, _make_context(delta, false, i))

				AbilityData.TriggerType.ACTIVE:
					if not ability.requires_hold:
						_handle_nonhold_ability(ability, i)
					else:
						var result := _handle_hold_ability(ability, delta, i, orb.nonhold_fired)
						holds_completed += result["completed"]
						any_activated    = any_activated or result["activated"]
						hold_t_sum      += result["orb_t"]

		# Open the ability queue if a non-hold ability was just queued.
		var queue_just_opened: bool = false
		if _ability_queue.size() > 0 and _targeting_orb_index == -1:
			_targeting_orb_index = i
			queue_just_opened    = true
			_queue_any_activated = false
			if has_hold:
				orb.nonhold_fired = true
			_advance_ability_queue(delta)

		if not queue_just_opened:
			orb_activated = _resolve_orb_glow(i, orb, has_hold, hold_count, holds_completed,
				hold_t_sum, any_activated)

		max_orb_t = maxf(max_orb_t, orb_visuals[i].glow)

		if orb_activated:
			shatter_orb(i)
			_trigger_connections(i, delta)

	_update_body_glow(max_orb_t)


# Returns a context dictionary for an ability activation.
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


func _ability_cost(ability: AbilityData) -> float:
	return ability.stats.light_cost if ability.stats and "light_cost" in ability.stats else 0.0


func _can_afford(ability: AbilityData) -> bool:
	return light >= _ability_cost(ability)


func _orb_is_usable(i: int) -> bool:
	var orb: Orb = $Inventory.orbs[i]
	return orb.node_index != -1 and not orb_visuals[i].shattered and orb.input_action != ""


func _log_blocked_orb(i: int, orb: Orb) -> void:
	if orb.input_action == "" or not Input.is_action_just_pressed(orb.input_action):
		return
	if orb.node_index == -1:
		print("[orb %d] blocked: not placed in graph" % i)
	elif orb_visuals[i].shattered:
		print("[orb %d] blocked: shattered (%.2fs remaining)" % [i,
			orb_visuals[i].cooldown - orb_visuals[i].cooldown_age])


func _count_hold_abilities(orb: Orb) -> int:
	var count: int = 0
	for ability: AbilityData in orb.abilities:
		if ability.trigger_type == AbilityData.TriggerType.ACTIVE and ability.requires_hold:
			count += 1
	return count


func _handle_nonhold_ability(ability: AbilityData, orb_index: int) -> void:
	var orb: Orb = $Inventory.orbs[orb_index]
	if not Input.is_action_just_pressed(orb.input_action):
		return
	if not _can_afford(ability):
		print("[orb %d] blocked: can't afford %s (cost %.1f, have %.1f)" % [
			orb_index, ability.resource_path.get_file(), _ability_cost(ability), light])
	elif _targeting_orb_index != -1:
		print("[orb %d] blocked: another orb is in targeting mode (orb %d)" % [
			orb_index, _targeting_orb_index])
	else:
		_ability_queue.append(ability)


# Returns { completed, activated, orb_t } for a single hold ability this frame.
func _handle_hold_ability(ability: AbilityData, delta: float,
		orb_index: int, nonhold_fired: bool) -> Dictionary:
	var orb:    Orb    = $Inventory.orbs[orb_index]
	var result: Dictionary = { "completed": 0, "activated": false, "orb_t": 0.0 }

	if Input.is_action_just_pressed(orb.input_action) and nonhold_fired:
		print("[orb %d] blocked: hold ability skipped — nonhold already fired this press" % orb_index)
		return result

	if Input.is_action_pressed(orb.input_action) and _can_afford(ability):
		var ctx := _make_context(delta, true, orb_index)
		if _activate(ability, ctx):
			result["completed"] = 1
			result["activated"] = true
		result["orb_t"] = ctx["orb_t"]
	elif Input.is_action_just_pressed(orb.input_action) and not _can_afford(ability):
		print("[orb %d] blocked: can't afford hold ability %s (cost %.1f, have %.1f)" % [
			orb_index, ability.resource_path.get_file(), _ability_cost(ability), light])
	elif Input.is_action_just_released(orb.input_action):
		_activate(ability, _make_context(delta, false, orb_index))

	return result


# Resolves glow state and returns true if the orb should shatter this frame.
func _resolve_orb_glow(i: int, orb: Orb, has_hold: bool, hold_count: int,
		holds_completed: int, hold_t_sum: float, any_activated: bool) -> bool:
	if not has_hold:
		return false

	var released: bool = Input.is_action_just_released(orb.input_action)

	if released and orb.nonhold_fired:
		orb.nonhold_fired = false
		if any_activated:
			orb_visuals[i].glow_target = 1.0
			return true
		orb_visuals[i].glow_target = 0.0  # ← activated but nothing fired; reset
	elif holds_completed >= hold_count and hold_count > 0 and any_activated:
		orb_visuals[i].glow_target = 1.0
		orb.nonhold_fired          = false
		return true
	elif Input.is_action_pressed(orb.input_action):
		orb_visuals[i].glow_target = hold_t_sum / float(hold_count)
	elif released:
		orb_visuals[i].glow_target = 0.0

	return false


func _update_body_glow(t: float) -> void:
	var glow: Color = Color(lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t))
	var c:    Color = glow if t > 0.0 else Color.WHITE
	%body.self_modulate = c
	%head.self_modulate = c


# ================================================================ targeting ==

func _advance_ability_queue(delta: float) -> void:
	# Immediately fire all NONE-targeting abilities in the queue.
	while _ability_queue.size() > 0:
		var ability: AbilityData = _ability_queue[0]
		if ability.targeting_mode != AbilityData.TargetingMode.NONE:
			queue_redraw()
			return
		_ability_queue.pop_front()
		if _can_afford(ability):
			var ctx := _make_context(delta, true, _targeting_orb_index)
			if _activate(ability, ctx):
				_queue_any_activated = true

	# Queue is empty — check if we still need to wait for a hold ability.
	var queued_orb: Orb = $Inventory.orbs[_targeting_orb_index]
	if _count_hold_abilities(queued_orb) > 0:
		_queue_hold_pending = true
	elif _queue_any_activated:
		_finish_orb_activation(delta)
	else:
		_targeting_orb_index = -1
		queue_redraw()


func _tick_targeting_hold_abilities(delta: float) -> void:
	var queued_orb:     Orb   = $Inventory.orbs[_targeting_orb_index]
	var hold_count:     int   = 0
	var holds_completed: int  = 0
	var hold_t_sum:     float = 0.0

	for ability: AbilityData in queued_orb.abilities:
		if ability.trigger_type != AbilityData.TriggerType.ACTIVE or not ability.requires_hold:
			continue
		hold_count += 1
		if Input.is_action_pressed(queued_orb.input_action) and _can_afford(ability):
			var ctx := _make_context(delta, true, _targeting_orb_index)
			if _activate(ability, ctx):
				holds_completed      += 1
				_queue_any_activated  = true
			hold_t_sum += ctx["orb_t"]
		elif Input.is_action_just_released(queued_orb.input_action):
			_activate(ability, _make_context(delta, false, _targeting_orb_index))

	if hold_count > 0 and Input.is_action_pressed(queued_orb.input_action):
		orb_visuals[_targeting_orb_index].glow_target = hold_t_sum / float(hold_count)

	if _queue_hold_pending:
		var hold_done: bool = holds_completed >= hold_count and hold_count > 0
		var released:  bool = Input.is_action_just_released(queued_orb.input_action)
		if hold_done or released:
			_queue_hold_pending = false
			_finish_orb_activation(delta)


func _tick_targeting(delta: float) -> void:
	if _ability_queue.size() == 0:
		return

	var ability:    AbilityData               = _ability_queue[0]
	var orb_action: String                    = $Inventory.orbs[_targeting_orb_index].input_action
	var mode:       AbilityData.TargetingMode = ability.targeting_mode
	var target:     Vector2                   = _get_clamped_target(ability)

	var cancel: bool = Input.is_action_just_pressed("cancel") \
		or (orb_action != "" and Input.is_action_just_pressed(orb_action))
	if cancel:
		_clear_enemy_outlines()
		_selected_enemies.clear()
		_ability_queue.pop_front()
		_advance_ability_queue(delta)
		return

	if mode == AbilityData.TargetingMode.ENEMY:
		_tick_enemy_targeting(ability, delta)
		return

	if Input.is_action_just_pressed("confirm"):
		var ctx          := _make_context(delta, true, _targeting_orb_index)
		ctx["target_pos"] = target
		if _activate(ability, ctx):
			_queue_any_activated = true
		_ability_queue.pop_front()
		_advance_ability_queue(delta)


func _tick_enemy_targeting(ability: AbilityData, delta: float) -> void:
	var hovered: Node = _find_hovered_enemy(ability)
	_set_hovered_enemy(hovered)

	if not Input.is_action_just_pressed("confirm") or hovered == null:
		return
	if hovered in _selected_enemies:
		return

	_selected_enemies.append(hovered)
	if hovered.has_method("set_outline"):
		hovered.set_outline(true)

	if _selected_enemies.size() >= ability.max_targets:
		var ctx       := _make_context(delta, true, _targeting_orb_index)
		ctx["targets"] = _selected_enemies.duplicate()
		if _activate(ability, ctx):
			_queue_any_activated = true
		_clear_enemy_outlines()
		_selected_enemies.clear()
		_ability_queue.pop_front()
		_advance_ability_queue(delta)


func _finish_orb_activation(delta: float) -> void:
	orb_visuals[_targeting_orb_index].glow_target = 1.0
	shatter_orb(_targeting_orb_index)
	_trigger_connections(_targeting_orb_index, delta)
	_targeting_orb_index = -1
	_queue_hold_pending  = false
	_queue_any_activated = false
	queue_redraw()


func _find_hovered_enemy(ability: AbilityData) -> Node:
	var mouse:  Vector2 = get_global_mouse_position()
	var range:  float   = ability.stats.range if ability.stats and "range" in ability.stats else 0.0
	var best_d: float   = 32.0
	var result: Node    = null

	var groups: Array[String] = ["enemies"]
	if ability is AbilityLightningChain:
		groups.append("conductor_posts")

	for group in groups:
		for target in get_tree().get_nodes_in_group(group):
			if range > 0.0 and target.global_position.distance_to(global_position) > range:
				continue
			var d: float = target.global_position.distance_to(mouse)
			if d < best_d:
				best_d = d
				result = target
	return result


func _set_hovered_enemy(enemy: Node) -> void:
	if _hovered_enemy == enemy:
		return
	_set_outline(_hovered_enemy, false)
	_hovered_enemy = enemy
	_set_outline(_hovered_enemy, true)


func _set_outline(node: Node, enabled: bool) -> void:
	if node and node not in _selected_enemies and node.has_method("set_outline"):
		node.set_outline(enabled)


func _clear_enemy_outlines() -> void:
	for enemy in _selected_enemies:
		if enemy and enemy.has_method("set_outline"):
			enemy.set_outline(false)
	if _hovered_enemy and _hovered_enemy.has_method("set_outline"):
		_hovered_enemy.set_outline(false)
	_hovered_enemy = null


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

	# Pick an orb to begin channeling when the player holds channel + orb button.
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

	# Reform any orbs whose cooldown has expired.
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

	# Update position, glow, and brightness for each orb sprite.
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

		# Skip one frame after reform so physics interpolation resets cleanly.
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
	var ov:              OrbVisual = OrbVisual.new()
	ov.sprite                      = Sprite2D.new()
	ov.sprite.texture              = orb.sprite_texture
	ov.sprite.centered             = true
	ov.sprite.visible              = false
	ov.sprite.z_as_relative        = false
	ov.sprite.z_index              = 4096
	add_child(ov.sprite)
	orb_visuals.append(ov)
	_auto_assign_slot(orb)


func _on_orb_removed(orb: Orb) -> void:
	var idx: int = $Inventory.orbs.find(orb)
	if idx == -1 or idx >= orb_visuals.size():
		return
	orb_visuals[idx].sprite.queue_free()
	orb_visuals.remove_at(idx)


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
	for n in range(1, 8):
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
	light            -= _compute_orb_light_cost(orb)
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


# ===================================================================== draw ==

func _draw() -> void:
	if _ability_queue.size() == 0:
		return

	var ability:      AbilityData               = _ability_queue[0]
	var mode:         AbilityData.TargetingMode = ability.targeting_mode
	var range:        float                     = ability.stats.range \
		if ability.stats and "range" in ability.stats else 0.0
	var target_local: Vector2                   = to_local(_get_clamped_target(ability))

	if range > 0.0 and mode != AbilityData.TargetingMode.SELF_AREA \
					and mode != AbilityData.TargetingMode.DIRECTION \
					and mode != AbilityData.TargetingMode.NONE:
		draw_arc(Vector2.ZERO, range, 0, TAU, 64, Color(1.0, 1.0, 1.5, 0.18), 1.0)

	match mode:
		AbilityData.TargetingMode.AREA:
			draw_arc(target_local, ability.stats.aoe_radius, 0, TAU, 48,
				Color(1.5, 1.5, 2.0, 0.5), 1.0)
		AbilityData.TargetingMode.SELF_AREA:
			draw_arc(Vector2.ZERO, ability.stats.aoe_radius, 0, TAU, 48,
				Color(1.5, 1.5, 2.0, 0.5), 1.0)
		AbilityData.TargetingMode.DIRECTION:
			var local_mouse: Vector2 = get_local_mouse_position()
			var dir:         Vector2 = local_mouse.normalized()
			var draw_range:  float   = minf(ability.stats.range, local_mouse.length()) \
				if range > 0.0 else ability.stats.range
			draw_line(Vector2.ZERO, dir * draw_range, Color(1.5, 1.5, 2.0, 0.5), 1.0)
		AbilityData.TargetingMode.POINT:
			draw_arc(target_local, 6.0, 0, TAU, 16, Color(1.5, 1.5, 2.0, 0.5), 1.0)
		AbilityData.TargetingMode.ENEMY:
			for enemy in _selected_enemies:
				if enemy:
					draw_line(Vector2.ZERO, to_local(enemy.global_position),
						Color(1.5, 1.5, 2.0, 0.4), 1.0)
			if _hovered_enemy and _hovered_enemy not in _selected_enemies:
				draw_line(Vector2.ZERO, to_local(_hovered_enemy.global_position),
					Color(1.5, 1.5, 2.0, 0.25), 1.0)
			var remaining: int = ability.max_targets - _selected_enemies.size()
			if remaining > 0:
				draw_string(ThemeDB.fallback_font, get_local_mouse_position() + Vector2(10, -10),
					"x%d" % remaining, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
					Color(1.5, 1.5, 2.0, 0.8))


# =================================================================== helpers ==

func _get_clamped_target(ability: AbilityData) -> Vector2:
	var mouse:  Vector2 = get_global_mouse_position()
	var range:  float   = ability.stats.range if ability.stats and "range" in ability.stats else 0.0
	if range <= 0.0:
		return mouse
	var offset: Vector2 = mouse - global_position
	if offset.length() > range:
		offset = offset.normalized() * range
	return global_position + offset


func _trigger_connections(orb_index: int, delta: float) -> void:
	var node_index: int = $Inventory.orbs[orb_index].node_index
	if node_index == -1:
		return
	GraphManager.on_orb_fired(node_index, {}, $Inventory.orbs[orb_index])


func Log(msg: Variant) -> void:
	print("[player.gd] " + str(msg))
