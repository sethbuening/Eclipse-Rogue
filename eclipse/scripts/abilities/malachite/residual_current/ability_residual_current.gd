# ability_residual_current.gd
# ---------------------------------------------------------------------------
# Passive ability — does not fire on its own.
# Listens to EnemyManager.enemy_died.  When a dying enemy has the meta flag
# "lightning_kill" set by a lightning ability before calling take_damage(),
# places a ResidualCorpse at the death position.
#
# The corpse behaves like a short-lived single-fire Conductor Post: it chains
# to the next enemy that walks within range, dealing reduced damage, then
# clears itself.
#
# Hard synergies (inbound — emergent from shared kill flag)
#   ← Thunderclap      : kills in a ring → ring of corpses simultaneously.
#   ← LightningJavelin : kills along a line → corridor of corpses.
#
# Soft synergy (StaticField / Gold metal)
#   The corpse's single chain shock calls StaticField.spawn() at the shocked
#   enemy's position, extending the field layer into corners and edges that
#   direct abilities never aimed at.
# ---------------------------------------------------------------------------
class_name AbilityResidualCurrent
extends AbilityData

const ResidualCorpseScene := preload("res://scenes/abilities/residual_corpse.tscn")

# Cap on simultaneous active corpses to prevent runaway density in thin rooms.
const MAX_ACTIVE_CORPSES: int = 12

var _connected: bool = false

func tick(context: Dictionary) -> void:
	super.tick(context)
	# Connect to the death signal once, on first tick.
	if not _connected:
		_connected = true
		if not EnemyManager.enemy_died.is_connected(_on_enemy_died):
			EnemyManager.enemy_died.connect(_on_enemy_died)

	# No cooldown logic — this ability fires only via the signal.
	# Drive orb glow when corpses are active so the player can see the passive.
	var active: int = ResidualCorpse.active_count
	context["orb_t"] = clampf(float(active) / float(MAX_ACTIVE_CORPSES), 0.0, 1.0)

func _on_enemy_died(enemy: Enemy) -> void:
	if not enemy.has_meta("lightning_kill"):
		return
	# Don't exceed the corpse cap.
	if ResidualCorpse.active_count >= MAX_ACTIVE_CORPSES:
		return

	# We need the parent scene to add the corpse to; find it via EnemyManager.
	var parent: Node = EnemyManager.get_parent() if EnemyManager != null else null
	if parent == null:
		return

	var corpse := ResidualCorpseScene.instantiate() as ResidualCorpse
	parent.add_child(corpse)
	corpse.global_position = enemy.global_position
	corpse.setup(stats, _orb_potency, main_stats)
