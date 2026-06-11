# static_field.gd
# ---------------------------------------------------------------------------
# Shared world-state ground patch written by lightning abilities, read by gold.
#
# Lightning abilities call StaticField.spawn() after each enemy hit.
# Gold abilities call StaticField.consume_at() after each crit, which finds
# every field overlapping the hit position, detonates them, and returns the
# total bonus damage so the gold ability can add it to its own hit.
#
# Neither metal references the other in code.
# ---------------------------------------------------------------------------
class_name StaticField
extends Node2D

# ── pool ──────────────────────────────────────────────────────────────────────

const POOL_SIZE:     int   = 64
const POOL_POSITION: Vector2 = Vector2(-99999, -99999)

static var _pool: Array[StaticField] = []

static func prewarm(count: int, parent: Node) -> void:
	for _i in range(count):
		var f := StaticField.new()
		f.global_position = POOL_POSITION
		parent.add_child(f)
		_pool.append(f)

static func _acquire(parent: Node) -> StaticField:
	for f: StaticField in _pool:
		if not f._active:
			return f
	var f := StaticField.new()
	f.global_position = POOL_POSITION
	parent.add_child(f)
	_pool.append(f)
	return f

# ── public API ────────────────────────────────────────────────────────────────

## Spawn a field at world_pos.  base_power is the damage of the lightning hit
## that created this field — stored so the gold explosion scales with lightning
## build strength rather than being a flat value.
static func spawn(world_pos: Vector2, base_power: float, parent: Node) -> void:
	var f: StaticField = _acquire(parent)
	f._activate(world_pos, base_power)

## Called by gold abilities on every crit.  Finds all active fields within
## trigger_radius of world_pos, detonates each one, and returns the summed
## bonus damage.  Pass crit_mult so the explosion scales with the gold build's
## crit damage stat.
static func consume_at(
		world_pos:    Vector2,
		trigger_radius: float,
		crit_mult:    float
) -> float:
	var bonus: float = 0.0
	var r2:    float = trigger_radius * trigger_radius
	for f: StaticField in _pool:
		if not f._active:
			continue
		if f.global_position.distance_squared_to(world_pos) <= r2:
			bonus += f._detonate(crit_mult)
	return bonus

# ── constants ─────────────────────────────────────────────────────────────────

const LIFETIME:       float = 4.0   # seconds before the field fades on its own
const TRIGGER_RADIUS: float = 28.0  # used by consume_at default; gold can pass its own

# crackle visual cadence
const CRACKLE_INTERVAL_MIN: float = 0.15
const CRACKLE_INTERVAL_MAX: float = 0.45

# ── state ─────────────────────────────────────────────────────────────────────

var _active:      bool  = false
var _age:         float = 0.0
var _base_power:  float = 0.0
var _crackle_t:   float = 0.0

# ── lifecycle ─────────────────────────────────────────────────────────────────

func _activate(world_pos: Vector2, base_power: float) -> void:
	global_position = world_pos
	_base_power     = base_power
	_age            = 0.0
	_crackle_t      = randf_range(CRACKLE_INTERVAL_MIN, CRACKLE_INTERVAL_MAX)
	_active         = true
	reset_physics_interpolation()

func _process(delta: float) -> void:
	if not _active:
		return

	_age += delta

	# ambient crackle particles so the player can see fields on the ground
	_crackle_t -= delta
	if _crackle_t <= 0.0:
		_crackle_t = randf_range(CRACKLE_INTERVAL_MIN, CRACKLE_INTERVAL_MAX)
		ParticleManager.spawn_lightning_spark(
			global_position + Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
		)

	# fade alpha as lifetime expires
	modulate.a = clampf(1.0 - (_age / LIFETIME), 0.0, 1.0)

	if _age >= LIFETIME:
		_deactivate()

## Detonate: returns bonus damage = base_power * crit_mult.
## Visual burst is spawned here so every detonation looks the same regardless
## of which gold ability triggered it.
func _detonate(crit_mult: float) -> float:
	if not _active:
		return 0.0
	var bonus: float = _base_power * crit_mult
	# spawn a bigger burst at the field position
	for _i in range(6):
		ParticleManager.spawn_lightning_spark(
			global_position + Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
		)
	_deactivate()
	return bonus

func _deactivate() -> void:
	_active         = false
	modulate.a      = 1.0
	global_position = POOL_POSITION
	reset_physics_interpolation()
