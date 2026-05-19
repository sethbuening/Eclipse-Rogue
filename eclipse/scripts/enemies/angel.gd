# angel.gd
class_name E_Angel
extends Enemy

@export var heal_radius:         float     = 120.0
@export var heal_amount_per_sec: float     = 5.0
@export var pylon_orbit_radius:  float     = 60.0
@export var pylon_data:          EnemyData = preload("res://data/enemies/pylon.tres")

var _pylons:       Array[E_Pylon] = []
var _pylons_alive: int            = 0
var _vulnerable:   bool           = false
var _heal_timer:   float          = 0.0

const HEAL_INTERVAL: float = 0.25

# ── lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	super._ready()

func initialize(p: CharacterBody2D, modifier: Util.Modifier = Util.Modifier.NONE) -> void:
	super.initialize(p, modifier)
	_spawn_pylons()

# ── pylons ────────────────────────────────────────────────────────────────────

func _spawn_pylons() -> void:
	for i in 4:
		var pylon: E_Pylon = pylon_data.scene.instantiate() as E_Pylon
		pylon.orbit_radius = pylon_orbit_radius
		pylon.health       = pylon_data.max_health
		add_child(pylon)
		pylon.setup(self, (TAU / 4.0) * i)
		_pylons.append(pylon)
	_pylons_alive = _pylons.size()

func _on_pylon_died(pylon: E_Pylon) -> void:
	_pylons.erase(pylon)
	_pylons_alive -= 1
	if _pylons_alive <= 0:
		_vulnerable = true

# ── process ───────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if player == null:
		return
	z_index = tilemap_manager.get_z_for(global_position)
	_move(delta)
	_tick_healing(delta)

func _move(delta: float) -> void:
	var best_pos:   Vector2 = Vector2.ZERO
	var best_count: int     = 0

	var all_enemies := get_tree().get_nodes_in_group("enemies")
	for candidate in all_enemies:
		if candidate == self or not candidate is Enemy:
			continue
		var count: int = 0
		for other in all_enemies:
			if other == self:
				continue
			if (candidate as Enemy).global_position.distance_to((other as Enemy).global_position) < heal_radius:
				count += 1
		if count > best_count:
			best_count = count
			best_pos   = (candidate as Enemy).global_position

	var target: Vector2 = best_pos if best_count > 0 else player.global_position

	if NavManager._built:
		velocity = _navigator.navigate_toward(target, delta)
	else:
		velocity = (target - global_position).normalized() * data.speed

	velocity += _separation_velocity()
	move_and_slide()

func _tick_healing(delta: float) -> void:
	_heal_timer += delta
	if _heal_timer < HEAL_INTERVAL:
		return
	_heal_timer = 0.0

	var heal: float = heal_amount_per_sec * HEAL_INTERVAL
	for node in get_tree().get_nodes_in_group("enemies"):
		if not node is Enemy:
			continue
		var enemy := node as Enemy
		if global_position.distance_to(enemy.global_position) <= heal_radius:
			enemy.health = mini(enemy.health + int(heal), enemy.data.max_health)

# ── combat ────────────────────────────────────────────────────────────────────

func take_damage(amount: int) -> void:
	if not _vulnerable:
		return
	super.take_damage(amount)

func die() -> void:
	for pylon in _pylons:
		if is_instance_valid(pylon):
			pylon.queue_free()
	super.die()
