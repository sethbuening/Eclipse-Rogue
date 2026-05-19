# ability_stats.gd
class_name AbilityStats
extends Resource

# ── core ──────────────────────────────────────────────────────────────────────
@export_group("Core")
@export var power:            float = 1.0
@export var cooldown:         float = 0.0
@export var duration:         float = 0.0
@export var range:            float = 1.0

# ── speed ─────────────────────────────────────────────────────────────────────
@export_group("Speed")
@export var cast_speed:       float = 1.0
@export var projectile_speed: float = 1.0
@export var move_speed_bonus: float = 0.0

# ── area ──────────────────────────────────────────────────────────────────────
@export_group("Area")
@export var aoe_radius:       float = 1.0
@export var pierce:           int   = 0

# ── critical hits ─────────────────────────────────────────────────────────────
@export_group("Critical Hits")
@export var crit_chance:      float = 0.0
@export var crit_damage:      float = 2.0
@export var crit_aoe:         float = 0.0

# ── light / resource ──────────────────────────────────────────────────────────
@export_group("Light")
@export var light_cost:       float = 0.0
@export var light_on_hit:     float = 0.0
@export var light_on_crit:    float = 0.0

# ── mining ────────────────────────────────────────────────────────────────────
@export_group("Mining")
@export var mining_power:     int   = 1
@export var mining_radius:    int   = 1
@export var ore_yield:        float = 1.0

# ── enemy interaction ─────────────────────────────────────────────────────────
@export_group("Enemy Interaction")
@export var knockback:        float = 0.0
@export var stun_duration:    float = 0.0
@export var slow_amount:      float = 0.0
@export var slow_duration:    float = 0.0
@export var dot_damage:       float = 0.0
@export var dot_duration:     float = 0.0

# ── defensive ─────────────────────────────────────────────────────────────────
@export_group("Defensive")
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

func apply_to_player(player: CharacterBody2D) -> void:
	if light_on_hit != 0.0:
		player.light += light_on_hit
	if move_speed_bonus != 0.0:
		player.speed += move_speed_bonus
