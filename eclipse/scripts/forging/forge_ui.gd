# forge_ui.gd
extends CanvasLayer

# ── references ────────────────────────────────────────────────────────────────
var player: Node2D = null
var forge:  Forge  = null

# ── state ─────────────────────────────────────────────────────────────────────
var staged_orbs:   Array[Orb]  = []
var staged_metals: Dictionary  = {}   # MetalData → int
var result_name_input: LineEdit = null

# Forge-result interactive selection state
var _pending_result: ForgeResult = null
var _chosen_ability: AbilityData = null
var _stat_picks_remaining: int   = 0

# ── sizing ────────────────────────────────────────────────────────────────────
var ui_scale: float = 1.0

# ── built nodes ───────────────────────────────────────────────────────────────
var root_panel:          PanelContainer  = null
var input_screen:        Control         = null
var forging_screen:      Control         = null
var complete_screen:     Control         = null
var ability_pick_screen: Control         = null
var stat_pick_screen:    Control         = null

var orb_inventory_list:  VBoxContainer   = null
var metal_inventory_list:VBoxContainer   = null
var staged_list:         VBoxContainer   = null

var orb_inv_scroll:   ScrollContainer = null
var metal_inv_scroll: ScrollContainer = null
var staged_scroll:    ScrollContainer = null

var heat_label:          Label           = null
var preview_label:       Label           = null
var _info_box:           VBoxContainer   = null
var activate_button:     Button          = null
var cancel_button:       Button          = null

var progress_bar:        ProgressBar     = null
var forging_heat_label:  Label           = null
var forging_wave_label:  Label           = null
var _stall_label:        Label           = null

var result_name_label:   Label           = null
var result_ability_list: VBoxContainer   = null
var result_stat_list:    VBoxContainer   = null
var collect_button:      Button          = null

var dim_overlay: ColorRect = null

var _tooltip: OrbTooltip = null
var _ability_tooltip: AbilityTooltip = null

# Ability pick screen
var _ability_pick_cards: HBoxContainer = null
var _ability_pick_title: Label         = null

# Stat pick screen
var _stat_pick_cards:     HBoxContainer = null
var _stat_pick_title:     Label         = null
var _stat_picks_label:    Label         = null

# ── controller navigation ─────────────────────────────────────────────────────
enum ForgePanel { ORB_INV, METAL_INV, STAGED, BUTTONS }

var _ctrl_panel:       ForgePanel  = ForgePanel.ORB_INV
var _ctrl_index:       int         = 0
var _ctrl_btn:         int         = 0
var _stick_was_active: Dictionary  = {}
const _STICK_DEAD:     float       = 0.4

# ── theme constants ───────────────────────────────────────────────────────────
const FONT_SIZE_LARGE:  int     = 24
const FONT_SIZE_NORMAL: int     = 18
const FONT_SIZE_SMALL:  int     = 15
const COL_GAP:          int     = 32
const ROW_GAP:          int     = 12
const CARD_PAD:         int     = 12
const SCROLL_MIN_H:     float   = 220.0
const BTN_MIN:          Vector2 = Vector2(140, 52)
const ICON_SIZE:        Vector2 = Vector2(36, 36)

const C_BG:        Color = Color(0.10, 0.11, 0.15)
const C_PANEL:     Color = Color(0.14, 0.16, 0.21)
const C_SECTION:   Color = Color(0.17, 0.20, 0.27)
const C_BTN:       Color = Color(0.20, 0.25, 0.38)
const C_BTN_HOVER: Color = Color(0.30, 0.42, 0.62)
const C_BTN_DOWN:  Color = Color(0.42, 0.58, 0.82)
const C_ACCENT:    Color = Color(0.95, 0.78, 0.35)
const C_TEXT:      Color = Color(0.92, 0.92, 0.92)
const C_SUBTEXT:   Color = Color(0.60, 0.65, 0.72)
const C_DANGER:    Color = Color(0.85, 0.30, 0.25)

# ── ready ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_build_ui()
	_apply_scale()

# ── scale ─────────────────────────────────────────────────────────────────────
func set_ui_scale(s: float) -> void:
	ui_scale = s
	if is_inside_tree() and root_panel != null:
		_apply_scale()

func _apply_scale() -> void:
	await get_tree().process_frame
	root_panel.pivot_offset = root_panel.size / 2.0
	root_panel.scale        = Vector2(ui_scale, ui_scale)

# ── style helpers ─────────────────────────────────────────────────────────────
func _make_panel_style(color: Color, radius: int = 8) -> StyleBoxFlat:
	var s          := StyleBoxFlat.new()
	s.bg_color      = color
	for i in 4:
		s.set_corner_radius(i, radius)
	return s

func _make_btn_style(color: Color, radius: int = 6) -> StyleBoxFlat:
	var s := _make_panel_style(color, radius)
	s.content_margin_left   = 18
	s.content_margin_right  = 18
	s.content_margin_top    = 10
	s.content_margin_bottom = 10
	return s

func _make_margin(top: int = CARD_PAD, right: int = CARD_PAD,
		bottom: int = CARD_PAD, left: int = CARD_PAD) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top",    top)
	m.add_theme_constant_override("margin_right",  right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.add_theme_constant_override("margin_left",   left)
	return m

func _make_label(text: String, size: int = FONT_SIZE_NORMAL,
		color: Color = C_TEXT) -> Label:
	var l  := Label.new()
	l.text  = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _make_button(text: String, danger: bool = false) -> Button:
	var b  := Button.new()
	b.text  = text
	b.custom_minimum_size = BTN_MIN
	b.add_theme_font_size_override("font_size", FONT_SIZE_NORMAL)
	var base: Color = C_DANGER if danger else C_BTN
	b.add_theme_stylebox_override("normal",   _make_btn_style(base))
	b.add_theme_stylebox_override("hover",    _make_btn_style(C_BTN_HOVER if not danger else C_DANGER.lightened(0.15)))
	b.add_theme_stylebox_override("pressed",  _make_btn_style(C_BTN_DOWN))
	b.add_theme_stylebox_override("disabled", _make_btn_style(C_BTN.darkened(0.4)))
	b.add_theme_color_override("font_color",          C_TEXT)
	b.add_theme_color_override("font_disabled_color", C_SUBTEXT)
	b.focus_mode = Control.FOCUS_NONE
	return b

func _make_icon_rect(texture: Texture2D) -> TextureRect:
	var t              := TextureRect.new()
	t.texture           = texture
	t.custom_minimum_size = ICON_SIZE
	t.expand_mode       = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	t.stretch_mode      = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return t

func _make_section(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var header := _make_label(title, FONT_SIZE_LARGE, C_ACCENT)
	box.add_child(header)
	var sep        := HSeparator.new()
	sep.add_theme_color_override("color", C_ACCENT.darkened(0.4))
	box.add_child(sep)
	return box

func _make_scroll(content: Control, min_h: float = SCROLL_MIN_H) -> ScrollContainer:
	var scroll                    := ScrollContainer.new()
	scroll.custom_minimum_size     = Vector2(0, min_h)
	scroll.size_flags_vertical     = Control.SIZE_SHRINK_BEGIN
	scroll.horizontal_scroll_mode  = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(content)
	content.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	return scroll

func _make_scroll_row(row: Control) -> MarginContainer:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_bottom", 4)
	wrap.add_child(row)
	return wrap

# ── UI construction ───────────────────────────────────────────────────────────
func _build_ui() -> void:
	dim_overlay              = ColorRect.new()
	dim_overlay.color        = Color(0, 0, 0, 0.55)
	dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim_overlay)

	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	root_panel = PanelContainer.new()
	root_panel.add_theme_stylebox_override("panel", _make_panel_style(C_BG, 10))
	root_panel.custom_minimum_size = Vector2(1050, 740)
	root_panel.anchor_left   = 0.5
	root_panel.anchor_right  = 0.5
	root_panel.anchor_top    = 0.5
	root_panel.anchor_bottom = 0.5
	root_panel.offset_left   = -525
	root_panel.offset_right  =  525
	root_panel.offset_top    = -370
	root_panel.offset_bottom =  370
	anchor.add_child(root_panel)

	var outer_margin := _make_margin(24, 24, 24, 24)
	outer_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_panel.add_child(outer_margin)

	var screens_stack := Control.new()
	screens_stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer_margin.add_child(screens_stack)

	input_screen        = _build_input_screen()
	complete_screen     = _build_complete_screen()
	ability_pick_screen = _build_ability_pick_screen()
	stat_pick_screen    = _build_stat_pick_screen()

	for screen: Control in [input_screen, complete_screen,
			ability_pick_screen, stat_pick_screen]:
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		screens_stack.add_child(screen)

	forging_screen = _build_forging_screen()
	var forging_anchor := Control.new()
	forging_anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	forging_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(forging_anchor)
	forging_anchor.add_child(forging_screen)
	forging_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	input_screen.hide()
	forging_screen.hide()
	complete_screen.hide()
	ability_pick_screen.hide()
	stat_pick_screen.hide()

	_tooltip = OrbTooltip.new()
	add_child(_tooltip)
	_ability_tooltip = AbilityTooltip.new()
	add_child(_ability_tooltip)
	_tooltip.set_ability_tooltip(_ability_tooltip)

# ── input screen ──────────────────────────────────────────────────────────────
func _build_input_screen() -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", ROW_GAP)

	var title := _make_label("FORGE", FONT_SIZE_LARGE + 6, C_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", COL_GAP)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	var inv_col_wrap := Control.new()
	inv_col_wrap.custom_minimum_size   = Vector2(450, 0)
	inv_col_wrap.size_flags_horizontal = Control.SIZE_FILL
	inv_col_wrap.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	inv_col_wrap.clip_contents         = true
	columns.add_child(inv_col_wrap)

	var inv_col := VBoxContainer.new()
	inv_col.add_theme_constant_override("separation", ROW_GAP)
	inv_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_col.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	inv_col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inv_col_wrap.add_child(inv_col)

	var orb_section := _make_section("Inventory — Orbs")
	inv_col.add_child(orb_section)
	orb_inventory_list = VBoxContainer.new()
	orb_inventory_list.add_theme_constant_override("separation", 6)
	orb_inv_scroll = _make_scroll(orb_inventory_list)
	orb_section.add_child(orb_inv_scroll)

	var metal_section := _make_section("Inventory — Metals")
	inv_col.add_child(metal_section)
	metal_inventory_list = VBoxContainer.new()
	metal_inventory_list.add_theme_constant_override("separation", 6)
	metal_inv_scroll = _make_scroll(metal_inventory_list)
	metal_section.add_child(metal_inv_scroll)

	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", ROW_GAP)
	right_col.custom_minimum_size   = Vector2(400, 0)
	right_col.size_flags_horizontal = Control.SIZE_FILL
	right_col.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	columns.add_child(right_col)

	var staged_section := _make_section("Staged")
	staged_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_child(staged_section)

	staged_list = VBoxContainer.new()
	staged_list.add_theme_constant_override("separation", 6)
	staged_scroll = ScrollContainer.new()
	staged_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	staged_scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	staged_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	staged_scroll.add_child(staged_list)
	staged_list.size_flags_horizontal    = Control.SIZE_EXPAND_FILL
	staged_section.add_child(staged_scroll)

	var info_panel := PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel", _make_panel_style(C_SECTION))
	info_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	right_col.add_child(info_panel)

	var info_pad := _make_margin(10, 10, 10, 10)
	info_panel.add_child(info_pad)

	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 8)
	info_pad.add_child(info_box)
	_info_box = info_box

	heat_label    = _make_label("Heat: 0", FONT_SIZE_NORMAL, C_ACCENT)
	preview_label = _make_label("Add resources to activate.", FONT_SIZE_SMALL, C_SUBTEXT)
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(heat_label)
	info_box.add_child(preview_label)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(bottom)

	cancel_button   = _make_button("Cancel", true)
	activate_button = _make_button("Activate")
	activate_button.disabled = true
	bottom.add_child(cancel_button)
	bottom.add_child(activate_button)

	cancel_button.pressed.connect(_on_cancel_pressed)
	activate_button.pressed.connect(_on_activate_pressed)

	return root

# ── forging screen ────────────────────────────────────────────────────────────
func _build_forging_screen() -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bar_panel := PanelContainer.new()
	bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.09, 0.12, 0.85), 8))
	bar_panel.custom_minimum_size = Vector2(420, 0)
	bar_panel.anchor_left   = 0.5
	bar_panel.anchor_right  = 0.5
	bar_panel.anchor_top    = 0.0
	bar_panel.anchor_bottom = 0.0
	bar_panel.offset_left   = -210
	bar_panel.offset_right  =  210
	bar_panel.offset_top    =  16
	bar_panel.offset_bottom =  16
	root.add_child(bar_panel)

	var pad := _make_margin(8, 14, 8, 14)
	bar_panel.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	pad.add_child(col)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	col.add_child(top_row)

	forging_heat_label = _make_label("Forging  •  Heat: 0", FONT_SIZE_SMALL, C_ACCENT)
	forging_heat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(forging_heat_label)

	forging_wave_label = _make_label("", FONT_SIZE_SMALL, C_SUBTEXT)
	forging_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_row.add_child(forging_wave_label)

	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(0, 10)
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.value = 0.0
	progress_bar.show_percentage = false
	col.add_child(progress_bar)

	# Stall warning label (shown when player is out of proximity range)
	_stall_label = _make_label("", FONT_SIZE_SMALL, Color(1.0, 0.55, 0.15, 1.0))
	_stall_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stall_label.visible = false
	col.add_child(_stall_label)

	return root

# ── ability pick screen ───────────────────────────────────────────────────────
func _build_ability_pick_screen() -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", ROW_GAP)
	root.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	root.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	_ability_pick_title = _make_label("Choose an Ability", FONT_SIZE_LARGE + 4, C_ACCENT)
	_ability_pick_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_ability_pick_title)

	var sub := _make_label("The new orb will be imbued with the chosen ability.", FONT_SIZE_SMALL, C_SUBTEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)

	_ability_pick_cards = HBoxContainer.new()
	_ability_pick_cards.add_theme_constant_override("separation", 24)
	_ability_pick_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(_ability_pick_cards)

	return root

# ── stat pick screen ──────────────────────────────────────────────────────────
func _build_stat_pick_screen() -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", ROW_GAP)
	root.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	root.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	_stat_pick_title = _make_label("Enhance a Stat", FONT_SIZE_LARGE + 4, C_ACCENT)
	_stat_pick_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_stat_pick_title)

	_stat_picks_label = _make_label("", FONT_SIZE_NORMAL, C_SUBTEXT)
	_stat_picks_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_stat_picks_label)

	_stat_pick_cards = HBoxContainer.new()
	_stat_pick_cards.add_theme_constant_override("separation", 24)
	_stat_pick_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(_stat_pick_cards)

	return root

# ── complete screen ───────────────────────────────────────────────────────────
func _build_complete_screen() -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	root.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	result_name_label = _make_label("Forged Orb", FONT_SIZE_LARGE + 4, C_ACCENT)
	result_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(result_name_label)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(name_row)

	var name_lbl := _make_label("Name:", FONT_SIZE_NORMAL, C_SUBTEXT)
	name_row.add_child(name_lbl)

	result_name_input = LineEdit.new()
	result_name_input.custom_minimum_size = Vector2(260, 0)
	result_name_input.add_theme_font_size_override("font_size", FONT_SIZE_NORMAL)
	result_name_input.placeholder_text = "Enter orb name..."
	name_row.add_child(result_name_input)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", COL_GAP)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(cols)

	var ability_section := _make_section("Abilities")
	ability_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ability_section.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	cols.add_child(ability_section)
	result_ability_list = VBoxContainer.new()
	result_ability_list.add_theme_constant_override("separation", 4)
	result_ability_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ability_section.add_child(result_ability_list)

	var stat_section := _make_section("Stat Bonuses")
	stat_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_section.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	cols.add_child(stat_section)
	result_stat_list = VBoxContainer.new()
	result_stat_list.add_theme_constant_override("separation", 4)
	result_stat_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stat_section.add_child(result_stat_list)

	collect_button = _make_button("Collect Orb")
	collect_button.pressed.connect(_on_collect_pressed)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	btn_row.add_child(collect_button)
	root.add_child(btn_row)

	return root

# ── open / close ──────────────────────────────────────────────────────────────
func open(p: Node2D, f: Forge) -> void:
	player = p
	forge  = f
	staged_orbs   = []
	staged_metals = {}
	_ctrl_panel = ForgePanel.ORB_INV
	_ctrl_index = 0
	_ctrl_btn   = 0
	if not forge.forge_complete.is_connected(_on_forge_complete):
		forge.forge_complete.connect(_on_forge_complete, CONNECT_ONE_SHOT)
	if not forge.forge_cancelled.is_connected(_on_forge_cancelled):
		forge.forge_cancelled.connect(_on_forge_cancelled, CONNECT_ONE_SHOT)
	var inventory: Node = player.get_node_or_null("Inventory")
	if inventory == null:
		push_error("ForgeUI: player has no Inventory node!")
		return
	_show_input_screen()
	show()
	dim_overlay.show()
	_apply_scale()
	get_tree().paused = true

func close() -> void:
	if forge != null and forge.state == Forge.State.OPEN:
		forge.state = Forge.State.IDLE
		forge.input_orbs.clear()
		forge.metal_counts.clear()
	player        = null
	forge         = null
	staged_orbs   = []
	staged_metals = {}
	_pending_result  = null
	_chosen_ability  = null
	_stat_picks_remaining = 0
	dim_overlay.hide()
	hide()
	input_screen.hide()
	get_tree().paused = false

# ── screens ───────────────────────────────────────────────────────────────────
func _show_input_screen() -> void:
	input_screen.show()
	forging_screen.hide()
	complete_screen.hide()
	ability_pick_screen.hide()
	stat_pick_screen.hide()
	_rebuild_input_screen()

func _show_forging_screen() -> void:
	input_screen.hide()
	forging_screen.show()
	complete_screen.hide()
	ability_pick_screen.hide()
	stat_pick_screen.hide()
	dim_overlay.hide()
	root_panel.hide()
	forging_heat_label.text = "Forging  •  Heat: %d" % forge.compute_heat()
	forging_wave_label.text = "Enemies incoming..."
	progress_bar.value      = 0.0
	_stall_label.visible    = false

func _show_ability_pick_screen(result: ForgeResult) -> void:
	root_panel.show()
	input_screen.hide()
	forging_screen.hide()
	complete_screen.hide()
	ability_pick_screen.show()
	stat_pick_screen.hide()

	_clear_children(_ability_pick_cards)

	var options: Array[AbilityData] = ForgeResult.build_weighted_ability_options(
		result.metal_counts_snapshot, 3)

	if options.is_empty():
		# No ability pool on any metal — skip ability pick, go straight to stats with no ability
		ability_pick_screen.hide()
		_begin_stat_picks(result, null)
		return

	for ability: AbilityData in options:
		var card := _make_ability_card(ability, func(): _on_ability_chosen(ability, result))
		_ability_pick_cards.add_child(card)

func _show_stat_pick_screen(result: ForgeResult, ability: AbilityData) -> void:
	root_panel.show()
	input_screen.hide()
	forging_screen.hide()
	complete_screen.hide()
	ability_pick_screen.hide()
	stat_pick_screen.show()

	_update_stat_pick_ui(result, ability)

func _update_stat_pick_ui(result: ForgeResult, ability: AbilityData) -> void:
	_clear_children(_stat_pick_cards)

	var picks_left: int = _stat_picks_remaining
	_stat_picks_label.text = "%d pick%s remaining" % [picks_left, "s" if picks_left != 1 else ""]

	if ability != null and "display_name" in ability:
		_stat_pick_title.text = "Enhance: %s" % ability.display_name
	else:
		_stat_pick_title.text = "Enhance Stats"

	var options: Array[Dictionary] = ForgeResult.build_weighted_stat_options(
		result.metal_counts_snapshot, ability, 3)

	if options.is_empty():
		# No valid stats — skip remaining picks
		_finish_result(result)
		return

	for entry: Dictionary in options:
		var stat_name:   String = entry.stat
		var stat_amount: float  = entry.amount
		var card := _make_choice_card(
			stat_name.capitalize().replace("_", " "),
			"+%.2f %s" % [stat_amount, stat_name],
			null,
			func(): _on_stat_chosen(entry, result, ability)
		)
		_stat_pick_cards.add_child(card)

func _show_complete_screen(result: ForgeResult) -> void:
	input_screen.hide()
	forging_screen.hide()
	complete_screen.show()
	ability_pick_screen.hide()
	stat_pick_screen.hide()
	_populate_result(result)
	result_name_input.text = _default_orb_name(result)
	result_name_input.grab_focus()

func _default_orb_name(result: ForgeResult) -> String:
	if result.identity is Orb:
		return (result.identity as Orb).display_name
	elif result.identity is MetalData:
		return (result.identity as MetalData).display_name + " Orb"
	return "Forged Orb"

# ── choice cards (shared by ability + stat pick screens) ──────────────────────
func _make_choice_card(
		title: String,
		desc:  String,
		icon:  Texture2D,
		on_chosen: Callable) -> PanelContainer:

	const CARD_W: float = 260.0
	const CARD_H: float = 300.0
	const RADIUS: float = 10.0

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_W, CARD_H)
	panel.mouse_filter        = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.15, 0.97)
	style.border_color = C_ACCENT.darkened(0.4)
	style.set_border_width_all(2)
	for i in 4:
		style.set_corner_radius(i, RADIUS)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	if icon != null:
		var tex := TextureRect.new()
		tex.texture      = icon
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(56.0, 56.0)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(tex)
		vbox.add_child(center)
	else:
		var placeholder := ColorRect.new()
		placeholder.color = Color(0, 0, 0, 0)
		placeholder.custom_minimum_size = Vector2(56.0, 56.0)
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(placeholder)
		vbox.add_child(center)

	var name_lbl := Label.new()
	name_lbl.text = title
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", FONT_SIZE_NORMAL)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	desc_lbl.add_theme_color_override("font_color", C_SUBTEXT)
	desc_lbl.custom_minimum_size = Vector2(CARD_W - 24.0, 0.0)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_lbl)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)

	var choose_lbl := Label.new()
	choose_lbl.text = "CHOOSE"
	choose_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	choose_lbl.add_theme_font_size_override("font_size", 14)
	choose_lbl.add_theme_color_override("font_color", C_ACCENT.darkened(0.1))
	choose_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(choose_lbl)

	panel.mouse_entered.connect(func():
		style.border_color = C_ACCENT
		style.bg_color     = Color(0.15, 0.18, 0.28, 0.97)
	)
	panel.mouse_exited.connect(func():
		style.border_color = C_ACCENT.darkened(0.4)
		style.bg_color     = Color(0.10, 0.11, 0.15, 0.97)
	)
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton \
				and event.button_index == MOUSE_BUTTON_LEFT \
				and event.pressed:
			on_chosen.call()
	)

	return panel

# ── ability pick card (tooltip-style with stats) ──────────────────────────────
func _make_ability_card(ability: AbilityData, on_chosen: Callable) -> PanelContainer:
	const CARD_W: float = 260.0
	const RADIUS: float = 10.0

	var panel := PanelContainer.new()
	panel.custom_minimum_size        = Vector2(CARD_W, 0.0)
	panel.mouse_filter               = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.06, 0.07, 0.10, 0.97)
	style.border_color = AbilityTooltip.C_BORDER.darkened(0.2)
	style.set_border_width_all(2)
	for i in 4:
		style.set_corner_radius(i, RADIUS)
	style.content_margin_left   = 14
	style.content_margin_right  = 14
	style.content_margin_top    = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	# ── icon + name header ──────────────────────────────────────────────
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if "icon" in ability and ability.icon != null:
		var tex := TextureRect.new()
		tex.texture                = ability.icon
		tex.stretch_mode           = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size    = Vector2(32.0, 32.0)
		tex.mouse_filter           = Control.MOUSE_FILTER_IGNORE
		header.add_child(tex)
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	var aname: String = ability.display_name if "display_name" in ability else "?"
	var name_lbl := Label.new()
	name_lbl.text = aname
	name_lbl.add_theme_font_size_override("font_size", AbilityTooltip.FONT_SIZE_TITLE)
	name_lbl.add_theme_color_override("font_color", AbilityTooltip.C_TITLE)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(name_lbl)
	if "trigger_type" in ability:
		var trig_lbl := Label.new()
		trig_lbl.text = _ability_trigger_label(ability.trigger_type)
		trig_lbl.add_theme_font_size_override("font_size", AbilityTooltip.FONT_SIZE_SMALL)
		trig_lbl.add_theme_color_override("font_color", AbilityTooltip.C_SUBTEXT)
		trig_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_col.add_child(trig_lbl)
	header.add_child(name_col)
	vbox.add_child(header)

	# ── description ─────────────────────────────────────────────────────
	if "description" in ability and ability.description != "":
		vbox.add_child(_make_ability_card_sep())
		var desc_lbl := Label.new()
		desc_lbl.text                  = ability.description
		desc_lbl.autowrap_mode         = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size   = Vector2(CARD_W - 28.0, 0.0)
		desc_lbl.add_theme_font_size_override("font_size", AbilityTooltip.FONT_SIZE_NORMAL)
		desc_lbl.add_theme_color_override("font_color", AbilityTooltip.C_TEXT)
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(desc_lbl)

	# ── stats ────────────────────────────────────────────────────────────
	if ability.stats != null:
		var stat_rows: Array = _collect_ability_stat_rows(ability.stats)
		if not stat_rows.is_empty():
			vbox.add_child(_make_ability_card_sep())
			for row in stat_rows:
				vbox.add_child(row)

	# ── choose prompt ────────────────────────────────────────────────────
	vbox.add_child(_make_ability_card_sep())
	var choose_lbl := Label.new()
	choose_lbl.text                 = "CHOOSE"
	choose_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	choose_lbl.add_theme_font_size_override("font_size", 14)
	choose_lbl.add_theme_color_override("font_color", C_ACCENT.darkened(0.1))
	choose_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(choose_lbl)

	# ── hover / click ────────────────────────────────────────────────────
	panel.mouse_entered.connect(func():
		style.border_color = AbilityTooltip.C_BORDER
		style.bg_color     = Color(0.12, 0.14, 0.22, 0.97)
	)
	panel.mouse_exited.connect(func():
		style.border_color = AbilityTooltip.C_BORDER.darkened(0.2)
		style.bg_color     = Color(0.06, 0.07, 0.10, 0.97)
	)
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton \
				and event.button_index == MOUSE_BUTTON_LEFT \
				and event.pressed:
			on_chosen.call()
	)

	return panel

func _make_ability_card_sep() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator_color", AbilityTooltip.C_BORDER)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep

func _ability_trigger_label(trigger_type: int) -> String:
	match trigger_type:
		0: return "Active"
		1: return "Passive"
		2: return "On hold"
		_: return ""

func _collect_ability_stat_rows(stats: AbilityStats) -> Array:
	var rows: Array = []
	for prop in stats.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var key: String = prop["name"]
		var val         = stats.get(key)
		var default     = AbilityTooltip.STAT_DEFAULTS.get(key, -1)
		if val == default:
			continue
		var unit:    String = AbilityTooltip.STAT_UNITS.get(key, "")
		var display: String = AbilityTooltip.fmt_stat_value(val, unit)
		if display == "":
			continue
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text                  = key.replace("_", " ").capitalize()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", AbilityTooltip.FONT_SIZE_NORMAL)
		lbl.add_theme_color_override("font_color", AbilityTooltip.C_SUBTEXT)
		lbl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
		var val_lbl := Label.new()
		val_lbl.text = display
		val_lbl.add_theme_font_size_override("font_size", AbilityTooltip.FONT_SIZE_NORMAL)
		val_lbl.add_theme_color_override("font_color", AbilityTooltip.C_VALUE)
		val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lbl)
		row.add_child(val_lbl)
		rows.append(row)
	return rows

func _process(_delta: float) -> void:
	if not visible:
		return

	if forging_screen.visible and forge != null and forge.forge_duration > 0.0:
		# Progress bar only advances while the player is in range
		progress_bar.value = clampf(
			forge.forge_timer / forge.forge_duration * 100.0, 0.0, 100.0)

		# Stall / cancel feedback
		if not forge.is_player_in_forge_range():
			var stall_frac: float = forge.get_stall_fraction()
			var secs_left: float  = forge.forge_stall_cancel_time * (1.0 - stall_frac)
			_stall_label.text    = "⚠ Return to the forge! Cancels in %.1fs" % secs_left
			_stall_label.visible = true
		else:
			_stall_label.visible = false

	if Util.last_input_device != Util.InputDevice.CONTROLLER:
		return
	if not input_screen.visible:
		return

	var scroll_amount: float = Input.get_axis("ui_scroll_up", "ui_scroll_down")
	if absf(scroll_amount) < _STICK_DEAD:
		return

	var scroll_target: ScrollContainer = null
	match _ctrl_panel:
		ForgePanel.ORB_INV:   scroll_target = orb_inv_scroll
		ForgePanel.METAL_INV: scroll_target = metal_inv_scroll
		ForgePanel.STAGED:    scroll_target = staged_scroll

	if scroll_target != null:
		scroll_target.scroll_vertical += int(scroll_amount * 12.0)

# ── input ─────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if Util.last_input_device != Util.InputDevice.CONTROLLER:
		return
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return

	if event is InputEventJoypadButton and not event.is_pressed():
		return

	if event is InputEventJoypadMotion:
		var axis:   int  = (event as InputEventJoypadMotion).axis
		var active: bool = absf(event.get_axis_value()) > _STICK_DEAD
		if not active:
			_stick_was_active[axis] = false
			return
		if _stick_was_active.get(axis, false):
			return
		_stick_was_active[axis] = true

	if complete_screen.visible:
		if event.is_action_pressed("confirm") or event.is_action_pressed("cancel"):
			_on_collect_pressed()
		return

	if not input_screen.visible:
		return

	if event.is_action_pressed("ui_navigate_up"):
		_ctrl_navigate_v(-1)
	elif event.is_action_pressed("ui_navigate_down"):
		_ctrl_navigate_v(1)
	elif event.is_action_pressed("ui_navigate_left"):
		_ctrl_navigate_h(-1)
	elif event.is_action_pressed("ui_navigate_right"):
		_ctrl_navigate_h(1)
	elif event.is_action_pressed("confirm"):
		_ctrl_confirm()
	elif event.is_action_pressed("cancel"):
		_on_cancel_pressed()

# ── rebuild ───────────────────────────────────────────────────────────────────
func _rebuild_input_screen() -> void:
	_rebuild_orb_inventory()
	_rebuild_metal_inventory()
	_rebuild_staged()
	_rebuild_heat_and_preview()
	if Util.last_input_device == Util.InputDevice.CONTROLLER:
		_ctrl_clamp_to_valid_panel()
		_ctrl_refresh_focus()

func _rebuild_orb_inventory() -> void:
	_clear_children(orb_inventory_list)
	if player == null:
		return
	var inventory: Node = player.get_node("Inventory")
	if not "orbs" in inventory:
		return
	var orbs: Array = inventory.orbs
	if orbs.is_empty():
		orb_inventory_list.add_child(_make_label("(no orbs)", FONT_SIZE_SMALL, C_SUBTEXT))
		return
	for orb: Orb in orbs:
		if staged_orbs.has(orb):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_make_icon_rect(orb.sprite_texture))
		var lbl := _make_label(orb.display_name, FONT_SIZE_NORMAL)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var btn := _make_button("Stage")
		btn.custom_minimum_size = Vector2(90, 40)
		btn.pressed.connect(_stage_orb.bind(orb))
		row.add_child(btn)
		_wire_orb_tooltip(row, orb)
		orb_inventory_list.add_child(_make_scroll_row(row))

func _rebuild_metal_inventory() -> void:
	_clear_children(metal_inventory_list)
	if player == null:
		return
	var inventory: Node = player.get_node("Inventory")
	if not inventory.has_method("get_metals"):
		return
	var metals: Dictionary = inventory.get_metals()
	if metals.is_empty():
		metal_inventory_list.add_child(_make_label("(no metals)", FONT_SIZE_SMALL, C_SUBTEXT))
		return
	for metal: MetalData in metals.keys():
		var available: int = metals[metal] - staged_metals.get(metal, 0)
		if available <= 0:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_make_icon_rect(metal.sprite_texture))
		var lbl := _make_label("%s (x%d)" % [metal.display_name, available], FONT_SIZE_NORMAL)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		for pair: Array in [["+1", 1], ["+5", mini(5, available)], ["+All", available]]:
			var btn := _make_button(pair[0])
			btn.custom_minimum_size = Vector2(70, 40)
			btn.pressed.connect(_stage_metal.bind(metal, pair[1]))
			row.add_child(btn)
		metal_inventory_list.add_child(_make_scroll_row(row))

func _rebuild_staged() -> void:
	_clear_children(staged_list)
	var has_anything: bool = false

	for orb: Orb in staged_orbs:
		has_anything = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_make_icon_rect(orb.sprite_texture))
		var lbl := _make_label(orb.display_name, FONT_SIZE_NORMAL)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var tag := _make_label("[orb]", FONT_SIZE_SMALL, C_SUBTEXT)
		row.add_child(tag)
		var btn := _make_button("Remove", true)
		btn.custom_minimum_size = Vector2(90, 40)
		btn.pressed.connect(_unstage_orb.bind(orb))
		row.add_child(btn)
		_wire_orb_tooltip(row, orb)
		staged_list.add_child(_make_scroll_row(row))

	for metal: MetalData in staged_metals:
		var count: int = staged_metals[metal]
		if count <= 0:
			continue
		has_anything = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_make_icon_rect(metal.sprite_texture))
		var lbl := _make_label("%s x%d" % [metal.display_name, count], FONT_SIZE_NORMAL)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var tag := _make_label("[metal]", FONT_SIZE_SMALL, C_SUBTEXT)
		row.add_child(tag)
		for pair: Array in [["-1", 1], ["-5", mini(5, count)], ["-All", count]]:
			var btn := _make_button(pair[0], true)
			btn.custom_minimum_size = Vector2(70, 40)
			btn.pressed.connect(_unstage_metal.bind(metal, pair[1]))
			row.add_child(btn)
		staged_list.add_child(_make_scroll_row(row))

	if not has_anything:
		staged_list.add_child(_make_label("(nothing staged)", FONT_SIZE_SMALL, C_SUBTEXT))

func _rebuild_heat_and_preview() -> void:
	var heat: int = 0
	for metal: MetalData in staged_metals:
		heat += metal.rarity * staged_metals[metal]
	heat_label.text          = "Heat: %d" % heat
	activate_button.disabled = not (forge != null and forge.can_activate())

	for child in _info_box.get_children():
		if child != heat_label and child != preview_label:
			_info_box.remove_child(child)
			child.queue_free()

	if forge == null or not forge.can_activate():
		preview_label.text = "Add resources to activate."
		preview_label.show()
		return

	preview_label.hide()

	if staged_orbs.is_empty():
		var total_metal: int = 0
		for metal: MetalData in staged_metals:
			total_metal += staged_metals[metal]
		var picks: int = ForgeResult.stat_pick_count(staged_metals)

		var lines: Array[String] = []
		lines.append("Forging new orb:")
		lines.append("• You will choose 1 ability from a weighted random pool")
		lines.append("• Then choose %d stat upgrade%s" % [picks, "s" if picks != 1 else ""])
		preview_label.text = "\n".join(lines)
		preview_label.show()
	else:
		var all_abilities: Array[AbilityData] = []
		for orb: Orb in staged_orbs:
			for ability: AbilityData in orb.abilities:
				all_abilities.append(ability)

		var hdr := _make_label("Inherited abilities:", FONT_SIZE_SMALL, C_SUBTEXT)
		_info_box.add_child(hdr)

		for ability: AbilityData in all_abilities:
			var aname: String = ability.display_name \
				if "display_name" in ability else ability.get_class()
			var a_lbl := _make_label("  • " + aname, FONT_SIZE_NORMAL, C_TEXT)
			a_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
			a_lbl.custom_minimum_size = Vector2(0, 24)
			var ability_ref: AbilityData = ability
			a_lbl.mouse_entered.connect(func() -> void:
				_ability_tooltip.request_show(ability_ref, get_viewport().get_mouse_position()))
			a_lbl.mouse_exited.connect(func() -> void:
				_ability_tooltip.request_hide())
			_info_box.add_child(a_lbl)

		var picks: int = ForgeResult.stat_pick_count(staged_metals)
		var stat_note: Label
		if picks > 0:
			stat_note = _make_label(
				"You will choose %d stat upgrade%s for a randomly picked ability." % [picks, "s" if picks != 1 else ""],
				FONT_SIZE_SMALL, C_SUBTEXT)
		else:
			stat_note = _make_label(
				"Add metal to unlock stat upgrades.",
				FONT_SIZE_SMALL, C_SUBTEXT)
		stat_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info_box.add_child(stat_note)

# ── staging ───────────────────────────────────────────────────────────────────
func _stage_orb(orb: Orb) -> void:
	staged_orbs.append(orb)
	forge.deposit_orb(orb)
	_rebuild_input_screen()

func _unstage_orb(orb: Orb) -> void:
	staged_orbs.erase(orb)
	forge.withdraw_orb(orb)
	_rebuild_input_screen()

func _stage_metal(metal: MetalData, count: int) -> void:
	staged_metals[metal] = staged_metals.get(metal, 0) + count
	forge.deposit_metal(metal, count)
	_rebuild_input_screen()

func _unstage_metal(metal: MetalData, count: int) -> void:
	var current: int = staged_metals.get(metal, 0)
	var remove:  int = mini(count, current)
	staged_metals[metal] = current - remove
	if staged_metals[metal] <= 0:
		staged_metals.erase(metal)
	forge.withdraw_metal(metal, remove)
	_rebuild_input_screen()

# ── buttons ───────────────────────────────────────────────────────────────────
func _on_activate_pressed() -> void:
	if forge == null or not forge.can_activate():
		return
	var inventory: Node = player.get_node("Inventory")
	forge.activate()
	_show_forging_screen()
	get_tree().paused = false
	for orb: Orb in staged_orbs:
		inventory.remove_orb(orb)
	for metal: MetalData in staged_metals:
		inventory.remove_metals(metal, staged_metals[metal])

func _on_cancel_pressed() -> void:
	for orb: Orb in staged_orbs:
		forge.withdraw_orb(orb)
	for metal: MetalData in staged_metals:
		forge.withdraw_metal(metal, staged_metals[metal])
	forge.state = Forge.State.IDLE
	forge.input_orbs.clear()
	forge.metal_counts.clear()
	close()

func _on_collect_pressed() -> void:
	if forge == null or _pending_result == null:
		return
	var result: ForgeResult = _pending_result
	var new_orb: Orb = _build_orb_from_result(result)
	var typed_name: String = result_name_input.text.strip_edges()
	if typed_name != "":
		new_orb.display_name = typed_name
	player.get_node("Inventory").add_orb(new_orb)

	# Permanently add each forged metal's enemy pool to the normal roster.
	for metal: MetalData in result.metal_counts_snapshot:
		if not metal.enemy_pool.is_empty():
			WaveManager.add_to_normal_roster(metal.enemy_pool)

	forge.state = Forge.State.COMPLETE
	close()

func _on_forge_complete(result: ForgeResult) -> void:
	_pending_result = result
	get_tree().paused = true
	dim_overlay.show()
	root_panel.show()

	# Kick off the interactive selection flow.
	# Rule: the resulting orb must always have at least 1 ability.
	# - Metal-only forge: player always picks 1 ability from a weighted pool.
	# - Orb merge: abilities are inherited. If the merged result still has 0
	#   abilities (e.g. all input orbs were empty), fall back to ability pick
	#   so the minimum-1 guarantee is upheld.
	if result.is_metal_only or result.abilities.is_empty():
		# Let player choose 1 ability, then stat upgrades
		_show_ability_pick_screen(result)
	else:
		# Orb merge with existing abilities: no new ability added,
		# go straight to stat picks for a randomly chosen ability on the orb.
		_begin_stat_picks(result, _pick_random_ability_from_result(result))

func _on_forge_cancelled() -> void:
	# Forge timed out because player left range — destroy forge, give nothing
	get_tree().paused = true
	dim_overlay.show()
	root_panel.show()

	_show_cancel_notice()

func _show_cancel_notice() -> void:
	# Reuse complete screen layout to show a simple "Forge destroyed" message
	_clear_children(result_ability_list)
	_clear_children(result_stat_list)
	result_name_label.text = "Forge Destroyed"
	result_ability_list.add_child(_make_label(
		"You strayed too far and the forge collapsed.", FONT_SIZE_SMALL, C_SUBTEXT))
	result_stat_list.add_child(_make_label(
		"Nothing was recovered.", FONT_SIZE_SMALL, C_SUBTEXT))
	collect_button.text = "Dismiss"
	# Temporarily swap the handler for the cancel case.
	# CONNECT_ONE_SHOT means the lambda auto-disconnects after firing.
	collect_button.pressed.disconnect(_on_collect_pressed)
	collect_button.pressed.connect(_on_cancel_notice_dismissed, CONNECT_ONE_SHOT)

	input_screen.hide()
	forging_screen.hide()
	ability_pick_screen.hide()
	stat_pick_screen.hide()
	complete_screen.show()

func _on_cancel_notice_dismissed() -> void:
	if forge != null:
		forge.state = Forge.State.CANCELLED
	# Restore button to normal state before closing
	collect_button.text = "Collect Orb"
	collect_button.pressed.connect(_on_collect_pressed)
	_pending_result = null
	close()

# ── interactive selection flow ────────────────────────────────────────────────
func _on_ability_chosen(ability: AbilityData, result: ForgeResult) -> void:
	result.abilities.append(ability.duplicate(true))
	_chosen_ability = ability
	_begin_stat_picks(result, ability)

func _begin_stat_picks(result: ForgeResult, ability: AbilityData) -> void:
	_chosen_ability       = ability
	_stat_picks_remaining = ForgeResult.stat_pick_count(result.metal_counts_snapshot)
	# If no metal was used, skip stat picks entirely
	if _stat_picks_remaining <= 0:
		_finish_result(result)
		return
	_show_stat_pick_screen(result, ability)

func _on_stat_chosen(entry: Dictionary, result: ForgeResult, ability: AbilityData) -> void:
	# Apply the stat bonus to the result
	var stat:   String = entry.stat
	var amount: float  = entry.amount
	result.stat_bonuses[stat] = result.stat_bonuses.get(stat, 0.0) + amount

	_stat_picks_remaining -= 1
	if _stat_picks_remaining > 0:
		_update_stat_pick_ui(result, ability)
	else:
		_finish_result(result)

func _finish_result(result: ForgeResult) -> void:
	_pending_result = result
	_show_complete_screen(result)

func _pick_random_ability_from_result(result: ForgeResult) -> AbilityData:
	if result.abilities.is_empty():
		return null
	return result.abilities[randi() % result.abilities.size()]

# ── result screen ─────────────────────────────────────────────────────────────
func _populate_result(result: ForgeResult) -> void:
	_clear_children(result_ability_list)
	_clear_children(result_stat_list)

	if result.identity is Orb:
		result_name_label.text = "Forged: %s" % (result.identity as Orb).display_name
	elif result.identity is MetalData:
		result_name_label.text = "Forged: %s Orb" % (result.identity as MetalData).display_name
	else:
		result_name_label.text = "Forged Orb"

	if result.abilities.is_empty():
		result_ability_list.add_child(_make_label("(none)", FONT_SIZE_SMALL, C_SUBTEXT))
	for ability: AbilityData in result.abilities:
		var aname: String = ability.display_name if "display_name" in ability else ability.get_class()
		var lbl: Label = _make_label("• " + aname, FONT_SIZE_NORMAL)
		lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		var ability_ref: AbilityData = ability
		lbl.mouse_entered.connect(func() -> void:
			_ability_tooltip.request_show(ability_ref, get_viewport().get_mouse_position()))
		lbl.mouse_exited.connect(func() -> void:
			_ability_tooltip.request_hide())
		result_ability_list.add_child(lbl)

	if result.stat_bonuses.is_empty():
		result_stat_list.add_child(_make_label("(none)", FONT_SIZE_SMALL, C_SUBTEXT))
	for stat: String in result.stat_bonuses:
		result_stat_list.add_child(
			_make_label("+ %s  %.2f" % [stat, result.stat_bonuses[stat]], FONT_SIZE_NORMAL))

func _build_orb_from_result(result: ForgeResult) -> Orb:
	var orb := Orb.new()
	if result.identity is Orb:
		var src: Orb       = result.identity as Orb
		orb.display_name   = src.display_name
		orb.sprite_texture = src.sprite_texture
		# Carry forward existing metal investment from the source orb.
		orb.total_metal_forged = src.total_metal_forged
		orb.metal_composition  = src.metal_composition.duplicate()
	elif result.identity is MetalData:
		var src: MetalData = result.identity as MetalData
		orb.display_name   = src.display_name + " Orb"
		orb.sprite_texture = src.sprite_texture
	# Add the metal used in this forge session (per-metal for composition tracking).
	for metal: MetalData in result.metal_counts_snapshot:
		var count: int = result.metal_counts_snapshot[metal]
		orb.add_metal_forged(count, metal)
	for ability: AbilityData in result.abilities:
		orb.abilities.append(ability.duplicate(true))
	for ability: AbilityData in orb.abilities:
		if ability.stats == null:
			continue
		for stat: String in result.stat_bonuses:
			if stat in ability.stats:
				ability.stats[stat] += result.stat_bonuses[stat]
	return orb

# ── helpers ───────────────────────────────────────────────────────────────────
func _clear_children(node: Control) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _wire_orb_tooltip(row: HBoxContainer, orb: Orb) -> void:
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.mouse_entered.connect(func() -> void:
		_tooltip.request_show(orb, get_viewport().get_mouse_position()))
	row.mouse_exited.connect(func() -> void:
		_tooltip.request_hide())

# ── controller helpers (unchanged) ────────────────────────────────────────────
func _ctrl_row_count(panel: ForgePanel) -> int:
	match panel:
		ForgePanel.ORB_INV:   return _get_orb_inv_rows().size()
		ForgePanel.METAL_INV: return _get_metal_inv_rows().size()
		ForgePanel.STAGED:    return _get_staged_rows().size()
		ForgePanel.BUTTONS:   return 1
	return 0

func _get_orb_inv_rows() -> Array:
	var rows: Array = []
	for child in orb_inventory_list.get_children():
		if child is MarginContainer:
			rows.append(child)
	return rows

func _get_metal_inv_rows() -> Array:
	var rows: Array = []
	for child in metal_inventory_list.get_children():
		if child is MarginContainer:
			rows.append(child)
	return rows

func _get_staged_rows() -> Array:
	var rows: Array = []
	for child in staged_list.get_children():
		if child is MarginContainer:
			rows.append(child)
	return rows

func _get_row_hbox(wrap: MarginContainer) -> HBoxContainer:
	return wrap.get_child(0) as HBoxContainer

func _ctrl_navigate_v(dir: int) -> void:
	if complete_screen.visible:
		return

	if _ctrl_panel == ForgePanel.BUTTONS:
		if dir == -1:
			for panel in [ForgePanel.STAGED, ForgePanel.METAL_INV, ForgePanel.ORB_INV]:
				var c: int = _ctrl_row_count(panel)
				if c > 0:
					_ctrl_panel = panel
					_ctrl_index = c - 1
					_ctrl_btn   = 0
					_ctrl_refresh_focus()
					var scroll: ScrollContainer = _scroll_for_panel(_ctrl_panel)
					_scroll_to_row(scroll, _rows_for_panel(_ctrl_panel), _ctrl_index)
					return
		return

	var count: int     = _ctrl_row_count(_ctrl_panel)
	var new_index: int = _ctrl_index + dir

	if new_index < 0:
		match _ctrl_panel:
			ForgePanel.METAL_INV:
				var c: int = _ctrl_row_count(ForgePanel.ORB_INV)
				if c > 0:
					_ctrl_panel = ForgePanel.ORB_INV
					_ctrl_index = c - 1
					_ctrl_btn   = 0
			ForgePanel.STAGED, ForgePanel.ORB_INV:
				pass
	elif new_index >= count:
		match _ctrl_panel:
			ForgePanel.ORB_INV:
				var c: int = _ctrl_row_count(ForgePanel.METAL_INV)
				if c > 0:
					_ctrl_panel = ForgePanel.METAL_INV
					_ctrl_index = 0
					_ctrl_btn   = 0
				else:
					_ctrl_panel = ForgePanel.BUTTONS
					_ctrl_index = 0
					_ctrl_btn   = 0
			ForgePanel.METAL_INV, ForgePanel.STAGED:
				_ctrl_panel = ForgePanel.BUTTONS
				_ctrl_index = 0
				_ctrl_btn   = 0
	else:
		_ctrl_index = new_index
		var rows: Array = _rows_for_panel(_ctrl_panel)
		if _ctrl_index < rows.size():
			var btn_count: int = _staged_row_button_count(_get_row_hbox(rows[_ctrl_index]))
			if btn_count > 0:
				_ctrl_btn = clampi(_ctrl_btn, 0, btn_count - 1)

	_ctrl_refresh_focus()
	if _ctrl_panel != ForgePanel.BUTTONS:
		var scroll: ScrollContainer = _scroll_for_panel(_ctrl_panel)
		_scroll_to_row(scroll, _rows_for_panel(_ctrl_panel), _ctrl_index)

func _ctrl_navigate_h(dir: int) -> void:
	if complete_screen.visible:
		return

	if _ctrl_panel == ForgePanel.BUTTONS:
		if dir == -1:
			if _ctrl_btn == 1:
				_ctrl_btn = 0
			else:
				for panel in [ForgePanel.METAL_INV, ForgePanel.ORB_INV]:
					var c: int = _ctrl_row_count(panel)
					if c > 0:
						_ctrl_panel = panel
						_ctrl_index = c - 1
						_ctrl_btn   = 0
						_ctrl_refresh_focus()
						return
		else:
			var new_btn: int = clampi(_ctrl_btn + dir, 0, 1)
			if new_btn == 1 and activate_button.disabled:
				new_btn = 0
			_ctrl_btn = new_btn
		_ctrl_refresh_focus()
		return

	if _ctrl_panel == ForgePanel.METAL_INV:
		var rows: Array = _get_metal_inv_rows()
		if _ctrl_index < rows.size():
			var btn_count: int = _staged_row_button_count(_get_row_hbox(rows[_ctrl_index]))
			if dir == -1 and _ctrl_btn == 0:
				var c: int = _ctrl_row_count(ForgePanel.STAGED)
				if c > 0:
					_ctrl_panel = ForgePanel.STAGED
					_ctrl_index = clampi(_ctrl_index, 0, c - 1)
					_ctrl_btn   = 0
			elif dir == 1 and _ctrl_btn >= btn_count - 1:
				pass
			else:
				_ctrl_btn = clampi(_ctrl_btn + dir, 0, btn_count - 1)
		_ctrl_refresh_focus()
		return

	if _ctrl_panel == ForgePanel.ORB_INV:
		if dir == 1:
			var c: int = _ctrl_row_count(ForgePanel.STAGED)
			if c > 0:
				_ctrl_panel = ForgePanel.STAGED
				_ctrl_index = clampi(_ctrl_index, 0, c - 1)
				_ctrl_btn   = 0
			else:
				_ctrl_panel = ForgePanel.BUTTONS
				_ctrl_index = 0
				_ctrl_btn   = 0
		_ctrl_refresh_focus()
		return

	if _ctrl_panel == ForgePanel.STAGED:
		var rows: Array = _get_staged_rows()
		if _ctrl_index >= rows.size():
			return
		var btn_count: int = _staged_row_button_count(_get_row_hbox(rows[_ctrl_index]))
		if dir == -1 and _ctrl_btn == 0:
			_ctrl_panel = ForgePanel.ORB_INV if _ctrl_row_count(ForgePanel.ORB_INV) > 0 \
				else ForgePanel.METAL_INV
			_ctrl_index = 0
			_ctrl_btn   = 0
		elif dir == 1 and _ctrl_btn >= btn_count - 1:
			pass
		else:
			_ctrl_btn = clampi(_ctrl_btn + dir, 0, btn_count - 1)
		_ctrl_refresh_focus()

func _staged_row_button_count(row: Control) -> int:
	var count: int = 0
	for child in row.get_children():
		if child is Button:
			count += 1
	return count

func _ctrl_confirm() -> void:
	if _ctrl_panel == ForgePanel.BUTTONS:
		if _ctrl_btn == 0:
			_on_cancel_pressed()
		elif not activate_button.disabled:
			_on_activate_pressed()
		return

	if _ctrl_panel == ForgePanel.ORB_INV:
		var rows: Array = _get_orb_inv_rows()
		if _ctrl_index < rows.size():
			_press_last_button(_get_row_hbox(rows[_ctrl_index]))
	elif _ctrl_panel == ForgePanel.METAL_INV:
		var rows: Array = _get_metal_inv_rows()
		if _ctrl_index < rows.size():
			_press_nth_button(_get_row_hbox(rows[_ctrl_index]), _ctrl_btn)
	elif _ctrl_panel == ForgePanel.STAGED:
		var rows: Array = _get_staged_rows()
		if _ctrl_index < rows.size():
			_press_nth_button(_get_row_hbox(rows[_ctrl_index]), _ctrl_btn)

func _press_last_button(row: Control) -> void:
	var last_btn: Button = null
	for child in row.get_children():
		if child is Button and not child.disabled:
			last_btn = child
	if last_btn != null:
		last_btn.emit_signal("pressed")

func _press_nth_button(row: Control, n: int) -> void:
	var idx: int = 0
	for child in row.get_children():
		if child is Button:
			if idx == n:
				if not child.disabled:
					child.emit_signal("pressed")
				return
			idx += 1

func _apply_highlight(btn: Button) -> void:
	var hover_style: StyleBoxFlat = btn.get_theme_stylebox("hover") as StyleBoxFlat
	if hover_style != null:
		btn.add_theme_stylebox_override("normal", hover_style)

func _ctrl_refresh_focus() -> void:
	_ctrl_clear_all_highlights()

	if _ctrl_panel == ForgePanel.BUTTONS:
		var target: Button = cancel_button
		if _ctrl_btn == 1 and not activate_button.disabled:
			target = activate_button
		_apply_highlight(target)
		return

	var rows: Array = []
	match _ctrl_panel:
		ForgePanel.ORB_INV:   rows = _get_orb_inv_rows()
		ForgePanel.METAL_INV: rows = _get_metal_inv_rows()
		ForgePanel.STAGED:    rows = _get_staged_rows()

	if _ctrl_index >= rows.size():
		return

	var row_hbox: HBoxContainer = _get_row_hbox(rows[_ctrl_index])

	if _ctrl_panel == ForgePanel.ORB_INV:
		var last_btn: Button = null
		for child in row_hbox.get_children():
			if child is Button:
				last_btn = child
		if last_btn != null:
			_apply_highlight(last_btn)
	else:
		var idx: int = 0
		for child in row_hbox.get_children():
			if child is Button:
				if idx == _ctrl_btn:
					_apply_highlight(child)
					return
				idx += 1

func _ctrl_clear_all_highlights() -> void:
	for btn in [cancel_button, activate_button, collect_button]:
		if btn != null:
			btn.remove_theme_stylebox_override("normal")
	for list in [orb_inventory_list, metal_inventory_list, staged_list]:
		if list == null:
			continue
		for wrap in list.get_children():
			if not wrap is MarginContainer:
				continue
			var row_hbox = _get_row_hbox(wrap)
			if row_hbox == null:
				continue
			for child in row_hbox.get_children():
				if child is Button:
					child.remove_theme_stylebox_override("normal")

func _ctrl_clamp_to_valid_panel() -> void:
	if _ctrl_panel == ForgePanel.BUTTONS:
		if _ctrl_btn == 1 and activate_button.disabled:
			_ctrl_btn = 0
		return

	if _ctrl_row_count(_ctrl_panel) > 0:
		_ctrl_index = clampi(_ctrl_index, 0, _ctrl_row_count(_ctrl_panel) - 1)
		var rows: Array = []
		match _ctrl_panel:
			ForgePanel.ORB_INV:   rows = _get_orb_inv_rows()
			ForgePanel.METAL_INV: rows = _get_metal_inv_rows()
			ForgePanel.STAGED:    rows = _get_staged_rows()
		if _ctrl_index < rows.size():
			var btn_count: int = _staged_row_button_count(_get_row_hbox(rows[_ctrl_index]))
			if btn_count > 0:
				_ctrl_btn = clampi(_ctrl_btn, 0, btn_count - 1)
		return

	for panel: ForgePanel in [ForgePanel.ORB_INV, ForgePanel.METAL_INV,
			ForgePanel.STAGED, ForgePanel.BUTTONS]:
		if _ctrl_row_count(panel) > 0 or panel == ForgePanel.BUTTONS:
			_ctrl_panel = panel
			_ctrl_index = 0
			_ctrl_btn   = 0
			return

func _scroll_for_panel(panel: ForgePanel) -> ScrollContainer:
	match panel:
		ForgePanel.ORB_INV:   return orb_inv_scroll
		ForgePanel.METAL_INV: return metal_inv_scroll
		ForgePanel.STAGED:    return staged_scroll
	return null

func _rows_for_panel(panel: ForgePanel) -> Array:
	match panel:
		ForgePanel.ORB_INV:   return _get_orb_inv_rows()
		ForgePanel.METAL_INV: return _get_metal_inv_rows()
		ForgePanel.STAGED:    return _get_staged_rows()
	return []

func _scroll_to_row(scroll: ScrollContainer, rows: Array, index: int) -> void:
	if scroll == null or index >= rows.size():
		return
	await get_tree().process_frame
	var row: Control = rows[index]
	var row_top:    int = int(row.position.y)
	var row_bottom: int = row_top + int(row.size.y)
	var view_top:    int = scroll.scroll_vertical
	var view_bottom: int = view_top + int(scroll.size.y)
	if row_top < view_top:
		scroll.scroll_vertical = row_top
	elif row_bottom > view_bottom:
		scroll.scroll_vertical = row_bottom - int(scroll.size.y)
