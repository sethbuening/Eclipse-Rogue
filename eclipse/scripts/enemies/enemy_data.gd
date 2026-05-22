class_name EnemyData
extends Resource

@export_group("Identity")
@export var id:           String      = "grunt"
@export var display_name: String      = "Grunt"
@export var scene:        PackedScene

@export_group("Wave Spawning")
@export var cost:         int         = 1
@export var min_wave:     int         = 1

@export_group("Core Stats")
@export var max_health:   int         = 3
@export var speed:        float       = 60.0

@export_group("Attack")
@export var damage:           int     = 1
@export var attack_range:     float   = 16.0
@export var attack_cooldown:  float   = 1.0
@export var projectile_speed: float   = 0.0
@export var crit_chance: float = 0.0
@export var crit_damage_mult: float = 3.0

@export_group("Separation")
@export var sep_radius: float         = 64.0
@export var sep_force:  float         = 1.0
@export var preferred_range: float    = 32.0

@export_group("Resistances")
@export var damage_reduction:     float = 0.0
@export var knockback_resistance: float = 0.0
@export var stun_resistance:      float = 0.0
@export var slow_resistance:      float = 0.0
@export var dot_resistance:       float = 0.0

@export_subgroup("Elemental")
@export var fire_resistance:      float = 0.0
@export var ice_resistance:       float = 0.0
@export var lightning_resistance: float = 0.0
@export var poison_resistance:    float = 0.0

@export_group("Healing")
@export var heals_allies:        bool  = false
@export var heal_radius:         float = 120.0
@export var heal_amount_per_sec: float = 0.0
@export var heal_interval:       float = 0.25

@export_group("Buff Aura")
@export var buff_radius:          float = 0.0
@export var buff_interval:        float = 2
@export var buff_pulse_interval: float = 1.5

@export_subgroup("Buff Multipliers")
@export var buff_speed_mult:      float = 1.0
@export var buff_damage_mult:     float = 1.0
@export var buff_cooldown_mult:   float = 1.0
@export var buff_sep_force_mult:  float = 1.0

@export_subgroup("Buff Resistances")
@export var buff_stun_resistance: float = 0.0
@export var buff_slow_resistance: float = 0.0

@export_group("Buff Immunity")
@export var buff_immune:          bool  = false

@export_group("Summoning")
@export var spawns_units:         bool      = false
@export var spawned_unit_data:    EnemyData = null
@export var spawn_count:          int       = 0
@export var spawned_orbit_radius: float     = 60.0

@export_group("Orbital")
@export var orbit_radius:         float = 60.0
@export var orbit_speed:          float = 1.0
@export var bob_amplitude:        float = 4.0
@export var bob_speed:            float = 2.0

@export_group("Reward")
@export var xp_value:             int           = 1
@export var loot_table:           Array[String] = []
