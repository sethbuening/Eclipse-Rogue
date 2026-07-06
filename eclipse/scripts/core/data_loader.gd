# DataLoader.gd
# ---------------------------------------------------------------------------
# Loads ability and enemy stats from JSON files exported from Excel/Google Sheets.
# Add this as an autoload (singleton) named "DataLoader" in Project Settings.
#
# JSON format: { "Sheet Name": { "0": {row}, "1": {row}, ... } }
# Each row has "Ability Name", "Ability Level" ("Base" or "Level N"), and stat keys.
# ---------------------------------------------------------------------------
extends Node

const ABILITIES_JSON_PATH: String = "res://data/json/Deepvein.json"
const ENEMIES_JSON_PATH:   String = "res://data/json/enemies.json"
const RELICS_JSON_PATH:    String = "res://data/json/relics.json"

var _ability_map:      Dictionary = {}  # "Ability Name" -> Array[Dictionary] (ordered by level)
var _enemy_map:        Dictionary = {}
var _relic_map:        Dictionary = {}  # "Relic Name" -> Array[Dictionary] (ordered by level)
var _loaded_abilities: bool       = false
var _loaded_enemies:   bool       = false
var _loaded_relics:    bool       = false

const INT_STATS: Array[String] = [
	"pierce", "projectile_count", "chain_length", "mining_power",
	"mining_radius", "armor_bonus", "armor_pen", "engine_base_stack_cap",
	"cost"
]

# Human-readable labels for stat deltas shown on upgrade cards.
const STAT_LABELS: Dictionary = {
	"damage":            "Damage",
	"cooldown":         "Cooldown",
	"duration":         "Duration",
	"range":            "Range",
	"cast_speed":       "Cast Speed",
	"projectile_speed": "Projectile Speed",
	"move_speed_bonus": "Move Speed",
	"aoe_radius":       "AoE Radius",
	"pierce":           "Pierce",
	"projectile_count": "Projectile Count",
	"chain_length":     "Chain Length",
	"crit_chance":      "Crit Chance",
	"crit_damage":      "Crit Damage",
	"crit_aoe":         "Crit AoE",
	"mining_power":     "Mining Power",
	"mining_radius":    "Mining Radius",
	"ore_yield":        "Ore Yield",
	"knockback":        "Knockback",
	"stun_duration":    "Stun Duration",
	"slow_amount":      "Slow",
	"slow_duration":    "Slow Duration",
	"dot_damage":       "DoT Damage",
	"dot_duration":     "DoT Duration",
	"damage_absorb":    "Damage Absorb",
	"reflect_chance":   "Reflect Chance",
	"shield_amount":    "Shield",
	"armor_bonus":      "Armor",
	"armor_pen":        "Armor Pen",
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Apply base stats and build upgrade_levels for [ability] from Deepvein.json.
func apply_ability_data(ability: AbilityData) -> void:
	_ensure_abilities_loaded()
	if _ability_map.is_empty():
		return

	var sheet_key: String = _find_matching_sheet_key(ability.id)
	if sheet_key.is_empty():
		push_warning("DataLoader: no sheet data for ability id '%s'" % ability.id)
		return

	var rows: Array = _ability_map[sheet_key]

	# Separate base row from upgrade rows.
	var base_row: Dictionary               = {}
	var upgrade_rows: Array[Dictionary]    = []

	for row: Dictionary in rows:
		var lvl: String = str(row.get("Ability Level", "Base")).strip_edges().to_lower()
		if lvl == "base":
			base_row = row
		elif lvl.begins_with("level"):
			upgrade_rows.append(row)

	# Sort upgrade rows by their level number.
	upgrade_rows.sort_custom(func(a, b):
		return _parse_level_number(str(a.get("Ability Level", "Level 0"))) \
			 < _parse_level_number(str(b.get("Ability Level", "Level 0")))
	)

	# ── Base stats ────────────────────────────────────────────────────────────
	if not base_row.is_empty():
		for key: String in base_row.keys():
			if key in ["Ability Name", "Ability Level"]:
				continue
			var raw = base_row[key]
			var parsed: float = _try_parse_float(raw)
			if is_nan(parsed):
				continue  # skip non-numeric values like "规律"
			if key in ability.stats:
				ability.stats.set(key, int(parsed) if key in INT_STATS else parsed)

	# ── Upgrade levels ────────────────────────────────────────────────────────
	ability.upgrade_levels.clear()

	for i in range(upgrade_rows.size()):
		var row: Dictionary = upgrade_rows[i]
		var level_after: int = i + 1  # level the ability reaches after taking this upgrade

		var entry := AbilityUpgradeEntry.new()
		entry.display_name = "%s Level %d" % [ability.display_name, level_after]

		# Collect stat deltas, skipping non-numeric and metadata columns.
		# "cost" is excluded here — it's the ability's static ore cost, read
		# once from the base row, not a per-level combat stat delta.
		var deltas: Dictionary = {}
		for key: String in row.keys():
			if key in ["Ability Name", "Ability Level", "cost"]:
				continue
			var raw = row[key]
			var parsed: float = _try_parse_float(raw)
			if is_nan(parsed):
				continue
			if key in ability.stats:
				deltas[key] = parsed

		# Build description from deltas.
		entry.description = _build_delta_description(deltas)

		# Apply deltas to all rarity tiers (no per-rarity scaling in this sheet format).
		entry.stat_deltas_common    = deltas.duplicate()
		entry.stat_deltas_uncommon  = deltas.duplicate()
		entry.stat_deltas_rare      = deltas.duplicate()
		entry.stat_deltas_epic      = deltas.duplicate()
		entry.stat_deltas_legendary = deltas.duplicate()

		ability.upgrade_levels.append(entry)


## Apply base stats and build upgrade_levels for [relic] from relics.json.
## The JSON format mirrors Deepvein.json: rows keyed by "Relic Name" and
## "Relic Level" ("Base" or "Level N"), with numeric stat columns.
func apply_relic_data(relic: RelicData) -> void:
	_ensure_relics_loaded()
	if _relic_map.is_empty():
		return

	var sheet_key: String = _find_matching_relic_key(relic.id)
	if sheet_key.is_empty():
		push_warning("DataLoader: no sheet data for relic id '%s'" % relic.id)
		return

	var rows: Array = _relic_map[sheet_key]

	var base_row: Dictionary            = {}
	var upgrade_rows: Array[Dictionary] = []

	for row: Dictionary in rows:
		var lvl: String = str(row.get("Relic Level", "Base")).strip_edges().to_lower()
		if lvl == "base":
			base_row = row
		elif lvl.begins_with("level"):
			upgrade_rows.append(row)

	upgrade_rows.sort_custom(func(a, b):
		return _parse_level_number(str(a.get("Relic Level", "Level 0"))) \
			 < _parse_level_number(str(b.get("Relic Level", "Level 0")))
	)

	# ── Base stats ────────────────────────────────────────────────────────────
	if not base_row.is_empty():
		for key: String in base_row.keys():
			if key in ["Relic Name", "Relic Level"]:
				continue
			var raw = base_row[key]
			var parsed: float = _try_parse_float(raw)
			if is_nan(parsed):
				continue
			if key in relic:
				relic.set(key, parsed)

	# ── Upgrade levels ────────────────────────────────────────────────────────
	relic.upgrade_levels.clear()

	for i in range(upgrade_rows.size()):
		var row: Dictionary  = upgrade_rows[i]
		var level_after: int = i + 1

		var entry := RelicUpgradeEntry.new()
		entry.display_name = "%s Level %d" % [relic.display_name, level_after]

		var deltas: Dictionary = {}
		for key: String in row.keys():
			if key in ["Relic Name", "Relic Level"]:
				continue
			var raw = row[key]
			var parsed: float = _try_parse_float(raw)
			if is_nan(parsed):
				continue
			if key in relic:
				deltas[key] = parsed

		entry.description = _build_delta_description(deltas)
		entry.stat_deltas_common    = deltas.duplicate()
		entry.stat_deltas_uncommon  = deltas.duplicate()
		entry.stat_deltas_rare      = deltas.duplicate()
		entry.stat_deltas_epic      = deltas.duplicate()
		entry.stat_deltas_legendary = deltas.duplicate()

		relic.upgrade_levels.append(entry)


## Apply base stats to [enemy_data] from enemies.json.
func apply_enemy_data(enemy: EnemyData) -> void:
	_ensure_enemies_loaded()
	if _enemy_map.is_empty():
		return
	var id: String = enemy.id
	if not id in _enemy_map:
		return
	var row: Dictionary = _enemy_map[id]
	for key: String in row:
		if key == "id":
			continue
		if not key in enemy:
			push_warning("DataLoader: enemy '%s' unknown column '%s'" % [id, key])
			continue
		var raw = row[key]
		var current = enemy.get(key)
		if typeof(current) == TYPE_BOOL:
			enemy.set(key, _truthy(raw))
		elif typeof(current) == TYPE_INT:
			enemy.set(key, int(raw))
		elif typeof(current) == TYPE_FLOAT:
			enemy.set(key, float(raw))
		else:
			enemy.set(key, raw)

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _ensure_abilities_loaded() -> void:
	if _loaded_abilities:
		return
	_loaded_abilities = true

	var raw = _load_json(ABILITIES_JSON_PATH)
	if raw == null:
		return

	# The JSON has one top-level sheet key; grab whichever dict is inside it.
	var sheet_data: Dictionary = {}
	if raw is Dictionary:
		if raw.size() == 1:
			# Single sheet wrapper — unwrap it.
			var inner = raw[raw.keys()[0]]
			if inner is Dictionary:
				sheet_data = inner
			else:
				push_error("DataLoader: unexpected JSON structure in abilities file.")
				return
		else:
			sheet_data = raw
	else:
		push_error("DataLoader: abilities JSON must be a Dictionary.")
		return

	# sheet_data is now { "0": {row}, "1": {row}, ... }
	_ability_map.clear()
	for row_key: String in sheet_data.keys():
		var element = sheet_data[row_key]
		if not element is Dictionary:
			continue
		var name_key: String = str(element.get("Ability Name", ""))
		if name_key.is_empty():
			continue
		if not _ability_map.has(name_key):
			_ability_map[name_key] = []
		_ability_map[name_key].append(element)

func _ensure_enemies_loaded() -> void:
	if _loaded_enemies:
		return
	_loaded_enemies = true
	var raw = _load_json(ENEMIES_JSON_PATH)
	if not raw is Array:
		push_error("DataLoader: enemies.json must be a JSON array.")
		return
	for row: Dictionary in raw:
		var id: String = str(row.get("id", ""))
		if id != "":
			_enemy_map[id] = row

func _ensure_relics_loaded() -> void:
	if _loaded_relics:
		return
	_loaded_relics = true

	var raw = _load_json(RELICS_JSON_PATH)
	if raw == null:
		return

	var sheet_data: Dictionary = {}
	if raw is Dictionary:
		if raw.size() == 1:
			var inner = raw[raw.keys()[0]]
			if inner is Dictionary:
				sheet_data = inner
			else:
				push_error("DataLoader: unexpected JSON structure in relics file.")
				return
		else:
			sheet_data = raw
	else:
		push_error("DataLoader: relics JSON must be a Dictionary.")
		return

	_relic_map.clear()
	for row_key: String in sheet_data.keys():
		var element = sheet_data[row_key]
		if not element is Dictionary:
			continue
		var name_key: String = str(element.get("Relic Name", ""))
		if name_key.is_empty():
			continue
		if not _relic_map.has(name_key):
			_relic_map[name_key] = []
		_relic_map[name_key].append(element)

static func _load_json(path: String):
	if not FileAccess.file_exists(path):
		push_error("DataLoader: file not found: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DataLoader: could not open: %s" % path)
		return null
	var result = JSON.parse_string(file.get_as_text())
	file.close()
	if result == null:
		push_error("DataLoader: JSON parse error in: %s" % path)
	return result

func _find_matching_sheet_key(resource_id: String) -> String:
	var target: String = resource_id.replace("_", " ").to_lower().strip_edges()
	for key: String in _ability_map.keys():
		if key.to_lower().strip_edges() == target:
			return key
	return ""

func _find_matching_relic_key(resource_id: String) -> String:
	var target: String = resource_id.replace("_", " ").to_lower().strip_edges()
	for key: String in _relic_map.keys():
		if key.to_lower().strip_edges() == target:
			return key
	return ""

func _parse_level_number(lvl_str: String) -> int:
	return int(lvl_str.to_lower().replace("level", "").strip_edges())

## Returns NAN if the value is non-numeric (e.g. a Chinese string placeholder).
func _try_parse_float(val) -> float:
	if val is float: return val
	if val is int:   return float(val)
	if val is String:
		var s: String = val.replace("+", "").strip_edges()
		if s.is_valid_float() or s.is_valid_int():
			return s.to_float()
	return NAN

## Builds a human-readable description from a stat delta dictionary.
func _build_delta_description(deltas: Dictionary) -> String:
	if deltas.is_empty():
		return ""
	var parts: Array[String] = []
	for key: String in deltas.keys():
		var val: float = deltas[key]
		var label: String = STAT_LABELS.get(key, key.replace("_", " ").capitalize())
		var sign: String  = "+" if val >= 0 else ""
		# Show integers cleanly, floats with up to 2 decimal places.
		var val_str: String
		if float(int(val)) == val:
			val_str = "%s%d" % [sign, int(val)]
		else:
			val_str = "%s%.2f" % [sign, val]
			# Trim trailing zeros after decimal point.
			if "." in val_str:
				val_str = val_str.rstrip("0").rstrip(".")
		parts.append("%s: %s" % [label, val_str])
	return "\n".join(parts)

static func _truthy(v) -> bool:
	if v is bool:   return v
	if v is int:    return v != 0
	if v is float:  return v != 0.0
	if v is String: return v.to_lower() in ["true", "yes", "1"]
	return false

func invalidate_cache() -> void:
	_ability_map      = {}
	_enemy_map        = {}
	_relic_map        = {}
	_loaded_abilities = false
	_loaded_enemies   = false
	_loaded_relics    = false

func get_all_abilities() -> Array[AbilityData]:
	_ensure_abilities_loaded()
	var results: Array[AbilityData] = []
	for key: String in _ability_map.keys():
		var a := AbilityData.new()
		a.id           = key.to_lower().replace(" ", "_")
		a.display_name = key
		apply_ability_data(a)
		results.append(a)
	return results
