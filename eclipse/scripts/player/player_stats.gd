# player_stats.gd
class_name PlayerStats
extends Resource

# ── movement ──────────────────────────────────────────────────────────────────
@export_group("Movement")
@export var speed:            float = 75.0  # pixels per second (scaled at runtime)
@export var mine_speed:  float = 1.35

# ── health ────────────────────────────────────────────────────────────────────
@export_group("Health")
@export var max_health:       int   = 100

# ── defence ───────────────────────────────────────────────────────────────────
@export_group("Defence")
@export var armor:            int   = 0
@export var dodge_chance:     float = 0.0    # 0.0–1.0; chance to fully negate an attack

# ── crits ─────────────────────────────────────────────────────────────────────
@export_group("Crits")
@export var guaranteed_crits: int   = 0      # next N attacks auto-crit

# ── relics ────────────────────────────────────────────────────────────────────
@export_group("Relics")
## Maximum number of orbs the player can hold at once.
@export var orb_max: int = 2

## Maximum number of relics the player can hold at once.
@export var relic_max: int = 2

# ── luck ──────────────────────────────────────────────────────────────────────
@export_group("Luck")
## Controls rarity weighting during level-up upgrade rolls.
## Each point adds LUCK_WEIGHT_BONUS (see UpgradeRarityTable) to every
## non-Common rarity tier. Starts at 0 (no bonus). Can be granted by relics,
## upgrades, or other systems.
@export var luck:             float = 0.0


# ── ability stat modifiers ────────────────────────────────────────────────────
# These are written to by relics (and any future system) when picked up.
# Because PlayerStats is instanced fresh each run, they reset automatically.
#
# Formula applied in apply_ability_modifiers():
#   final = (base + flat) * (1.0 + mult)
#
# flat — added to the raw stat value before multiplying.
# mult — stacks additively; 0.2 means +20%, -0.1 means -10%.
# All default to 0.0 (neutral — no effect on stats that return -1 as "unused").
@export_group("Ability Stat Modifiers")
@export var damage_flat:              float = 0.0
@export var damage_mult:              float = 0.0
@export var cooldown_flat:           float = 0.0
@export var cooldown_mult:           float = 0.0
@export var duration_flat:           float = 0.0
@export var duration_mult:           float = 0.0
@export var range_flat:              float = 0.0
@export var range_mult:              float = 0.0
@export var cast_speed_flat:         float = 0.0
@export var cast_speed_mult:         float = 0.0
@export var projectile_speed_flat:   float = 0.0
@export var projectile_speed_mult:   float = 0.0
@export var move_speed_bonus_flat:   float = 0.0
@export var move_speed_bonus_mult:   float = 0.0
@export var aoe_radius_flat:         float = 0.0
@export var aoe_radius_mult:         float = 0.0
@export var pierce_flat:             float = 0.0
@export var pierce_mult:             float = 0.0
@export var projectile_count_flat:   float = 0.0
@export var projectile_count_mult:   float = 0.0
@export var chain_length_flat:       float = 0.0
@export var chain_length_mult:       float = 0.0
@export var crit_chance_flat:        float = 0.0
@export var crit_chance_mult:        float = 0.0
@export var crit_damage_flat:        float = 0.0
@export var crit_damage_mult:        float = 0.0
@export var crit_aoe_flat:           float = 0.0
@export var crit_aoe_mult:           float = 0.0
@export var mining_power_flat:       float = 0.0
@export var mining_power_mult:       float = 0.0
@export var mining_radius_flat:      float = 0.0
@export var mining_radius_mult:      float = 0.0
@export var ore_yield_flat:          float = 0.0
@export var ore_yield_mult:          float = 0.0
@export var knockback_flat:          float = 0.0
@export var knockback_mult:          float = 0.0
@export var stun_duration_flat:      float = 0.0
@export var stun_duration_mult:      float = 0.0
@export var slow_amount_flat:        float = 0.0
@export var slow_amount_mult:        float = 0.0
@export var slow_duration_flat:      float = 0.0
@export var slow_duration_mult:      float = 0.0
@export var dot_damage_flat:         float = 0.0
@export var dot_damage_mult:         float = 0.0
@export var dot_duration_flat:       float = 0.0
@export var dot_duration_mult:       float = 0.0
@export var damage_absorb_flat:      float = 0.0
@export var damage_absorb_mult:      float = 0.0
@export var reflect_chance_flat:     float = 0.0
@export var reflect_chance_mult:     float = 0.0
@export var shield_amount_flat:      float = 0.0
@export var shield_amount_mult:      float = 0.0
@export var armor_bonus_flat:        float = 0.0
@export var armor_bonus_mult:        float = 0.0
@export var armor_pen_flat:          float = 0.0
@export var armor_pen_mult:          float = 0.0

## Apply this PlayerStats' modifiers to [base], a value already read from
## AbilityStats for [stat_name].  Returns base unchanged if no modifiers exist
## for that stat (i.e. both _flat and _mult are 0.0).
func apply_ability_modifiers(stat_name: String, base: float) -> float:
	var flat: float = get(stat_name + "_flat")
	var mult: float = get(stat_name + "_mult")
	# If the property doesn't exist on this resource, get() returns null.
	if flat == null: flat = 0.0
	if mult == null: mult = 0.0
	if flat == 0.0 and mult == 0.0:
		return base
	return (base + flat) * (1.0 + mult)
