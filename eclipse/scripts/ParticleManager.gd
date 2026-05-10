extends Node2D

class Particle:
	var pos: Vector2
	var vel: Vector2
	var z: float
	var z_vel: float
	var bounce: float
	var lifetime: float
	var age: float
	var gradient: Gradient
	var cast_shadow: bool
	var size: float

const GRAVITY: float = 400.0
var particles: Array[Particle] = []
var tilemap_manager: Node = null

func _ready() -> void:
	z_index = 1

func spawn(pos: Vector2, vel: Vector2, z_vel: float, gradient: Gradient, lifetime: float, size: float = 3.0, bounce: float = 0.4, cast_shadow: bool = true) -> void:
	var p := Particle.new()
	p.pos         = pos
	p.vel         = vel
	p.z           = 0.0
	p.z_vel       = z_vel
	p.bounce      = bounce
	p.lifetime    = lifetime
	p.age         = 0.0
	p.gradient    = gradient
	p.cast_shadow = cast_shadow
	p.size        = size
	particles.append(p)

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
			randf_range(2.0, 4.0),
			0.35,
			false
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
			true
		)

func spawn_footstep_dust(pos: Vector2) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.6, 0.55, 0.5, 0.6))
	gradient.set_color(1, Color(0.6, 0.55, 0.5, 0.0))
	for i: int in range(randi_range(1, 3)):
		spawn(
			pos,
			Vector2(randf_range(-20, 20), randf_range(-10, 0)),
			randf_range(10, 40),
			gradient,
			randf_range(0.2, 0.4),
			randf_range(1.5, 3.0),
			0.1,
			false
		)

func _process(delta: float) -> void:
	for p: Particle in particles:
		p.age += delta

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
				# if on the ground, also kill some vertical energy on wall hit
				if p.z <= 0.0:
					p.vel   *= 0.7
			else:
				p.pos = next_pos
		else:
			p.pos = next_pos

		p.z_vel -= GRAVITY * delta
		p.z     += p.z_vel * delta
		if p.z < 0.0:
			p.z     = 0.0
			p.z_vel = -p.z_vel * p.bounce
			p.vel   *= 0.8

	particles = particles.filter(func(p: Particle) -> bool: return p.age < p.lifetime)
	queue_redraw()

func _draw() -> void:
	for p: Particle in particles:
		var t: float          = p.age / p.lifetime
		var alpha: float      = 1.0 - t
		var draw_pos: Vector2 = p.pos + Vector2(0, -p.z)
		var color: Color      = p.gradient.sample(t)
		color.a               = alpha
		if p.cast_shadow:
			var shadow_alpha: float = alpha * 0.3 * (1.0 - clampf(p.z / 64.0, 0.0, 1.0))
			draw_rect(Rect2(p.pos, Vector2.ONE), Color(0, 0, 0, shadow_alpha))
		draw_rect(Rect2(draw_pos, Vector2.ONE * 2), color)
