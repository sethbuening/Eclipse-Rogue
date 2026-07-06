class_name Enemy
extends Node

@export var data: EnemyData
@export var min_spawn_distance_tiles: int = 15

const DAMAGE_FLASH_DURATION: float = 0.08
const STUCK_TIMEOUT:         float = 0.6
const STUCK_DIST_SQ:         float = 4.0
const PUSH_STRENGTH:         float = 0.5
const SPAWN_SCREEN_MARGIN:   float = 48.0
const EFFECT_PATH:           String = "res://scripts/effects/"

const EffectIconDisplayScript = preload("res://scripts/effects/effect_icon_display.gd")
const FlashShader             = preload("res://scripts/enemies/damage_flash.gdshader")

static var _effect_registry: Dictionary = {}

var health:          int
var global_position: Vector2 = Vector2.ZERO
var player:          CharacterBody2D
var tilemap:         Node = null
var _offscreen:      bool = false

signal died(enemy: Enemy)

var _velocity:        Vector2    = Vector2.ZERO
var _ai_accum:        float      = 0.0
var _effects:         Dictionary = {}
var _attack_cooldown: float      = 0.0
var _icon_display:    EffectIconDisplay = null
var _damage_flash:    float      = 0.0
var _z_timer:         float      = 0.0
var _z_update_every:  float      = 0.5
var _z_offset:        float      = 0.0
var _last_flow_dir:   Vector2    = Vector2.ZERO
var _stuck_timer:     float      = 0.0
var _stuck_pos:       Vector2    = Vector2.ZERO

# Throttling state for offscreen movement integration (set by EnemyManager)
var _move_accum: float = 0.0
var _move_skip:  int   = 0

# --- OPT: Cached child references (set in setup / _cache_children) ---
# Avoids get_children() iteration in _sync_children, _set_flash, _update_z_index,
# deactivate, and _apply_flash_shader — all of which previously looped blindly.
var _sprite_nodes:  Array[Node2D] = []   # all Node2D children (sprite + health bar etc.)
var _flash_nodes:   Array[Node2D] = []   # subset that have a ShaderMaterial (for flash)

# --- OPT: Per-cell solid-tile neighbour cache ---
# Maps tilemap cell Vector2i → Array[Vector2] of solid tile world centres.
# Built on first visit, cleared when tilemap changes.  Cuts _resolve_tiles_r from
# always scanning 9 tiles to only testing the pre-filtered solid subset.
static var _solid_cache: Dictionary = {}

static func invalidate_tile_cache() -> void:
	_solid_cache.clear()

func setup(ai_tick_rate: float) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	health          = data.max_health
	_z_update_every = ai_tick_rate * 10.0
	_z_offset       = randf() * _z_update_every
	add_to_group("enemies")
	_cache_children()

func initialize(p: CharacterBody2D, modifier: Util.Modifier = Util.Modifier.NONE) -> void:
	data   = data.duplicate()
	health = data.max_health
	player = p
	_apply_modifier(modifier)
	global_position = _find_spawn_position()
	if _icon_display == null:
		_apply_flash_shader()
		_spawn_icon_display()
	else:
		_icon_display.visible = true
		_icon_display.set_effects(_effects)

# --- OPT: Build cached child lists once at setup (and after adding icon display) ---
func _cache_children() -> void:
	_sprite_nodes.clear()
	_flash_nodes.clear()
	for child in get_children():
		if child is Node2D:
			_sprite_nodes.append(child as Node2D)
			if (child is Sprite2D or child is AnimatedSprite2D) and child.material is ShaderMaterial:
				_flash_nodes.append(child as Node2D)

func tick_move(delta: float, offscreen: bool = false) -> void:
	var motion: Vector2 = _velocity
	var kb: EffectKnockback = _effects.get("knockback") as EffectKnockback
	if kb != null: motion += kb.velocity
	_move(motion, delta, offscreen)
	if offscreen:
		return
	if _damage_flash > 0.0:
		_damage_flash -= delta
		_set_flash(clampf(_damage_flash / DAMAGE_FLASH_DURATION, 0.0, 1.0))
	elif _damage_flash == 0.0:
		_damage_flash = -1.0
		_set_flash(0.0)
	# OPT: inline _sync_children using cached array — no get_children() call
	var gp: Vector2 = global_position
	for node in _sprite_nodes:
		node.global_position = gp
	if _icon_display: _icon_display.global_position = gp
	_z_timer += delta
	if _z_timer >= _z_update_every + _z_offset:
		_z_timer = 0.0
		_z_offset = 0.0
		_update_z_index()

func tick_ai(delta: float) -> void:
	_tick_effects(delta)

func _tick_behavior(_delta: float) -> void:
	pass

func _in_wall() -> bool:
	return tilemap != null and not tilemap.is_air(tilemap.world_to_map(global_position))

func _move(vel: Vector2, delta: float, offscreen: bool) -> void:
	var motion: Vector2 = vel * delta
	if motion.length_squared() < 0.01: return
	var prev: Vector2 = global_position
	var r: float = data.collision_radius
	global_position.x += motion.x
	_resolve_tiles_r(true, r)
	global_position.y += motion.y
	_resolve_tiles_r(false, r)
	if _in_wall():
		global_position = prev

# --- OPT: Solid-tile neighbour cache ---
# Instead of always testing all 9 offsets and calling tile_exists + is_air for each,
# we look up (or build) a per-cell list of only the solid tile world-centres.
# Building costs one full 9-scan on first visit; subsequent visits do zero tile queries.
const _NEIGHBOUR_OFFSETS: Array[Vector2i] = [
	Vector2i(0,0),  Vector2i(1,0),  Vector2i(-1,0),
	Vector2i(0,1),  Vector2i(0,-1),
	Vector2i(1,1),  Vector2i(-1,1), Vector2i(1,-1), Vector2i(-1,-1),
]

func _get_solid_neighbours(center: Vector2i) -> Array:
	if _solid_cache.has(center):
		return _solid_cache[center]
	var solid: Array = []
	for offset in _NEIGHBOUR_OFFSETS:
		var tile: Vector2i = center + offset
		if tilemap.tile_exists(tile) and not tilemap.is_air(tile):
			solid.append(tilemap.map_to_world(tile))
	_solid_cache[center] = solid
	return solid

func _resolve_tiles_r(x_axis: bool, r: float) -> void:
	if tilemap == null: return
	var half:   float    = tilemap.TILE_SIZE.x * 0.5
	var center: Vector2i = tilemap.world_to_map(global_position)
	var r_sq:   float    = r * r
	# OPT: only iterate pre-filtered solid tiles from cache
	for tc: Vector2 in _get_solid_neighbours(center):
		var closest: Vector2 = global_position.clamp(tc - Vector2(half,half), tc + Vector2(half,half))
		var diff:    Vector2 = global_position - closest
		var dist_sq: float   = diff.length_squared()
		if dist_sq >= r_sq: continue
		var dist: float = sqrt(dist_sq)
		var normal: Vector2
		if dist < 0.0001:
			var away: Vector2 = global_position - tc
			normal = away.normalized() if away.length_squared() > 0.0001 else Vector2(1,0)
		else:
			normal = diff / dist
		var push: float = (r - dist) * PUSH_STRENGTH
		if x_axis: global_position.x += normal.x * push
		else:       global_position.y += normal.y * push
	var play_radius_world: float = (tilemap.WIDTH - tilemap.BUFFER_TILES) / 2.0 * tilemap.TILE_SIZE.x * tilemap.get_parent().scale.x
	var dist: float = global_position.length()
	if dist > play_radius_world:
		global_position = global_position / dist * play_radius_world

func _tick_attack(delta: float) -> void:
	if data.projectile_speed > 0.0: return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if _attack_cooldown > 0.0: return
	if global_position.distance_squared_to(player.global_position) <= data.attack_range * data.attack_range:
		_attack_cooldown  = data.attack_cooldown
		var is_crit: bool = randf() < data.crit_chance
		var damage:  int  = data.damage
		if is_crit: damage = int(damage * data.crit_damage_mult)
		player.take_damage(damage, data.armor_penetration, is_crit)

func deal_damage_to_player(raw_damage: int, is_crit: bool = false) -> void:
	player.take_damage(raw_damage, data.armor_penetration, is_crit)

func take_damage(amount: int, armor_pen: int = 0, is_crit: bool = false, damage_type: Util.DamageType = Util.DamageType.PHYSICAL) -> void:
	var after_armor: int   = maxi(1, amount - maxi(0, data.armor - armor_pen))
	var resistance:  float = _get_elemental_resistance(damage_type)
	var reduced:     int   = maxi(1, int(float(after_armor) * (1.0 - data.damage_reduction) * (1.0 - resistance)))
	health -= reduced
	_damage_flash = DAMAGE_FLASH_DURATION
	DamageNumbers.spawn(global_position + Vector2(0,-16), reduced, is_crit)
	if health <= 0: die()

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

func deactivate() -> void:
	_velocity      = Vector2.ZERO
	_last_flow_dir = Vector2.ZERO
	_stuck_pos     = Vector2.ZERO
	_attack_cooldown = 0.0
	_ai_accum      = 0.0
	_z_timer       = 0.0
	_stuck_timer   = 0.0
	_damage_flash  = -1.0
	_offscreen     = false
	_move_accum    = 0.0
	_move_skip     = 0
	_effects.clear()
	if _icon_display: _icon_display.set_effects(_effects)
	_set_flash(0.0)
	# OPT: iterate cached list instead of get_children()
	for node in _sprite_nodes:
		node.visible = false

func apply_stun(duration: float) -> void:
	var d: float = duration * (1.0 - data.stun_resistance)
	if d <= 0.0: return
	var effect: EffectData = _get_or_create_effect("stun")
	if effect == null: return
	effect.apply(self, d)
	_sync_effect_icons()

func apply_slow(amount: float, duration: float) -> void:
	var a: float = clampf(amount, 0.0, 1.0) * (1.0 - data.slow_resistance)
	if a <= 0.0: return
	var effect := _get_or_create_effect("slow") as EffectSlow
	if effect == null: return
	effect.amount = a
	effect.apply(self, duration)
	_sync_effect_icons()

func apply_dot(dps: float, duration: float) -> void:
	var d: float = dps * (1.0 - data.dot_resistance)
	if d <= 0.0: return
	var effect := _get_or_create_effect("dot") as EffectDot
	if effect == null: return
	effect.dps = d
	effect.apply(self, duration)
	_sync_effect_icons()

func apply_knockback(impulse: Vector2) -> void:
	var v: Vector2 = impulse * (1.0 - data.knockback_resistance)
	if v.length_squared() <= 0.0: return
	var effect := _get_or_create_effect("knockback") as EffectKnockback
	if effect == null: return
	effect.velocity += v
	effect.apply(self, 0.0)

func apply_effect(effect: EffectData, duration: float) -> void:
	if not _effects.has(effect.id): _effects[effect.id] = effect
	(_effects[effect.id] as EffectData).apply(self, duration)
	_sync_effect_icons()

func remove_effect(effect_id: String) -> void:
	if not _effects.has(effect_id): return
	(_effects[effect_id] as EffectData).on_remove(self)
	_effects.erase(effect_id)
	_sync_effect_icons()

func _tick_effects(delta: float) -> void:
	if _effects.is_empty(): return
	var expired: Array[String] = []
	for id in _effects:
		var effect: EffectData = _effects[id]
		effect.tick(delta, self)
		if not is_inside_tree(): return
		if effect.is_expired(): expired.append(id)
	for id in expired:
		(_effects[id] as EffectData).on_remove(self)
		_effects.erase(id)
	if not expired.is_empty(): _sync_effect_icons()

func _get_or_create_effect(key: String) -> EffectData:
	if not _effects.has(key):
		# OPT: hoist registry lookup — _effect_scripts() checks is_empty() every call;
		# storing in a local avoids the repeated static-var dict access on hot paths.
		var registry: Dictionary = _effect_scripts()
		if not registry.has(key):
			push_warning("Enemy: no effect registered for id '%s'" % key)
			return null
		_effects[key] = (registry[key] as GDScript).new()
	return _effects[key]

static func _effect_scripts() -> Dictionary:
	if _effect_registry.is_empty():
		_effect_registry = Util.load_scripts(EFFECT_PATH)
	return _effect_registry

func _sync_effect_icons() -> void:
	if _icon_display: _icon_display.set_effects(_effects)

func _apply_modifier(modifier: Util.Modifier) -> void:
	if modifier == Util.Modifier.FAST: data.speed *= 1.6

# OPT: replaced with cached-array version inlined into tick_move
# (kept as no-op so subclasses calling super._sync_children() don't break)
func _sync_children() -> void:
	var gp: Vector2 = global_position
	for node in _sprite_nodes:
		node.global_position = gp

# OPT: use cached _sprite_nodes instead of get_children()
func _update_z_index() -> void:
	var z: int = tilemap.get_z_for(global_position)
	for node in _sprite_nodes:
		node.z_index = z

func _find_spawn_position() -> Vector2:
	if not is_instance_valid(player): return Vector2.ZERO
	if tilemap == null: return player.global_position
	var pos: Vector2 = _raycast_offscreen_spawn()
	if pos != Vector2.INF: return pos
	var origin: Vector2i = tilemap.world_to_map(player.global_position)
	for _i in range(40):
		var off: Vector2i = Vector2i(randi_range(-20,20), randi_range(-20,20))
		var c:   Vector2i = origin + off
		if not _in_bounds(c) or abs(off.x)+abs(off.y) < min_spawn_distance_tiles: continue
		if _is_clear(c): return tilemap.map_to_world(c)
	for _i in range(40):
		var off: Vector2i = Vector2i(randi_range(-25,25), randi_range(-25,25))
		var c:   Vector2i = origin + off
		if not _in_bounds(c) or abs(off.x)+abs(off.y) < min_spawn_distance_tiles: continue
		if tilemap.is_air(c): return tilemap.map_to_world(c)
	push_warning("[Enemy] No valid spawn for %s" % data.id)
	return player.global_position

func _raycast_offscreen_spawn() -> Vector2:
	var cam: Camera2D = tilemap.camera
	if cam == null: return Vector2.INF
	var vp_size:    Vector2  = get_viewport().get_visible_rect().size
	var edge_dist:  float    = maxf((vp_size * 0.5 / cam.zoom).x, (vp_size * 0.5 / cam.zoom).y) + SPAWN_SCREEN_MARGIN
	var tile_size:  float    = float(tilemap.TILE_SIZE.x)
	var dir:        Vector2  = Vector2.RIGHT.rotated(randf() * TAU)
	var step_tiles: int      = int(ceil(edge_dist / tile_size))
	var origin:     Vector2i = tilemap.world_to_map(player.global_position)
	for step in range(step_tiles, step_tiles + 12):
		var c: Vector2i = tilemap.world_to_map(player.global_position + dir * (float(step) * tile_size))
		if not _in_bounds(c) or abs(c.x-origin.x)+abs(c.y-origin.y) < min_spawn_distance_tiles: continue
		if _is_clear(c): return tilemap.map_to_world(c)
	for step in range(step_tiles, step_tiles + 12):
		var c: Vector2i = tilemap.world_to_map(player.global_position + dir * (float(step) * tile_size))
		if not _in_bounds(c) or abs(c.x-origin.x)+abs(c.y-origin.y) < min_spawn_distance_tiles: continue
		if tilemap.is_air(c): return tilemap.map_to_world(c)
	return Vector2.INF

func _is_clear(pos: Vector2i) -> bool:
	if not tilemap.is_air(pos): return false
	for nb in [Vector2i(0,-1),Vector2i(0,1),Vector2i(-1,0),Vector2i(1,0)]:
		if not tilemap.is_air(pos+nb): return false
	return true

func _in_bounds(c: Vector2i) -> bool:
	var play_radius: float = (tilemap.WIDTH - tilemap.BUFFER_TILES) / 2.0
	var dx: float = float(c.x) - tilemap.WIDTH  / 2.0
	var dy: float = float(c.y) - tilemap.HEIGHT / 2.0
	return sqrt(dx*dx + dy*dy) < play_radius

func _spawn_icon_display() -> void:
	_icon_display = EffectIconDisplayScript.new()
	_icon_display.name = "EffectIconDisplay"
	add_child(_icon_display)
	# OPT: rebuild cache now that icon display is a child
	_cache_children()

func _apply_flash_shader() -> void:
	# OPT: use cached list; rebuilds it with shader materials set
	for node in _sprite_nodes:
		if node is Sprite2D or node is AnimatedSprite2D:
			var mat := ShaderMaterial.new()
			mat.shader = FlashShader
			node.material = mat
	# Rebuild flash subset now that materials are assigned
	_flash_nodes.clear()
	for node in _sprite_nodes:
		if (node is Sprite2D or node is AnimatedSprite2D) and node.material is ShaderMaterial:
			_flash_nodes.append(node)

func _set_flash(amount: float) -> void:
	# OPT: use pre-filtered _flash_nodes — no type checks, no get_children()
	for node in _flash_nodes:
		(node.material as ShaderMaterial).set_shader_parameter("flash_amount", amount)
