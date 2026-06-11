class_name AbilityTooltip
extends Tooltip

const FONT_SIZE_TITLE:  int   = 16
const FONT_SIZE_NORMAL: int   = 13
const FONT_SIZE_SMALL:  int   = 11
const MAX_WIDTH:        float = 260.0

const C_BORDER:  Color = Color(0.55, 0.35, 0.80, 0.7)
const C_TITLE:   Color = Color(0.80, 0.60, 1.00)
const C_TEXT:    Color = Color(0.90, 0.90, 0.90)
const C_SUBTEXT: Color = Color(0.60, 0.65, 0.72)
const C_VALUE:   Color = Color(0.45, 0.85, 0.65)

# since all current stats have a default of -1 this dictionary is empty for now
const STAT_DEFAULTS: Dictionary = {
}

const STAT_UNITS: Dictionary = {
	"power": "", "cooldown": " sec", "duration": " sec", "range": " tiles",
	"cast_speed": "", "projectile_speed": " px/s", "move_speed_bonus": " px/s",
	"aoe_radius": " tiles", "pierce": "", "crit_chance": " %", "crit_damage": "x",
	"crit_aoe": " tiles",
	"mining_power": "", "mining_radius": " tiles", "ore_yield": "x",
	"knockback": "", "stun_duration": " sec", "slow_amount": " %",
	"slow_duration": " sec", "dot_damage": "", "dot_duration": " sec",
	"damage_absorb": "", "reflect_chance": " %", "shield_amount": "",
}

# Stats that are stored in px and should be displayed divided by 32 (tile size).
const STAT_DIVIDE_BY_TILE: Array = ["range", "aoe_radius", "crit_aoe"]

# Shared formatter used by ability_tooltip, orb_tooltip, and forge_ui.
# Returns a display string with trailing zeros stripped and unit appended.
static func fmt_stat_value(val: Variant, unit: String, key: String = "") -> String:
	var display: String
	var v = val
	if key in STAT_DIVIDE_BY_TILE and v is float:
		v = v / 32.0
	elif key in STAT_DIVIDE_BY_TILE and v is int:
		v = float(v) / 32.0
	if v is float:
		if unit == " %":
			display = "%.0f%%" % (v * 100.0)
			return display
		else:
			display = "%.2f" % v
			if "." in display:
				display = display.rstrip("0").rstrip(".")
	elif v is int:
		display = str(v)
	else:
		return ""
	return display + unit

func _make_style() -> StyleBoxFlat:
	var style              := StyleBoxFlat.new()
	style.bg_color          = Color(0.06, 0.07, 0.10, 1.0)
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_width_top    = 2
	style.border_width_bottom = 2
	style.border_color      = C_BORDER
	for i in 4: style.set_corner_radius(i, 6)
	style.content_margin_left   = PAD
	style.content_margin_right  = PAD
	style.content_margin_top    = PAD
	style.content_margin_bottom = PAD
	return style

func _build_content(data: Object) -> void:
	var ability: AbilityData = data as AbilityData
	if ability == null:
		return

	var aname: String = ability.display_name if "display_name" in ability else ability.get_class()
	_vbox.add_child(_make_label(aname, FONT_SIZE_TITLE, C_TITLE))

	if "trigger_type" in ability:
		_vbox.add_child(_make_label(_trigger_label(ability.trigger_type), FONT_SIZE_SMALL, C_SUBTEXT))

	if "description" in ability and ability.description != "":
		_vbox.add_child(_make_sep(C_BORDER))
		var desc := _make_label(ability.description, FONT_SIZE_NORMAL, C_TEXT)
		desc.autowrap_mode       = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(MAX_WIDTH - PAD * 2, 0)
		_vbox.add_child(desc)

	if ability.stats != null:
		var rows: Array = _collect_stat_rows(ability.stats)
		if not rows.is_empty():
			_vbox.add_child(_make_sep(C_BORDER))
			for row in rows:
				_vbox.add_child(row)

func _collect_stat_rows(stats: AbilityStats) -> Array:
	var rows: Array = []
	for prop in stats.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var key: String = prop["name"]
		var val         = stats.get(key)
		var default     = STAT_DEFAULTS.get(key, -1)
		if val == default:
			continue
		var unit:    String = STAT_UNITS.get(key, "")
		var display: String = fmt_stat_value(val, unit, key)
		if display == "":
			continue
		rows.append(_make_stat_row(key.replace("_", " ").capitalize(), display))
	return rows

func _make_stat_row(label_text: String, value_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	var lbl := _make_label(label_text, FONT_SIZE_NORMAL, C_SUBTEXT)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := _make_label(value_text, FONT_SIZE_NORMAL, C_VALUE)
	row.add_child(lbl)
	row.add_child(val)
	return row

func _trigger_label(trigger_type) -> String:
	match trigger_type:
		0: return "Active"
		1: return "Passive"
		2: return "On hold"
		_: return ""
