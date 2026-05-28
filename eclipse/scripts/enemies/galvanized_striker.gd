# galvanized_striker.gd
class_name E_GalvanizedStriker
extends Enemy

enum Phase { IDLE, CHARGING, CHARGED, SLAMMING, COOLDOWN }

const CHARGE_TIME:    float = 3.0
const CHARGED_TIME:   float = 2.0
const SLAM_RANGE:     float = 40.0
const SLAM_RADIUS:    float = 80.0
const SLAM_STUN:      float = 1.5
const SLAM_DAMAGE:    int   = 8
const COOLDOWN_TIME:  float = 4.0

var _phase:     Phase = Phase.IDLE
var _phase_t:   float = 0.0

func _tick_behavior(delta: float) -> void:
	_phase_t += delta
	match _phase:
		Phase.IDLE:
			if _phase_t >= 2.0:   # short idle before next charge
				_set_phase(Phase.CHARGING)
		Phase.CHARGING:
			if _phase_t >= CHARGE_TIME:
				_set_phase(Phase.CHARGED)
		Phase.CHARGED:
			var dist: float = global_position.distance_to(player.global_position)
			if dist <= SLAM_RANGE:
				_set_phase(Phase.SLAMMING)
			elif _phase_t >= CHARGED_TIME:
				_set_phase(Phase.IDLE)  # missed, give up
		Phase.SLAMMING:
			_do_slam()
			_set_phase(Phase.COOLDOWN)
		Phase.COOLDOWN:
			if _phase_t >= COOLDOWN_TIME:
				_set_phase(Phase.IDLE)

func _set_phase(p: Phase) -> void:
	_phase   = p
	_phase_t = 0.0
	# TODO: trigger visual change here (modulate color, emit particles, etc.)

func _do_slam() -> void:
	# Damage + stun player if in radius
	var dist: float = global_position.distance_to(player.global_position)
	if dist <= SLAM_RADIUS:
		player.light -= SLAM_DAMAGE
		player.apply_stun(SLAM_STUN)   # add apply_stun() to player if not present
	ParticleManager.spawn_gold_bomb_trail(global_position)  # reuse or replace with slam VFX
