# projectile_manager.gd
# Autoload — add to Project Settings as "ProjectileManager"

extends Node

const DRAW_RADIUS:  float = 3.0
const FLASH_LIFE:   float = 0.06
const COLOR_NORMAL: Color = Color(0.898, 0.895, 0.902, 1.0)
const COLOR_CRIT:   Color = Color(0.999, 0.408, 0.0, 1.0)

# Bullet explosion constants
const EXPLOSION_LIFE:       float = 0.12
const EXPLOSION_RADIUS_MAX: float = 10.0

var _projectiles: Array = []
var _flashes:     Array = []
var _explosions:  Array = []
var _canvas:      Node2D

# ── setup ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_canvas = Node2D.new()
	_canvas.name    = "ProjectileManagerCanvas"
	_canvas.z_index = 100
	_canvas.draw.connect(_on_canvas_draw)
	get_tree().root.call_deferred("add_child", _canvas)

# ── public API ────────────────────────────────────────────────────────────────

func spawn_toward_enemy(
		origin:    Vector2,
		target:    Enemy,
		damage:    int,
		armor_pen: int      = 0,
		speed:     float    = 300.0,
		is_crit:   bool     = false,
		pierce:    int      = 0,
		max_range: float    = 600.0,
		radius:    float    = DRAW_RADIUS,
		on_hit:    Callable = Callable()
) -> void:
	if not is_instance_valid(target):
		return
	var dir: Vector2 = (target.global_position - origin).normalized()
	_add(origin, dir, damage, armor_pen, speed, is_crit, pierce, max_range, radius, on_hit)

func spawn_in_direction(
		origin:    Vector2,
		direction: Vector2,
		damage:    int,
		armor_pen: int      = 0,
		speed:     float    = 300.0,
		is_crit:   bool     = false,
		pierce:    int      = 0,
		max_range: float    = 600.0,
		radius:    float    = DRAW_RADIUS,
		on_hit:    Callable = Callable()
) -> void:
	_add(origin, direction.normalized(), damage, armor_pen, speed, is_crit, pierce, max_range, radius, on_hit)

# ── internal ──────────────────────────────────────────────────────────────────

func _add(
		origin:    Vector2,
		dir:       Vector2,
		damage:    int,
		armor_pen: int,
		speed:     float,
		is_crit:   bool,
		pierce:    int,
		max_range: float,
		radius:    float,
		on_hit:    Callable
) -> void:
	_projectiles.append({
		"pos":       origin,
		"vel":       dir * speed,
		"damage":    damage,
		"armor_pen": armor_pen,
		"is_crit":   is_crit,
		"pierce":    pierce,
		"range":     max_range,
		"travelled": 0.0,
		"radius":    radius,
		"color":     COLOR_CRIT if is_crit else COLOR_NORMAL,
		"hit_ids":   [],
		"on_hit":    on_hit,
	})

func _process(delta: float) -> void:
	_tick_projectiles(delta)
	_tick_flashes(delta)
	_tick_explosions(delta)
	if _canvas:
		_canvas.queue_redraw()

func _tick_projectiles(delta: float) -> void:
	if _projectiles.is_empty():
		return

	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var alive:   Array = []

	for p in _projectiles:
		var step: Vector2 = p["vel"] * delta
		p["pos"]       += step
		p["travelled"] += step.length()

		if p["travelled"] >= p["range"]:
			continue

		var hit_this_frame: bool = false
		for node in enemies:
			if not is_instance_valid(node):
				continue
			var id: int = node.get_instance_id()
			if id in p["hit_ids"]:
				continue
			var dist_sq: float   = p["pos"].distance_squared_to(node.global_position)
			var threshold: float = p["radius"] + 8.0
			if dist_sq <= threshold * threshold:
				node.take_damage(p["damage"], p["armor_pen"], p["is_crit"])
				_spawn_flash(p["pos"], p["color"])
				p["hit_ids"].append(id)
				if p["on_hit"].is_valid():
					p["on_hit"].call(node)
				if p["pierce"] <= 0:
					hit_this_frame = true
					break
				else:
					p["pierce"] -= 1

		if not hit_this_frame:
			alive.append(p)

	_projectiles = alive

func _tick_flashes(delta: float) -> void:
	var alive: Array = []
	for f in _flashes:
		f["life"] -= delta
		if f["life"] > 0.0:
			alive.append(f)
	_flashes = alive

func _tick_explosions(delta: float) -> void:
	var alive: Array = []
	for e in _explosions:
		e["life"] -= delta
		if e["life"] > 0.0:
			alive.append(e)
	_explosions = alive

func _spawn_flash(pos: Vector2, color: Color) -> void:
	_flashes.append({ "pos": pos, "life": FLASH_LIFE, "max_life": FLASH_LIFE, "color": color })

# Called by AbilityBasicAttack when a bullet hits its final target (pierce exhausted)
func _spawn_bullet_explosion(pos: Vector2, color: Color) -> void:
	_explosions.append({
		"pos":      pos,
		"life":     EXPLOSION_LIFE,
		"max_life": EXPLOSION_LIFE,
		"color":    color,
	})

# ── drawing ───────────────────────────────────────────────────────────────────

func _on_canvas_draw() -> void:
	var xform: Transform2D = _canvas.get_global_transform().affine_inverse()

	# Generic (non-basic-attack) projectiles — still drawn as circles
	for p in _projectiles:
		_canvas.draw_circle(xform * p["pos"], p["radius"], p["color"])

	# Impact flashes
	for f in _flashes:
		var t:     float = f["life"] / f["max_life"]
		var color: Color = Color(f["color"].r, f["color"].g, f["color"].b, t)
		_canvas.draw_circle(xform * f["pos"], DRAW_RADIUS * (1.0 + (1.0 - t) * 2.0), color)

	# Bullet final-hit explosions — bright expanding ring
	for e in _explosions:
		var t:      float = e["life"] / e["max_life"]
		var radius: float = EXPLOSION_RADIUS_MAX * (1.0 - t)
		var alpha:  float = t
		# Outer ring
		var ring_col: Color = Color(e["color"].r, e["color"].g, e["color"].b, alpha * 0.7)
		_canvas.draw_arc(xform * e["pos"], radius, 0.0, TAU, 12, ring_col, 1.5, true)
		# Bright core flash
		var core_col: Color = Color(1.0, 1.0, 1.0, alpha)
		_canvas.draw_circle(xform * e["pos"], maxf(0.5, radius * 0.3), core_col)

	# Draw bullet streaks from basic attack abilities
	for node in get_tree().get_nodes_in_group("player"):
		for attack in node.basic_attacks:
			attack.draw_projectiles(_canvas)
