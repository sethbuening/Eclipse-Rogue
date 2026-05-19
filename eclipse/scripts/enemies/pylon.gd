class_name E_Pylon
extends Enemy

@export var orbit_radius:  float = 60.0
@export var orbit_speed:   float = 1.0
@export var bob_amplitude: float = 4.0
@export var bob_speed:     float = 2.0

var angel:         E_Angel
var _angle:        float = 0.0
var _alive:        bool  = true
var _bob_time:     float = 0.0
var _bob_offset_1: float = 0.0
var _bob_offset_2: float = 0.0
var _bob_offset_3: float = 0.0

func _ready() -> void:
	# Deliberately skip super._ready() — pylon has no navigator,
	# no separation area, and health is set by angel.gd via pylon_data.max_health
	pass

func setup(angel_ref: E_Angel, start_angle: float) -> void:
	angel         = angel_ref
	_angle        = start_angle
	_bob_offset_1 = randf() * TAU
	_bob_offset_2 = randf() * TAU
	_bob_offset_3 = randf() * TAU
	z_index       = 4096

func _physics_process(delta: float) -> void:
	if not _alive or angel == null:
		return
	_angle   += orbit_speed * delta
	position  = Vector2(cos(_angle), sin(_angle)) * orbit_radius

func _process(delta: float) -> void:
	if not _alive:
		return
	_bob_time += bob_speed * delta
	if has_node("fracture"):
		$fracture.position.y  = sin(_bob_time + _bob_offset_1) * bob_amplitude
	if has_node("fracture2"):
		$fracture2.position.y = sin(_bob_time + _bob_offset_2) * bob_amplitude
	if has_node("fracture3"):
		$fracture3.position.y = sin(_bob_time + _bob_offset_3) * bob_amplitude
	var line_bob: float = sin(_bob_time + _bob_offset_1) * bob_amplitude
	if has_node("line"):
		$line.position.y  =  line_bob
	if has_node("line2"):
		$line2.position.y = -line_bob

func take_damage(amount: int) -> void:
	if not _alive:
		return
	health -= amount
	if health <= 0:
		die()

func die() -> void:
	_alive = false
	if is_instance_valid(angel):
		angel._on_pylon_died(self)
	queue_free()
