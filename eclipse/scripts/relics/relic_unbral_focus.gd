# relic_umbral_focus.gd
# "Umbral Focus"
# While your health is below 35%, all orbs gain increased potency.
# The bonus is removed the moment your health climbs back to 35% or above.
class_name RelicUmbralFocus
extends RelicData

const HEALTH_THRESHOLD: float = 35.0  # percent (0–100)
const POTENCY_BONUS:    float = 0.4   # +40% orb_potency while bloodied

var _player:      CharacterBody2D = null
var _buff_active: bool            = false

func on_equip(player: CharacterBody2D) -> void:
	_player      = player
	_buff_active = false
	var inventory: Node = player.get_node("Inventory")
	if not inventory.orb_added.is_connected(_on_orb_added):
		inventory.orb_added.connect(_on_orb_added)

func tick(_delta: float, player: CharacterBody2D) -> void:
	if _player == null:
		_player = player
	var health_pct: float = float(player.health) / float(player.max_health) * 100.0
	var bloodied: bool    = health_pct < HEALTH_THRESHOLD
	if bloodied and not _buff_active:
		_apply_buff(player)
	elif not bloodied and _buff_active:
		_remove_buff(player)

# ── buff helpers ──────────────────────────────────────────────────────────────
func _apply_buff(player: CharacterBody2D) -> void:
	_buff_active = true
	for orb: Orb in player.get_node("Inventory").orbs:
		_buff_orb(orb)

func _remove_buff(player: CharacterBody2D) -> void:
	_buff_active = false
	for orb: Orb in player.get_node("Inventory").orbs:
		_unbuff_orb(orb)

func _buff_orb(orb: Orb) -> void:
	orb.orb_potency += POTENCY_BONUS

func _unbuff_orb(orb: Orb) -> void:
	orb.orb_potency -= POTENCY_BONUS

# Called when a new orb is added to inventory while the relic is equipped.
# If the buff is already active the new orb gets it immediately.
func _on_orb_added(orb: Orb) -> void:
	if _buff_active:
		_buff_orb(orb)
