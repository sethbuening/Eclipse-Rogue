# ball_lightning.gd
# ---------------------------------------------------------------------------
# Drifting orb that pulses damage to nearby enemies as it moves.
# Participates in two hard synergies and one soft synergy — see ability file.
# ---------------------------------------------------------------------------
class_name BallLightning
extends Node2D

# ── BallLightning is a valid chain hop target — this static list lets
#    Targeting.nearest_chain_target() find live orbs the same way it finds
#    ConductorPost.all_posts.
static var all_balls: Array[BallLightning] = []

const PULSE_INTERVAL: float = 0.25   # seconds between damage pulses
const CHAIN_BOOST_SCALE:  float = 2.0   # pulse power multiplier after a chain hop
const CHAIN_BOOST_PULSES: int   = 3    # how many boosted pulses fire after a chain hop
const POST_SNAP_CHECK_INTERVAL: float = 0.1  # how often to check for nearby posts

var _stats:       AbilityStats
var _orb_potency: float
var _main_stats:  Array[String]

var _lifetime:      float
var _age:           float  = 0.0
var _pulse_timer:   float  = 0.0
var _post_check_t:  float  = 0.0
var _direction:     Vector2 = Vector2.RIGHT

# Chain boost state
var _boost_pulses_left: int   = 0

# Post snap state — set externally by ConductorPost.notify_ball_nearby()
var _snapped:           bool  = false
var _snap_scale:        float = 1.0

func _ready() -> void:
	set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)
	all_balls.append(self)

func _exit_tree() -> void:
	all_balls.erase(self)

func setup(
	stats:       AbilityStats,
	orb_potency: float,
	main_stats:  Array[String]
) -> void:
	_stats       = stats
	_orb_potency = orb_potency
	_main_stats  = main_stats
	_lifetime    = _stats.get_stat("duration", _orb_potency, _main_stats)
	if _lifetime <= 0.0:
		_lifetime = 5.0

	# Pick initial direction toward nearest enemy, or a random direction.
	var nearest: Enemy = _nearest_enemy()
	if nearest != null:
		_direction = (nearest.global_position - global_position).normalized()
	else:
		_direction = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()

	reset_physics_interpolation()

func _process(delta: float) -> void:
	_age += delta
	if _age >= _lifetime:
		queue_free()
		return

	# Fade out in the final 20% of lifetime.
	var fade_start: float = _lifetime * 0.8
	if _age >= fade_start:
		modulate.a = 1.0 - (_age - fade_start) / (_lifetime - fade_start)

	# While snapped to a post, stay still — the post handles the pulse.
	if _snapped:
		return

	# Drift
	var speed: float = _stats.get_stat("projectile_speed", _orb_potency, _main_stats)
	if speed <= 0.0:
		speed = 60.0
	global_position += _direction * speed * delta

	# Gently re-aim toward nearest enemy to avoid drifting into walls forever,
	# but don't home sharply — the drift feel is intentional.
	var nearest: Enemy = _nearest_enemy()
	if nearest != null:
		var desired: Vector2 = (nearest.global_position - global_position).normalized()
		_direction = _direction.lerp(desired, 0.04).normalized()

	# Post snap check
	_post_check_t -= delta
	if _post_check_t <= 0.0:
		_post_check_t = POST_SNAP_CHECK_INTERVAL
		_check_post_snap()

	# Pulse damage
	_pulse_timer += delta
	if _pulse_timer >= PULSE_INTERVAL:
		_pulse_timer = 0.0
		_pulse()

# ── synergy API ───────────────────────────────────────────────────────────────

## Called by LightningChain when it hops through this orb.
## Triggers a burst of amplified pulses at the orb's current position.
func receive_chain_boost() -> void:
	_boost_pulses_left = CHAIN_BOOST_PULSES
	# Fire the first boosted pulse immediately.
	_pulse(CHAIN_BOOST_SCALE)

## Called by ConductorPost when it accepts the snap.
func snap_to_post(post_position: Vector2) -> void:
	_snapped      = true
	global_position = post_position
	reset_physics_interpolation()

## Called by ConductorPost when snap duration expires, or on post death.
func release_from_post() -> void:
	_snapped = false
	# After release, re-aim toward nearest enemy.
	var nearest: Enemy = _nearest_enemy()
	if nearest != null:
		_direction = (nearest.global_position - global_position).normalized()

# ── internal ──────────────────────────────────────────────────────────────────

func _check_post_snap() -> void:
	var post: ConductorPost = ConductorPost.nearest_in_range(
		global_position, ConductorPost.BALL_SNAP_RADIUS
	)
	if post != null:
		var accepted: bool = post.notify_ball_nearby(self)
		if accepted:
			snap_to_post(post.global_position)

func _pulse(power_scale: float = 1.0) -> void:
	# Apply boost scale from a recent chain hop if any pulses remain.
	if _boost_pulses_left > 0:
		_boost_pulses_left -= 1
		power_scale = maxf(power_scale, CHAIN_BOOST_SCALE)

	var radius:    float = _stats.get_stat("aoe_radius", _orb_potency, _main_stats)
	if radius <= 0.0:
		radius = 48.0
	var radius_sq: float = radius * radius
	var power:     float = _stats.get_stat("power", _orb_potency, _main_stats) * power_scale

	for enemy: Enemy in EnemyManager.living_enemies:
		if not is_instance_valid(enemy):
			continue
		if global_position.distance_squared_to(enemy.global_position) > radius_sq:
			continue

		var is_crit: bool  = _stats.roll_crit(null)
		var damage:  float = power * (_stats.crit_damage if is_crit else 1.0)
		enemy.take_damage(int(damage), _stats.get_armor_pen(), is_crit, Util.DamageType.LIGHTNING)
		RelicOvercharged.add_stack(enemy)
		if _stats.slow_amount > 0.0:
			enemy.apply_slow(_stats.slow_amount, _stats.slow_duration)
		ParticleManager.spawn_lightning_spark(enemy.global_position)

		# Soft synergy: StaticField — gold crits can detonate these.
		StaticField.spawn(enemy.global_position, power, get_parent())

	ParticleManager.spawn_lightning_spark(global_position)

func _nearest_enemy() -> Enemy:
	var best_d: float = INF
	var best:   Enemy = null
	for enemy: Enemy in EnemyManager.living_enemies:
		if not is_instance_valid(enemy):
			continue
		var d: float = global_position.distance_squared_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best   = enemy
	return best
