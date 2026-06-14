class_name AbilityStats
extends Resource

# ── core ──────────────────────────────────────────────────────────────────────
@export_group("Core")
@export var damage:           float = -1
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

# ── projectiles ───────────────────────────────────────────────────────────────
@export_group("Projectiles")
@export var projectile_count: int   = -1
@export var chain_length:     int   = -1

# ── critical hits ─────────────────────────────────────────────────────────────
@export_group("Critical Hits")
@export var crit_chance:      float = -1
@export var crit_damage:      float = -1
@export var crit_aoe:         float = -1

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
@export var armor_bonus:      int   = -1
@export var armor_pen:        int   = -1

# ── gold ──────────────────────────────────────────────────────────────────────
# Used by Gold-metal abilities. All default to -1 (unused / not configured).
# Stats that are purely internal constants have been moved to their scripts.
@export_group("Gold")
## Maximum Fortune capacity. Configured by King's Treasury only.
@export var fortune_capacity:         float = -1
## Seconds of inactivity before Fortune starts decaying.
@export var fortune_decay_delay:      float = -1
## Fortune lost per second while decaying.
@export var fortune_decay_rate:       float = -1
## King's Treasury fill threshold (Fortune-charge units to trigger Royal Wealth).
@export var treasury_capacity:        float = -1
## Golden Halo minimum radius (fixed ring size without Fortune).
@export var halo_min_radius:          float = -1
## Golden Halo maximum radius (ring size at max Fortune).
@export var halo_max_radius:          float = -1
## Fortune Engine base stack cap at zero Fortune.
@export var engine_base_stack_cap:    int   = -1
## Rain of Crowns: Fortune-charge threshold to trigger one Crown volley.
@export var crowns_charge_cost:       float = -1
## Rain of Crowns: crater radius left after Crown impact.
@export var crown_crater_radius:      float = -1
## Rain of Crowns: delay between targeting reticle and impact (uses DEFAULT_DROP_DELAY if -1).
@export var crown_drop_delay:         float = -1
## Jackpot Wheel: interval between spins (seconds).
@export var wheel_spin_interval:      float = -1
## Midas Curse: interval between new marks when no mark is active.
@export var curse_mark_interval:      float = -1
## Midas Curse: crit chance increase on marked enemy.
@export var curse_crit_chance_bonus:  float = -1
## Midas Curse: crit damage multiplier increase on marked enemy.
@export var curse_crit_damage_bonus:  float = -1

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
		printerr("[ability_stats.gd] player is null in roll_crit — cannot check guaranteed_crits")
	return randf() < crit_chance

func get_damage(is_crit: bool = false) -> float:
	return damage * (crit_damage if is_crit else 1.0)

func get_aoe(is_crit: bool = false) -> float:
	return aoe_radius + (crit_aoe if is_crit else 0.0)

func get_armor_pen() -> int:
	return maxi(0, armor_pen)

func apply_to_player(player: CharacterBody2D) -> void:
	if move_speed_bonus != 0.0:
		player.speed += move_speed_bonus
	if armor_bonus > 0:
		player.armor += armor_bonus
