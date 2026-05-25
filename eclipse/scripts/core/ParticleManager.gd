extends Node2D

class Particle:
	var pos:        Vector2
	var vel:        Vector2
	var z:          float        # vertical height (arc/bounce), NOT world z-sort
	var z_vel:      float
	var bounce:     float
	var lifetime:   float
	var age:        float
	var gradient:   Gradient
	var cast_shadow: bool
	var size:       float
	var use_gravity: bool
	var canvas_item: RID        # own canvas item for z-sorting

const GRAVITY: float = 400.0
var particles: Array[Particle] = []
var tilemap_manager: Node = null

func _ready() -> void:
	z_index = 1

func spawn(pos: Vector2, vel: Vector2, z_vel: float, gradient: Gradient, lifetime: float, size: float = 3.0, bounce: float = 0.4, cast_shadow: bool = true, use_grav: bool = true) -> Particle:
	var p         := Particle.new()
	p.pos          = pos
	p.vel          = vel
	p.z            = 0.0
	p.z_vel        = z_vel
	p.bounce       = bounce
	p.lifetime     = lifetime
	p.age          = 0.0
	p.gradient     = gradient
	p.cast_shadow  = cast_shadow
	p.size         = size
	p.use_gravity  = use_grav
	p.canvas_item  = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(p.canvas_item, get_canvas())
	RenderingServer.canvas_item_set_z_index(p.canvas_item, _sort_z_for(pos))
	RenderingServer.canvas_item_set_z_as_relative_to_parent(p.canvas_item, false)
	particles.append(p)
	return p

func _sort_z_for(world_pos: Vector2) -> int:
	if tilemap_manager == null:
		return 0
	return clampi(tilemap_manager.get_z_for(world_pos), RenderingServer.CANVAS_ITEM_Z_MIN, RenderingServer.CANVAS_ITEM_Z_MAX)

func spawn_focus_spark(pos: Vector2) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(2.0, 2.0, 1.6))
	gradient.add_point(0.4, Color(2.0, 1.4, 0.2))
	gradient.set_color(1, Color(1.2, 0.3, 0.0))
	for i: int in range(randi_range(4, 7)):
		spawn(
			pos,
			Vector2(randf_range(-120, 120), randf_range(-120, 120)),
			randf_range(80, 200),
			gradient,
			randf_range(2, 2.3),
			randf_range(1.5, 2.0),
			0.35,
			false,
			true
		)

func spawn_mine_chunk(pos: Vector2, tile_color: Color) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, tile_color)
	gradient.set_color(1, Color(tile_color.r * 0.5, tile_color.g * 0.5, tile_color.b * 0.5))
	for i: int in range(randi_range(2, 4)):
		spawn(
			pos,
			Vector2(randf_range(-60, 60), randf_range(-60, 0)),
			randf_range(40, 120),
			gradient,
			randf_range(0.2, 0.5),
			randf_range(3.0, 6.0),
			0.5,
			true,
			true
		)

func spawn_mine_chunk_directional(pos: Vector2, tile_color: Color, vel_bias: Vector2) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, tile_color)
	gradient.set_color(1, Color(tile_color.r * 0.5, tile_color.g * 0.5, tile_color.b * 0.5))
	for i: int in range(randi_range(2, 4)):
		spawn(
			pos,
			Vector2(randf_range(-50, 50), randf_range(-70, 0)) + vel_bias,
			randf_range(40, 120),
			gradient,
			randf_range(0.2, 0.45),
			randf_range(3.0, 6.0),
			0.5,
			true,
			true
		)

func spawn_mine_dust(pos: Vector2, tile_type: Util.tile) -> void:
	var color: Color = _tile_dust_color(tile_type)
	var gradient     := Gradient.new()
	gradient.set_color(0, Color(color.r, color.g, color.b, 0.7))
	gradient.set_color(1, Color(color.r * 0.6, color.g * 0.6, color.b * 0.6, 0.0))
	for i in range(randi_range(3, 6)):
		spawn(
			pos + Vector2(randf_range(-8, 8), randf_range(-8, 8)),
			Vector2(randf_range(-30, 30), randf_range(-50, -10)),
			randf_range(20, 60),
			gradient,
			randf_range(0.3, 0.6),
			randf_range(2.0, 4.0),
			0.1,
			false
		)

func _tile_dust_color(tile_type: Util.tile) -> Color:
	match tile_type:
		Util.tile.STONE:   return Color(0.5, 0.45, 0.4)
		Util.tile.ROCK:    return Color(0.35, 0.32, 0.3)
		Util.tile.GOLD:    return Color(0.8, 0.65, 0.1)
		Util.tile.COPPER:  return Color(0.7, 0.4, 0.2)
		Util.tile.CRYSTAL: return Color(0.4, 0.6, 0.9)
		_:                 return Color(0.5, 0.45, 0.4)

func spawn_focus_particles(pos: Vector2, charge_t: float) -> void:
	var count: int = 0
	if charge_t <= 0.05:
		count = 1 if randf() < charge_t * 4.0 else 0
	else:
		count = int(lerpf(1.0, 3.0, charge_t))
	if count == 0:
		return

	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.1, 1.1, 1.4, 0.0))

	for i in range(count):
		var offset := Vector2(randf_range(-20.0, 20.0), randf_range(-8.0, 8.0))
		spawn(
			pos + offset,
			Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)),
			randf_range(45.0, 65.0),
			gradient,
			randf_range(0.5, 0.9),
			randf_range(1.25, 2.25),
			0.0,
			false,
			false
		)

func spawn_gold_bomb_trail(pos: Vector2) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(2.5, 2.0, 0.3, 1.0))
	gradient.add_point(0.4, Color(1.8, 1.0, 0.1, 0.8))
	gradient.set_color(1, Color(0.8, 0.3, 0.0, 0.0))
	for i in range(randi_range(2, 4)):
		spawn(
			pos + Vector2(randf_range(-3, 3), randf_range(-3, 3)),
			Vector2(randf_range(-20, 20), randf_range(-20, 20)),
			randf_range(10, 40),
			gradient,
			randf_range(0.15, 0.3),
			randf_range(2.0, 4.0),
			0.0,
			false,
			false
		)

func spawn_lightning_spark(pos: Vector2) -> void:
	# Core flash — bright white-blue, tight burst, no gravity (electric, not ballistic)
	var core_gradient := Gradient.new()
	core_gradient.set_color(0, Color(3.0, 3.0, 4.0, 1.0))       # blinding white-blue core
	core_gradient.add_point(0.3, Color(0.6, 0.8, 3.5, 0.9))      # electric blue mid
	core_gradient.set_color(1, Color(0.1, 0.2, 1.2, 0.0))        # deep blue fade
	for i in range(randi_range(5, 8)):
		spawn(
			pos + Vector2(randf_range(-4, 4), randf_range(-4, 4)),
			Vector2(randf_range(-160, 160), randf_range(-160, 160)),
			randf_range(0, 30),          # very low arc — electricity hugs the surface
			core_gradient,
			randf_range(0.12, 0.25),     # short-lived, snappy
			randf_range(1.5, 2.5),
			0.0,                         # no bounce — dissipates on contact
			false,                       # no shadow
			false                        # no gravity — floats outward
		)

	# Tendril streamers — longer, thinner, drift further
	var tendril_gradient := Gradient.new()
	tendril_gradient.set_color(0, Color(1.0, 1.4, 4.0, 0.8))     # vivid blue-violet
	tendril_gradient.add_point(0.5, Color(0.3, 0.5, 2.5, 0.5))
	tendril_gradient.set_color(1, Color(0.05, 0.1, 0.8, 0.0))
	for i in range(randi_range(3, 5)):
		var dir: Vector2 = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
		spawn(
			pos,
			dir * randf_range(60, 200),
			randf_range(10, 50),
			tendril_gradient,
			randf_range(0.2, 0.45),
			randf_range(1.0, 1.8),
			0.0,
			false,
			false
		)

func spawn_basic_attack_trail(pos: Vector2, dir: Vector2, speed: float) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.825, 1.825, 1.825, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.2, 0.0))
	spawn(
		pos + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)),
		dir * speed * randf_range(0.3, 0.5),
		0.0,
		gradient,
		randf_range(0.14, 0.22),
		randf_range(1.5, 2.5),
		0.0,
		false,
		false
	)

func spawn_basic_attack_explode(pos: Vector2) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(3.0, 3.0, 3.5, 1.0))
	gradient.add_point(0.3, Color(1.5, 1.5, 2.0, 0.8))
	gradient.set_color(1, Color(0.6, 0.6, 1.0, 0.0))
	for i in range(randi_range(6, 10)):
		var burst_dir: Vector2 = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		spawn(
			pos + burst_dir * randf_range(0.0, 3.0),
			burst_dir * randf_range(60.0, 160.0),
			randf_range(20.0, 80.0),
			gradient,
			randf_range(0.15, 0.3),
			randf_range(1.5, 3.0),
			0.0,
			false,
			false
		)

# -------------------------------------------------------------------- Sprite Particles ------------

class SpriteParticle:
	var pos:        Vector2
	var vel:        Vector2
	var z:          float
	var z_vel:      float
	var bounce:     float
	var lifetime:   float
	var age:        float
	var use_gravity: bool
	var texture:    Texture2D
	var overlay:    Texture2D   # null if no overlay (ore on rubble)
	var size:       Vector2     # draw size in pixels
	var rotation:   float
	var rot_vel:    float       # rotational velocity
	var fade_delay: float       # how long before it starts fading

var sprite_particles: Array[SpriteParticle] = []

func spawn_sprite(
				pos:        Vector2,
				vel:        Vector2,
				z_vel:      float,
				texture:    Texture2D,
				size:       Vector2,
				lifetime:   float,
				fade_delay: float   = 0.5,
				overlay:    Texture2D = null,
				bounce:     float   = 0.3,
				use_gravity: bool   = true,
				rot_vel:    float   = 0.0) -> void:
	var p          := SpriteParticle.new()
	p.pos           = pos
	p.vel           = vel
	p.z             = 0.0
	p.z_vel         = z_vel
	p.bounce        = bounce
	p.lifetime      = lifetime
	p.fade_delay    = fade_delay
	p.age           = 0.0
	p.use_gravity   = use_gravity
	p.texture       = texture
	p.overlay       = overlay
	p.size          = size
	p.rotation      = randf_range(0, TAU)
	p.rot_vel       = rot_vel
	sprite_particles.append(p)

# base_textures and overlay_textures set in inspector or loaded here
@export var rubble_stone:  Array[Texture2D] = []  # 10 sprites
@export var rubble_rock:   Array[Texture2D] = []  # 10 sprites
@export var ore_overlay_gold:   Array[Texture2D] = []  # 2-4 sprites
@export var ore_overlay_copper: Array[Texture2D] = []  # 2-4 sprites

func spawn_debris(pos: Vector2, tile_type: Util.tile) -> void:
	var base_set: Array[Texture2D] = _rubble_set_for(tile_type)
	if base_set.is_empty():
		return
	var count: int = randi_range(2, 4)
	for i in range(count):
		var tex: Texture2D = base_set[randi() % base_set.size()]
		spawn_sprite(
			pos + Vector2(randf_range(-6, 6), randf_range(-4, 4)),
			Vector2(randf_range(-40, 40), randf_range(-60, -10)),
			randf_range(30, 90),
			tex,
			Vector2(8, 8),
			randf_range(1.5, 2.5),
			0.8,           # fade_delay — sits on ground before fading
			null,          # no overlay
			0.35,
			true,
			randf_range(-4.0, 4.0)
		)

func spawn_ore_rubble(pos: Vector2, tile_type: Util.tile, ore_type: Util.tile) -> void:
	var base_set:    Array[Texture2D] = _rubble_set_for(tile_type)
	var overlay_set: Array[Texture2D] = _ore_overlay_set_for(ore_type)
	if base_set.is_empty():
		return
	var tex:     Texture2D = base_set[randi() % base_set.size()]
	var overlay: Texture2D = overlay_set[randi() % overlay_set.size()] if not overlay_set.is_empty() else null
	spawn_sprite(
		pos + Vector2(randf_range(-4, 4), randf_range(-4, 4)),
		Vector2(randf_range(-30, 30), randf_range(-50, -20)),
		randf_range(40, 100),
		tex,
		Vector2(10, 10),
		randf_range(2.0, 3.0),
		1.0,
		overlay,
		0.4,
		true,
		randf_range(-3.0, 3.0)
	)

func _rubble_set_for(t: Util.tile) -> Array[Texture2D]:
	match t:
		Util.tile.STONE: return rubble_stone
		Util.tile.ROCK:  return rubble_rock
		_:               return rubble_stone

func _ore_overlay_set_for(t: Util.tile) -> Array[Texture2D]:
	match t:
		Util.tile.GOLD:   return ore_overlay_gold
		Util.tile.COPPER: return ore_overlay_copper
		_:                return []

func _process(delta: float) -> void:
	var alive: Array[Particle] = []
	for p: Particle in particles:
		p.age += delta
		if p.age >= p.lifetime:
			RenderingServer.free_rid(p.canvas_item)
			continue
		alive.append(p)

		# physics
		var next_pos: Vector2 = p.pos + p.vel * delta
		if tilemap_manager != null:
			var map_pos: Vector2i = tilemap_manager.world_to_map(next_pos)
			if tilemap_manager.tile_exists(map_pos):
				var tile_center: Vector2 = tilemap_manager.map_to_world(map_pos)
				var diff: Vector2        = p.pos - tile_center
				if abs(diff.x) > abs(diff.y):
					p.vel.x *= -p.bounce
				else:
					p.vel.y *= -p.bounce
				if p.z <= 0.0:
					p.vel *= 0.7
			else:
				p.pos = next_pos
		else:
			p.pos = next_pos
		if p.use_gravity:
			p.z_vel -= GRAVITY * delta
			p.z     += p.z_vel * delta
			if p.z < 0.0:
				p.z     = 0.0
				p.z_vel = -p.z_vel * p.bounce
				p.vel   *= 0.8
		else:
			p.z += p.z_vel * delta

		# draw
		var t:        float   = p.age / p.lifetime
		var color:    Color   = p.gradient.sample(t)
		color.a               = 1.0 - t
		var draw_pos: Vector2 = p.pos + Vector2(0, -p.z)
		var sort_z:   int     = _sort_z_for(p.pos)
		RenderingServer.canvas_item_set_z_index(p.canvas_item, sort_z)
		RenderingServer.canvas_item_clear(p.canvas_item)
		if p.cast_shadow:
			var shadow_alpha: float = color.a * 0.3 * (1.0 - clampf(p.z / 64.0, 0.0, 1.0))
			RenderingServer.canvas_item_add_rect(
				p.canvas_item,
				Rect2(p.pos, Vector2.ONE),
				Color(0, 0, 0, shadow_alpha)
			)
		RenderingServer.canvas_item_add_rect(
			p.canvas_item,
			Rect2(draw_pos, Vector2.ONE * p.size),
			color
		)
	particles = alive

	for p: SpriteParticle in sprite_particles:
		p.age      += delta
		p.rotation += p.rot_vel * delta
		var next_pos: Vector2 = p.pos + p.vel * delta
		if tilemap_manager != null:
			var map_pos: Vector2i = tilemap_manager.world_to_map(next_pos)
			if tilemap_manager.tile_exists(map_pos):
				var tile_center: Vector2 = tilemap_manager.map_to_world(map_pos)
				var diff: Vector2 = p.pos - tile_center
				if abs(diff.x) > abs(diff.y):
					p.vel.x *= -p.bounce
				else:
					p.vel.y *= -p.bounce
				if p.z <= 0.0:
					p.vel    *= 0.7
					p.rot_vel *= 0.4
			else:
				p.pos = next_pos
		else:
			p.pos = next_pos
		if p.use_gravity:
			p.z_vel -= GRAVITY * delta
			p.z     += p.z_vel * delta
			if p.z < 0.0:
				p.z      = 0.0
				p.z_vel  = -p.z_vel * p.bounce
				p.vel   *= 0.8
				p.rot_vel *= 0.4
		else:
			p.z += p.z_vel * delta
			
	queue_redraw()

func _draw() -> void:
	'''for p: Particle in particles:
		var t: float          = p.age / p.lifetime
		var alpha: float      = 1.0 - t
		var draw_pos: Vector2 = p.pos + Vector2(0, -p.z)
		var color: Color      = p.gradient.sample(t)
		color.a               = alpha
		if p.cast_shadow:
			var shadow_alpha: float = alpha * 0.3 * (1.0 - clampf(p.z / 64.0, 0.0, 1.0))
			draw_rect(Rect2(p.pos, Vector2.ONE), Color(0, 0, 0, shadow_alpha))
		draw_rect(Rect2(draw_pos, Vector2.ONE * p.size), color)'''

	for p: SpriteParticle in sprite_particles:
		if p.texture == null:
			continue
		var alpha: float = 1.0
		if p.age > p.fade_delay:
			alpha = 1.0 - (p.age - p.fade_delay) / (p.lifetime - p.fade_delay)
		alpha = clampf(alpha, 0.0, 1.0)
		var half: Vector2 = p.size / 2.0
		draw_set_transform(p.pos + Vector2(0, -p.z), p.rotation)
		draw_texture_rect(p.texture, Rect2(-half, p.size), false, Color(1, 1, 1, alpha))
		if p.overlay != null:
			draw_texture_rect(p.overlay, Rect2(-half, p.size), false, Color(1, 1, 1, alpha))
		draw_set_transform(Vector2.ZERO)

func _exit_tree() -> void:
	for p: Particle in particles:
		RenderingServer.free_rid(p.canvas_item)
