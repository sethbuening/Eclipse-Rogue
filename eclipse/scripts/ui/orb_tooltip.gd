class_name OrbTooltip
extends Tooltip

const FONT_SIZE_TITLE:  int   = 17
const FONT_SIZE_NORMAL: int   = 14
const FONT_SIZE_SMALL:  int   = 12
const MAX_WIDTH:        float = 280.0

const C_BORDER:  Color = Color(0.95, 0.78, 0.35, 0.6)
const C_TITLE:   Color = Color(0.95, 0.78, 0.35)
const C_TEXT:    Color = Color(0.90, 0.90, 0.90)
const C_SUBTEXT: Color = Color(0.60, 0.65, 0.72)
const C_POTENCY: Color = Color(0.45, 0.90, 0.55)

var _ability_tooltip: AbilityTooltip = null

func _ready():
	super._ready()
	z_index = 4095

func set_ability_tooltip(t: AbilityTooltip) -> void:
	_ability_tooltip = t
	_ability_tooltip._on_hidden_callback = func() -> void:
		_evaluate_hide()

## Provide the graph manager so the tooltip can resolve node boosts.
func set_graph_context(_gm: Node) -> void:
	pass  # node graph removed; kept for call-site compatibility

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
	var orb: Orb = data as Orb
	if orb == null:
		return

	var title := _make_label(orb.display_name, FONT_SIZE_TITLE, C_TITLE)
	title.autowrap_mode       = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(MAX_WIDTH - PAD * 2, 0)
	_vbox.add_child(title)

	_vbox.add_child(_make_stat_row("Potency",  AbilityTooltip.fmt_stat_value(orb.orb_potency, "") if "orb_potency" in orb else "—"))
	_vbox.add_child(_make_stat_row("Cooldown", AbilityTooltip.fmt_stat_value(orb.cooldown, " sec") if orb.cooldown > 0.0 else "—"))

	# Show ability slot usage so players can see capacity even at 1/1.
	if "ability_max" in orb:
		_vbox.add_child(_make_stat_row("Ability Slots", "%d / %d" % [orb.abilities.size(), orb.ability_max]))

	if not orb.abilities.is_empty():
		_vbox.add_child(_make_sep(C_BORDER))
		_vbox.add_child(_make_label("Abilities", FONT_SIZE_SMALL, C_SUBTEXT))

		for ability: AbilityData in orb.abilities:
			var aname: String = ability.display_name \
				if "display_name" in ability else ability.get_class()
			if "level" in ability and ability.level > 0:
				aname += " (Lv.%d)" % ability.level
			var a_lbl := _make_label("• " + aname, FONT_SIZE_NORMAL + 3, C_TEXT)
			a_lbl.autowrap_mode       = TextServer.AUTOWRAP_WORD_SMART
			a_lbl.custom_minimum_size = Vector2(MAX_WIDTH - PAD * 2, 24)
			a_lbl.mouse_filter        = Control.MOUSE_FILTER_PASS
			var ability_ref: AbilityData = ability
			a_lbl.mouse_entered.connect(func() -> void:
				if _ability_tooltip != null:
					_ability_tooltip.request_show(ability_ref,
						get_viewport().get_mouse_position()))
			a_lbl.mouse_exited.connect(func() -> void:
				if _ability_tooltip != null:
					_ability_tooltip.request_hide())
			_vbox.add_child(a_lbl)

func _evaluate_hide() -> void:
	if _mouse_on_src or _mouse_on_tip:
		return
	if _ability_tooltip != null and _ability_tooltip.visible:
		return
	if _hide_timer != null:
		return
	_hide_timer = get_tree().create_timer(HIDE_DELAY)
	_hide_timer.timeout.connect(func() -> void:
		_hide_timer = null
		if _mouse_on_src or _mouse_on_tip:
			return
		if _ability_tooltip != null and _ability_tooltip.visible:
			return
		hide()
	)

func _make_stat_row(label_text: String, value_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	var lbl := _make_label(label_text, FONT_SIZE_NORMAL, C_SUBTEXT)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := _make_label(value_text, FONT_SIZE_NORMAL, C_POTENCY)
	row.add_child(lbl)
	row.add_child(val)
	return row

func _open(data: Object, at_global: Vector2) -> void:
	await super._open(data, at_global)
	# _ignore_mouse wiped the ability label filters — restore them.
	for child in _vbox.get_children():
		if child is Label and child.mouse_entered.get_connections().size() > 0:
			child.mouse_filter = Control.MOUSE_FILTER_PASS
