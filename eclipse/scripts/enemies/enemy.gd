class_name Enemy
extends Node

# ── exports ───────────────────────────────────────────────────────────────────

@export var data:                     EnemyData
@export var min_spawn_distance_tiles: int = 15

# ── constants ─────────────────────────────────────────────────────────────────

const ENEMY_RADIUS:    float = 8.0
const KNOCKBACK_DECAY: float = 8.0
const MIN_SEPARATION:  float = ENEMY_RADIUS * 2.0
var _damage_flash:          float = 0.0
var DAMAGE_FLASH_DURATION:  float = 0.08

const NavigatorScript         = preload("res://scripts/pathfinding/enemy_navigator.gd")
const EnemyHealthBarScript    = preload("res://scripts/enemies/enemy_health_bar.gd")
const EffectIconDisplayScript = preload("res://scripts/effects/effect_icon_display.gd")

## Folder scanned by Util.load_scripts() on first use.
## Every .gd file in this folder that has an [id] property is registered.
const EFFECT_PATH: String = "res://scripts/effects/"

## Registry: String id → GDScript.  Populated once by _effect_scripts().
static var _effect_registry: Dictionary = {}

# ── public state ──────────────────────────────────────────────────────────────

var health:          int
var global_position: Vector2 = Vector2.ZERO
var player:          CharacterBody2D
var tilemap:         Node = null

signal died(enemy: Enemy)

# ── private state ─────────────────────────────────────────────────────────────

var _navigator:       EnemyNavigator
var _velocity:        Vector2    = Vector2.ZERO

## Active effects: String id → EffectData instance.
var _effects:          Dictionary = {}

var _attack_cooldown: float            = 0.0
var _health_bar:      EnemyHealthBar   = null
var _icon_display:    EffectIconDisplay = null

var _z_timer:        float = 0.0
var _z_update_every: float = 0.5
var _z_offset:       float = 0.0

# ── setup ─────────────────────────────────────────────────────────────────────

func setup(ai_tick_rate: float) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	health          = data.max_health
	_z_update_every = ai_tick_rate * 10.0
	_z_offset       = randf() * _z_update_every
	_navigator      = NavigatorScript.new()
	_navigator.name = "Navigator"
	add_child(_navigator)
	add_to_group("enemies")

func initialize(p: CharacterBody2D, modifier: Util.Modifier = Util.Modifier.NONE) -> void:
	data   = data.duplicate()
	player = p
	_apply_modifier(modifier)
	_navigator.move_speed = data.speed
	global_position       = _find_spawn_position()
	_apply_flash_shader()
	_spawn_health_bar()
	_spawn_icon_display()

# ── tick API (called by EnemyManager) ────────────────────────────────────────

func tick_move(delta: float, offscreen: bool = false) -> void:
	if player == null:
		return
	var motion: Vector2 = _velocity
	# Knockback contributes extra velocity via its own EffectData.
	var kb: EffectKnockback = _effects.get("knockback") as EffectKnockback
	if kb != null:
		motion += kb.velocity
	_move(motion, delta, offscreen)

	if offscreen:
		return

	# visuals only matter onscreen
	if _damage_flash > 0.0:
		_damage_flash -= delta
		var t: float = clampf(_damage_flash / DAMAGE_FLASH_DURATION, 0.0, 1.0)
		_set_flash(t)
	elif _damage_flash == 0.0:
		_damage_flash = -1.0
		_set_flash(0.0)

	_sync_children()
	if _health_bar:
		_health_bar.global_position = global_position
	if _icon_display:
		_icon_display.global_position = global_position

	_z_timer += delta
	if _z_timer >= _z_update_every + _z_offset:
		_z_timer  = 0.0
		_z_offset = 0.0
		_update_z_index()

func tick_ai(delta: float) -> void:
	_tick_effects(delta)
	if _effects.has("stun"):
		return

	_tick_behavior(delta)
	_tick_attack(delta)

	var offscreen: bool     = EnemyManager.offscreen_enemies.has(self)
	var desired:   Vector2  = _navigator.navigate_toward(player.global_position, delta, true)
	if not offscreen:
		desired += _separation_velocity()
	_velocity = _velocity.lerp(desired, data.turn_speed * delta)

func _tick_behavior(_delta: float) -> void:
	pass

# ── movement ──────────────────────────────────────────────────────────────────

func _move(velocity: Vector2, delta: float, offscreen: bool = false) -> void:
	var motion: Vector2 = velocity * delta
	if motion.length_squared() < 0.01:
		return
	global_position.x += motion.x
	_resolve_tiles(true)
	global_position.y += motion.y
	_resolve_tiles(false)
	if not offscreen:
		_resolve_enemies()

func _resolve_tiles(x_axis: bool) -> void:
	if tilemap == null:
		return

	var half:   float    = tilemap.TILE_SIZE.x * 0.5
	var center: Vector2i = tilemap.world_to_map(global_position)
	var r_sq:   float    = ENEMY_RADIUS * ENEMY_RADIUS

	for offset in [
		Vector2i( 0,  0), Vector2i( 1,  0), Vector2i(-1,  0),
		Vector2i( 0,  1), Vector2i( 0, -1),
		Vector2i( 1,  1), Vector2i(-1,  1), Vector2i( 1, -1), Vector2i(-1, -1),
	]:
		var tile: Vector2i = center + offset
		if not tilemap.tile_exists(tile):
			continue

		var tile_center: Vector2 = tilemap.map_to_world(tile)
		var closest:     Vector2 = global_position.clamp(
			tile_center - Vector2(half, half),
			tile_center + Vector2(half, half)
		)
		var diff:    Vector2 = global_position - closest
		var dist_sq: float   = diff.length_squared()
		if dist_sq >= r_sq:
			continue

		var normal: Vector2
		if dist_sq < 0.0001:
			var away: Vector2 = global_position - tile_center
			normal = away.normalized() if away.length_squared() > 0.0001 else Vector2(1, 0)
		else:
			normal = diff / sqrt(dist_sq)

		var push: float = ENEMY_RADIUS - sqrt(dist_sq)
		if x_axis:
			global_position.x += normal.x * push
		else:
			global_position.y += normal.y * push

	var play_radius_world: float = (tilemap.WIDTH - tilemap.BUFFER_TILES) / 2.0 * tilemap.TILE_SIZE.x * tilemap.get_parent().scale.x
	var dist: float = global_position.length()
	if dist > play_radius_world:
		global_position = global_position / dist * play_radius_world

func _resolve_enemies() -> void:
	for other in EnemyManager.get_nearby_enemies(global_position, MIN_SEPARATION):
		if not is_instance_valid(other) or other == self:
			continue
		var away: Vector2 = global_position - other.global_position
		var d_sq: float   = away.length_squared()
		if d_sq >= MIN_SEPARATION * MIN_SEPARATION:
			continue
		if d_sq < 0.0001:
			global_position += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
			continue
		var dist: float = sqrt(d_sq)
		global_position += (away / dist) * (MIN_SEPARATION - dist) * 0.5

# ── separation ────────────────────────────────────────────────────────────────

func _separation_velocity() -> Vector2:
	var push:     Vector2 = Vector2.ZERO
	var sep_r:    float   = data.sep_radius
	var sep_r_sq: float   = sep_r * sep_r

	for other in EnemyManager.get_nearby_enemies(global_position, sep_r):
		if not is_instance_valid(other) or other == self:
			continue
		var away: Vector2 = global_position - other.global_position
		var d_sq: float   = away.length_squared()
		if d_sq >= sep_r_sq:
			continue
		if d_sq < 0.0001:
			push += Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * data.speed * data.sep_force
			continue
		var dist: float = sqrt(d_sq)
		push += (away / dist) * (1.0 - dist / sep_r) * data.speed * data.sep_force

	return push

# ── attack ────────────────────────────────────────────────────────────────────

func _tick_attack(delta: float) -> void:
	if data.projectile_speed > 0.0:
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if _attack_cooldown > 0.0:
		return
	if global_position.distance_squared_to(player.global_position) <= data.attack_range * data.attack_range:
		_attack_cooldown  = data.attack_cooldown
		var is_crit: bool = randf() < data.crit_chance
		var damage:  int  = data.damage
		if is_crit:
			damage = int(damage * data.crit_damage_mult)
		player.take_damage(damage, data.armor_penetration, is_crit)

func deal_damage_to_player(raw_damage: int, is_crit: bool = false) -> void:
	player.take_damage(raw_damage, data.armor_penetration, is_crit)

# ── incoming damage ───────────────────────────────────────────────────────────

func take_damage(amount: int, armor_pen: int = 0, is_crit: bool = false, damage_type: Util.DamageType = Util.DamageType.PHYSICAL) -> void:
	var after_armor: int = maxi(1, amount - maxi(0, data.armor - armor_pen))
	var resistance:  float = _get_elemental_resistance(damage_type)
	var reduced:     int = maxi(1, int(float(after_armor) * (1.0 - data.damage_reduction) * (1.0 - resistance)))
	health -= reduced
	_damage_flash = DAMAGE_FLASH_DURATION
	if _health_bar:
		_health_bar.on_damage(health)
	DamageNumbers.spawn(global_position + Vector2(0, -16), reduced, is_crit)
	if health <= 0:
		die()

func _get_elemental_resistance(damage_type: Util.DamageType) -> float:
	match damage_type:
		Util.DamageType.LIGHTNING: return data.lightning_resistance
		Util.DamageType.FIRE:      return data.fire_resistance
		Util.DamageType.ICE:       return data.ice_resistance
		Util.DamageType.POISON:    return data.poison_resistance
		_:                         return 0.0

func die() -> void:
	ItemManager.spawn_xp(global_position, data.xp_value)
	emit_signal("died", self)
	queue_free()

# ── effects — public API ───────────────────────────────────────────────
#
# Each apply_*() function is kept as a named convenience wrapper so that
# abilities and other callers don't need to construct EffectData
# instances manually.  All resistance scaling happens here before the
# data object is handed the final values.
#
# To add a new effect:
#   1. Create scripts/enemies/effects/effect_<name>.gd
#      extending EffectData.
#   2. Preload it at the top of this file.
#   3. Add an apply_<name>() method below.
#   That's it — _tick_effects() and the icon system handle the rest
#   automatically.

func apply_stun(duration: float) -> void:
	var d: float = duration * (1.0 - data.stun_resistance)
	if d <= 0.0:
		return
	var effect: EffectData = _get_or_create_effect("stun")
	if effect == null:
		return
	effect.apply(self, d)
	_sync_effect_icons()

func apply_slow(amount: float, duration: float) -> void:
	var a: float = clampf(amount, 0.0, 1.0) * (1.0 - data.slow_resistance)
	if a <= 0.0:
		return
	var effect := _get_or_create_effect("slow") as EffectSlow
	if effect == null:
		return
	effect.amount = a
	effect.apply(self, duration)
	_sync_effect_icons()

func apply_dot(dps: float, duration: float) -> void:
	var d: float = dps * (1.0 - data.dot_resistance)
	if d <= 0.0:
		return
	var effect := _get_or_create_effect("dot") as EffectDot
	if effect == null:
		return
	effect.dps = d
	effect.apply(self, duration)
	_sync_effect_icons()

func apply_knockback(impulse: Vector2) -> void:
	var v: Vector2 = impulse * (1.0 - data.knockback_resistance)
	if v.length_squared() <= 0.0:
		return
	var effect := _get_or_create_effect("knockback") as EffectKnockback
	if effect == null:
		return
	effect.velocity += v
	effect.apply(self, 0.0)
	# Knockback has no visible icon by default; no icon sync needed.

## Generic entry point for custom effects defined outside enemy.gd.
## [effect] must be an EffectData subclass instance with a valid id.
## The caller is responsible for resistance scaling and setting any
## subclass properties before calling this.
func apply_effect(effect: EffectData, duration: float) -> void:
	if not _effects.has(effect.id):
		_effects[effect.id] = effect
	(_effects[effect.id] as EffectData).apply(self, duration)
	_sync_effect_icons()

## Forcibly remove an effect by id, calling on_remove() first.
func remove_effect(effect_id: String) -> void:
	if not _effects.has(effect_id):
		return
	(_effects[effect_id] as EffectData).on_remove(self)
	_effects.erase(effect_id)
	_sync_effect_icons()

# ── effects — internal tick ────────────────────────────────────────────

func _tick_effects(delta: float) -> void:
	var expired: Array[String] = []

	for id in _effects:
		var effect: EffectData = _effects[id] as EffectData
		effect.tick(delta, self)
		if not is_inside_tree():
			return
		if effect.is_expired():
			expired.append(id)

	for id in expired:
		(_effects[id] as EffectData).on_remove(self)
		_effects.erase(id)

	if not expired.is_empty():
		_sync_effect_icons()

# ── helpers ───────────────────────────────────────────────────────────────────

## Returns the existing effect for [key], or instantiates a fresh one
## from the registry.  Returns null and warns if the id is not registered.
func _get_or_create_effect(key: String) -> EffectData:
	if not _effects.has(key):
		var registry: Dictionary = _effect_scripts()
		if not registry.has(key):
			push_warning("Enemy: no effect registered for id '%s'" % key)
			return null
		_effects[key] = (registry[key] as GDScript).new()
	return _effects[key] as EffectData

## Returns the shared registry, populating it on first call.
static func _effect_scripts() -> Dictionary:
	if _effect_registry.is_empty():
		_effect_registry = Util.load_scripts(EFFECT_PATH)
	return _effect_registry

## Notifies the icon display to refresh its effect icon row.
func _sync_effect_icons() -> void:
	if _icon_display:
		_icon_display.set_effects(_effects)

func _apply_modifier(modifier: Util.Modifier) -> void:
	if modifier == Util.Modifier.FAST:
		data.speed *= 1.6

func _range_offset_target(target: Vector2, preferred_range: float) -> Vector2:
	if preferred_range <= 0.0:
		return target
	var to_target: Vector2 = target - global_position
	var dist:      float   = to_target.length()
	return global_position if dist <= preferred_range else target - to_target / dist * preferred_range

func _sync_children() -> void:
	for child in get_children():
		if child is EnemyHealthBar:
			continue
		if child is Node2D:
			child.global_position = global_position

func _update_z_index() -> void:
	var z: int = tilemap.get_z_for(global_position)
	for child in get_children():
		if child is Node2D:
			child.z_index = z

# ── spawn ─────────────────────────────────────────────────────────────────────

func _find_spawn_position() -> Vector2:
	if tilemap == null:
		return player.global_position
	var origin: Vector2i = tilemap.world_to_map(player.global_position)

	for _i in range(40):
		var off: Vector2i = Vector2i(randi_range(-20, 20), randi_range(-20, 20))
		var c:   Vector2i = origin + off
		if not _in_bounds(c) or abs(off.x) + abs(off.y) < min_spawn_distance_tiles:
			continue
		if _is_clear(c):
			return tilemap.map_to_world(c)

	for _i in range(40):
		var off: Vector2i = Vector2i(randi_range(-25, 25), randi_range(-25, 25))
		var c:   Vector2i = origin + off
		if not _in_bounds(c) or abs(off.x) + abs(off.y) < min_spawn_distance_tiles:
			continue
		if tilemap.is_air(c):
			return tilemap.map_to_world(c)

	push_warning("[Enemy] No valid spawn for %s" % data.id)
	return player.global_position

func _is_clear(pos: Vector2i) -> bool:
	if not tilemap.is_air(pos):
		return false
	for nb in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
		if not tilemap.is_air(pos + nb):
			return false
	return true

func _in_bounds(c: Vector2i) -> bool:
	var cx: float = tilemap.WIDTH  / 2.0
	var cy: float = tilemap.HEIGHT / 2.0
	var play_radius: float = (tilemap.WIDTH - tilemap.BUFFER_TILES) / 2.0
	var dx: float = float(c.x) - cx
	var dy: float = float(c.y) - cy
	return sqrt(dx * dx + dy * dy) < play_radius

const FlashShader = preload("res://scripts/enemies/damage_flash.gdshader")

func _spawn_health_bar() -> void:
	var bar := EnemyHealthBarScript.new()
	add_child(bar)
	if not bar.init(data.max_health):
		return   # bar freed itself — not needed for this enemy
	_health_bar = bar

func _spawn_icon_display() -> void:
	_icon_display = EffectIconDisplayScript.new()
	_icon_display.name = "EffectIconDisplay"
	add_child(_icon_display)

func _apply_flash_shader() -> void:
	for child in get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			var mat := ShaderMaterial.new()
			mat.shader = FlashShader
			child.material = mat

func _set_flash(amount: float) -> void:
	for child in get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			var mat := child.material as ShaderMaterial
			if mat:
				mat.set_shader_parameter("flash_amount", amount)
