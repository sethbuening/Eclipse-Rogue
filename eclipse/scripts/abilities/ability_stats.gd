# ability_stats.gd
class_name AbilityStats
extends Resource

# ── core ──────────────────────────────────────────────────────────────────────
@export var power:            float = 1.0
@export var cooldown:         float = 0.0
@export var duration:         float = 0.0
@export var range:            float = 1.0

# ── speed ─────────────────────────────────────────────────────────────────────
@export var cast_speed:       float = 1.0
@export var projectile_speed: float = 1.0
@export var move_speed_bonus: float = 0.0

# ── area ──────────────────────────────────────────────────────────────────────
@export var aoe_radius:       float = 1.0
@export var pierce:           int   = 0

# ── critical hits ─────────────────────────────────────────────────────────────
@export var crit_chance:      float = 0.0
@export var crit_damage:      float = 2.0
@export var crit_aoe:         float = 0.0

# ── light / resource ──────────────────────────────────────────────────────────
@export var light_cost:       float = 0.0
@export var light_on_hit:     float = 0.0
@export var light_on_crit:    float = 0.0

# ── mining specific ───────────────────────────────────────────────────────────
@export var mining_power:     int   = 1
@export var mining_radius:    int   = 1
@export var ore_yield:        float = 1.0

# ── enemy interaction ─────────────────────────────────────────────────────────
@export var knockback:        float = 0.0
@export var stun_duration:    float = 0.0
@export var slow_amount:      float = 0.0
@export var slow_duration:    float = 0.0
@export var dot_damage:       float = 0.0
@export var dot_duration:     float = 0.0

# ── defensive ─────────────────────────────────────────────────────────────────
@export var damage_absorb:    float = 0.0
@export var reflect_chance:   float = 0.0
@export var shield_amount:    float = 0.0

# ── helpers ───────────────────────────────────────────────────────────────────
func roll_crit() -> bool:
	return randf() < crit_chance

func get_power(is_crit: bool = false) -> float:
	return power * (crit_damage if is_crit else 1.0)

func get_aoe(is_crit: bool = false) -> float:
	return aoe_radius + (crit_aoe if is_crit else 0.0)
