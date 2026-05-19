# enemy_data.gd
class_name EnemyData
extends Resource

# ── identity ──────────────────────────────────────────────────────────────────
@export var id:           String     = "grunt"
@export var display_name: String     = "Grunt"
@export var scene:        PackedScene

# ── wave spawning ─────────────────────────────────────────────────────────────
@export var cost:         int        = 1
@export var min_wave:     int        = 1

# ── stats ─────────────────────────────────────────────────────────────────────
@export var max_health:   int        = 3
@export var speed:        float      = 60.0
@export var damage:       int        = 1

# ── healing (for Angel and similar) ──────────────────────────────────────────
@export var heals_allies:        bool  = false
@export var heal_radius:         float = 120.0
@export var heal_amount_per_sec: float = 0.0

# ── pylon / summoning ─────────────────────────────────────────────────────────s
@export var spawns_units:               bool      = false
@export var spawned_unit_data:          EnemyData = null   # e.g. angel → pylon data
@export var spawn_count:                int       = 0      # how many to spawn

# ── resistances ───────────────────────────────────────────────────────────────
@export var damage_reduction: float = 0.0   # 0.0 = none, 1.0 = immune
@export var knockback_resistance: float = 0.0

# ── reward ────────────────────────────────────────────────────────────────────
@export var xp_value:    int = 1
@export var loot_table:  Array[String] = []  # item/drop IDs
