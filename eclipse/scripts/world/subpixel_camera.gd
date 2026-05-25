extends Camera2D

## Smooth top-down camera that follows a target node, with trauma-based screen shake.

@export var target:       Node2D
@export var follow_speed: float = 10.0

# Increase SHAKE_MAX_OFFSET until it feels right in your zoom level.
# At zoom=1 with 32px tiles, 5–8px is subtle; 12–20px is Vampire Survivors-level punch.
const SHAKE_DECAY:      float = 7.0   # trauma lost per second
const SHAKE_MAX_OFFSET: float = 16.0  # max pixel offset at full trauma — was 3.0, too small
const SHAKE_MAX_ROLL:   float = 0.008 # max rotation in radians at full trauma

var _trauma:  float = 0.0
var _shake_t: float = 0.0

## Call this to add shake. trauma is 0–1; values stack (clamped to 1.0).
## Mining hit = 0.2, tile death = 0.45, explosion = 0.8+
func shake(trauma: float) -> void:
	_trauma = minf(_trauma + trauma, 1.0)

func _ready() -> void:
	if target == null:
		target = %Player
	if target:
		global_position = target.global_position

func _physics_process(delta: float) -> void:
	if target == null:
		return

	# Follow — always writes to global_position only.
	var t := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(target.global_position, t)
	if global_position.distance_to(target.global_position) < 0.25:
		global_position = target.global_position

	# Shake — writes only to offset + rotation, never global_position.
	if _trauma > 0.0:
		_trauma  = maxf(0.0, _trauma - SHAKE_DECAY * delta)
		_shake_t += delta * 45.0
		var s    := _trauma * _trauma  # square = punchy at high values, subtle at low
		offset    = Vector2(
			SHAKE_MAX_OFFSET * s * _noise(_shake_t),
			SHAKE_MAX_OFFSET * s * _noise(_shake_t + 100.0)
		)
		rotation  = SHAKE_MAX_ROLL * s * _noise(_shake_t + 200.0)
	else:
		offset   = Vector2.ZERO
		rotation = 0.0

func _noise(x: float) -> float:
	return sin(x * 1.7) * 0.5 + sin(x * 3.1) * 0.3 + sin(x * 5.3) * 0.2
