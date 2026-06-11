# gold_crater.gd
# ---------------------------------------------------------------------------
# Persistent ground zone left by a Crown impact.
# Any Gold crit within the crater radius triggers a detonation proportional
# to crown power * crit_mult. Fades after its lifetime.
#
# Does not reference GoldManager — it is triggered externally by
# GoldManager.on_gold_crit() calling GoldCrater.consume_at(), the same
# interface used by StaticField.
# ---------------------------------------------------------------------------
class_name GoldCrater
extends Node2D

const LIFETIME:              float = 5.0
const CRACKLE_INTERVAL_MIN:  float = 0.2
const CRACKLE_INTERVAL_MAX:  float = 0.6

var _active:     bool  = false
var _radius:     float = 72.0
var _base_power: float = 0.0
var _age:        float = 0.0
var _crackle_t:  float = 0.0

static var _all_craters: Array[GoldCrater] = []

func _ready() -> void:
	set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)

func activate(radius: float, base_power: float) -> void:
	_active     = true
	_radius     = radius
	_base_power = base_power
	_age        = 0.0
	_crackle_t  = randf_range(CRACKLE_INTERVAL_MIN, CRACKLE_INTERVAL_MAX)
	reset_physics_interpolation()
	_all_craters.append(self)

func _exit_tree() -> void:
	_all_craters.erase(self)

## Called by on_gold_crit paths — same interface as StaticField.consume_at().
static func consume_at(world_pos: Vector2, trigger_radius: float, crit_mult: float) -> float:
	var total: float = 0.0
	for crater: GoldCrater in _all_craters:
		if not crater._active:
			continue
		var check_r: float = crater._radius + trigger_radius
		if world_pos.distance_squared_to(crater.global_position) <= check_r * check_r:
			total += crater._detonate(crit_mult)
	return total

func _detonate(crit_mult: float) -> float:
	if not _active:
		return 0.0
	var bonus: float = _base_power * crit_mult
	for _i in range(8):
		ParticleManager.spawn_gold_bomb_trail(
			global_position + Vector2(
				randf_range(-_radius * 0.5, _radius * 0.5),
				randf_range(-_radius * 0.5, _radius * 0.5)
			)
		)
	_deactivate()
	return bonus

func _process(delta: float) -> void:
	if not _active:
		return
	_age       += delta
	_crackle_t -= delta
	if _crackle_t <= 0.0:
		_crackle_t = randf_range(CRACKLE_INTERVAL_MIN, CRACKLE_INTERVAL_MAX)
		ParticleManager.spawn_gold_bomb_trail(
			global_position + Vector2(
				randf_range(-_radius * 0.4, _radius * 0.4),
				randf_range(-_radius * 0.4, _radius * 0.4)
			)
		)
	modulate.a = clampf(1.0 - (_age / LIFETIME), 0.0, 1.0)
	if _age >= LIFETIME:
		_deactivate()

func _deactivate() -> void:
	_active    = false
	modulate.a = 1.0
	queue_free()
