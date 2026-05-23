class_name E_Pylon
extends Enemy

var angel:         E_Angel
var _angle:        float = 0.0
var _alive:        bool  = true
var _bob_time:     float = 0.0
var _bob_offset_1: float = 0.0
var _bob_offset_2: float = 0.0
var _bob_offset_3: float = 0.0

# ── lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Deliberately skip super._ready() — pylon has no navigator,
	# no separation area, and health is set by angel.gd via pylon_data.max_health.
	pass

func setup(angel_ref: E_Angel, start_angle: float) -> void:
	angel         = angel_ref
	_angle        = start_angle
	_bob_offset_1 = randf() * TAU
	_bob_offset_2 = randf() * TAU
	_bob_offset_3 = randf() * TAU
	z_index       = 4096
	add_to_group("enemies")

# ── process ───────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not _alive or angel == null:
		return
	_angle  += data.orbit_speed * delta
	position = Vector2(cos(_angle), sin(_angle)) * data.orbit_radius

#func _process(delta: float) -> void:
	#if not _alive:
		#return
	#_bob_time += data.bob_speed * delta
	#if has_node("fracture"):
		#$fracture.position.y  = sin(_bob_time + _bob_offset_1) * data.bob_amplitude
	#if has_node("fracture2"):
		#$fracture2.position.y = sin(_bob_time + _bob_offset_2) * data.bob_amplitude
	#if has_node("fracture3"):
		#$fracture3.position.y = sin(_bob_time + _bob_offset_3) * data.bob_amplitude
	#var line_bob: float = sin(_bob_time + _bob_offset_1) * data.bob_amplitude
	#if has_node("line"):
		#$line.position.y  =  line_bob
	#if has_node("line2"):
		#$line2.position.y = -line_bob

# ── combat ────────────────────────────────────────────────────────────────────

func take_damage(amount: int, is_crit: bool = false) -> void:
	if not _alive:
		return
	var reduced: int = int(amount * (1.0 - data.damage_reduction))
	health -= reduced
	DamageNumbers.spawn(global_position + Vector2(0, -16), reduced, is_crit)
	if health <= 0:
		die()

func die() -> void:
	_alive = false
	emit_signal("died", self)
	queue_free()
