# ability_stats.gd
class_name AbilityStats
extends Resource

# ── core ──────────────────────────────────────────────────────────────────────
@export_group("Core")
@export var power:            float = -1
@export var cooldown:         float = -1
@export var duration:         float = -1
@export var range:            float = -1

# ── speed ─────────────────────────────────────────────────────────────────────
@export_group("Speed")
@export var cast_speed:       float = -1
@export var projectile_speed: float = -1
@export var move_speed_bonus: float = -1

# ── area ──────────────────────────────────────────────────────────────────────
@export_group("Area")
@export var aoe_radius:       float = -1
@export var pierce:           int   = -1

# ── critical hits ─────────────────────────────────────────────────────────────
@export_group("Critical Hits")
@export var crit_chance:      float = -1
@export var crit_damage:      float = -1
@export var crit_aoe:         float = -1

# ── light / resource ──────────────────────────────────────────────────────────
@export_group("Light")
@export var light_cost:       float = -1
@export var light_on_hit:     float = -1
@export var light_on_crit:    float = -1

# ── mining ────────────────────────────────────────────────────────────────────
@export_group("Mining")
@export var mining_power:     int   = -1
@export var mining_radius:    int   = -1
@export var ore_yield:        float = -1

# ── enemy interaction ─────────────────────────────────────────────────────────
@export_group("Enemy Interaction")
@export var knockback:        float = -1
@export var stun_duration:    float = -1
@export var slow_amount:      float = -1
@export var slow_duration:    float = -1
@export var dot_damage:       float = -1
@export var dot_duration:     float = -1

# ── defensive ─────────────────────────────────────────────────────────────────
@export_group("Defensive")
@export var damage_absorb:    float = -1
@export var reflect_chance:   float = -1
@export var shield_amount:    float = -1
@export var armor_bonus:      int   = -1   # flat armor added to the player
@export var armor_pen:        int   = -1   # flat armor ignored on enemy hits

# ── helpers ───────────────────────────────────────────────────────────────────
func get_stat(stat_name: String, orb_potency: float = 1.0, main_stats: Array[String] = []) -> float:
	var base: float = get(stat_name)
	if stat_name in main_stats:
		return base * orb_potency
	return base

func roll_crit(player: CharacterBody2D = null) -> bool:
	if player != null and player.guaranteed_crits > 0:
		player.guaranteed_crits -= 1
		return true
	if player == null:
		printerr("[ability_stats.gd] player is null in function roll_crit! Cannot check for guaranteed crits!")
	return randf() < crit_chance

func get_power(is_crit: bool = false) -> float:
	return power * (crit_damage if is_crit else 1.0)

func get_aoe(is_crit: bool = false) -> float:
	return aoe_radius + (crit_aoe if is_crit else 0.0)

func get_armor_pen() -> int:
	return maxi(0, armor_pen)

func apply_to_player(player: CharacterBody2D) -> void:
	if light_on_hit != 0.0:
		player.light += light_on_hit
	if move_speed_bonus != 0.0:
		player.speed += move_speed_bonus
	if armor_bonus > 0:
		player.armor += armor_bonus
