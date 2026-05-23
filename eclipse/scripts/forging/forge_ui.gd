# forge_ui.gd
extends CanvasLayer

# ── references ────────────────────────────────────────────────────────────────
var player: Node2D = null
var forge:  Forge  = null

# ── state ─────────────────────────────────────────────────────────────────────
var staged_orbs:   Array[Orb]  = []
var staged_metals: Dictionary  = {}   # MetalData → int
var result_name_input: LineEdit = null

# ── sizing ────────────────────────────────────────────────────────────────────
var ui_scale: float = 1.0

# ── built nodes (no @onready — we create everything in _ready) ────────────────
var root_panel:          PanelContainer  = null
var input_screen:        Control         = null
var forging_screen:      Control         = null
var complete_screen:     Control         = null

var orb_inventory_list:  VBoxContainer   = null
var metal_inventory_list:VBoxContainer   = null
var staged_list:         VBoxContainer   = null   # combined orbs + metals

var heat_label:          Label           = null
var preview_label:       Label           = null
var _info_box:           VBoxContainer   = null
var activate_button:     Button          = null
var cancel_button:       Button          = null

var progress_bar:        ProgressBar     = null
var forging_heat_label:  Label           = null
var forging_wave_label:  Label           = null

var result_name_label:   Label           = null
var result_ability_list: VBoxContainer   = null
var result_stat_list:    VBoxContainer   = null
var collect_button:      Button          = null

var dim_overlay: ColorRect = null

var _tooltip: OrbTooltip = null
var _ability_tooltip: AbilityTooltip = null

# ── controller navigation ─────────────────────────────────────────────────────
enum ForgePanel { ORB_INV, METAL_INV, STAGED, BUTTONS }

var _ctrl_panel:     ForgePanel = ForgePanel.ORB_INV
var _ctrl_index:     int        = 0   # focused row within the current panel
var _ctrl_btn:       int        = 0   # focused button index within a row
var _stick_cooldown: float      = 0.0
const _STICK_REPEAT: float      = 0.18
const _STICK_DEAD:   float      = 0.4

# ── Actions used by this UI ───────────────────────────────────────────────────
# All of these are Godot built-ins present in every project by default.
# Controller bindings: ui_accept=A, ui_cancel=B, ui_up/down/left/right=dpad+left stick.
# Keyboard bindings:   ui_accept=Enter/Space, ui_cancel=Escape, ui_up/down/left/right=arrows.
# No entries needed in Project Settings — they already exist.

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
	# Prevent Godot's built-in focus visuals from conflicting with our highlight.
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

	input_screen    = _build_input_screen()
	complete_screen = _build_complete_screen()

	for screen: Control in [input_screen, complete_screen]:
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
	orb_section.add_child(_make_scroll(orb_inventory_list))

	var metal_section := _make_section("Inventory — Metals")
	inv_col.add_child(metal_section)
	metal_inventory_list = VBoxContainer.new()
	metal_inventory_list.add_theme_constant_override("separation", 6)
	metal_section.add_child(_make_scroll(metal_inventory_list))

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
	var staged_scroll := ScrollContainer.new()
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
	dim_overlay.hide()
	hide()
	input_screen.hide()
	get_tree().paused = false

# ── screens ───────────────────────────────────────────────────────────────────
func _show_input_screen() -> void:
	input_screen.show()
	forging_screen.hide()
	complete_screen.hide()
	_rebuild_input_screen()

func _show_forging_screen() -> void:
	input_screen.hide()
	forging_screen.show()
	complete_screen.hide()
	dim_overlay.hide()
	root_panel.hide()
	forging_heat_label.text = "Forging  •  Heat: %d" % forge.compute_heat()
	forging_wave_label.text = "Enemies incoming..."
	progress_bar.value      = 0.0

func _show_complete_screen(result: ForgeResult) -> void:
	input_screen.hide()
	forging_screen.hide()
	complete_screen.show()
	_populate_result(result)
	result_name_input.text = _default_orb_name(result)
	result_name_input.grab_focus()

func _default_orb_name(result: ForgeResult) -> String:
	if result.identity is Orb:
		return (result.identity as Orb).display_name
	elif result.identity is MetalData:
		return (result.identity as MetalData).display_name + " Orb"
	return "Forged Orb"

# ── process ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not visible:
		return
	if forging_screen.visible and forge != null and forge.forge_duration > 0.0:
		progress_bar.value = clampf(
			forge.forge_timer / forge.forge_duration * 100.0, 0.0, 100.0)

	if Util.last_input_device != Util.InputDevice.CONTROLLER:
		return
	if not input_screen.visible and not complete_screen.visible:
		return

	_stick_cooldown -= delta
	if _stick_cooldown > 0.0:
		return

	# ui_left/right/up/down cover both dpad and left stick in Godot's defaults.
	# get_axis reads analog values, so stick deflection magnitude is captured.
	var h: float = Input.get_axis("ui_left", "ui_right")
	var v: float = Input.get_axis("ui_up",   "ui_down")

	if absf(h) < _STICK_DEAD and absf(v) < _STICK_DEAD:
		_stick_cooldown = 0.0
		return

	_stick_cooldown = _STICK_REPEAT
	if absf(h) >= absf(v):
		_ctrl_navigate_h(1 if h > 0 else -1)
	else:
		_ctrl_navigate_v(1 if v > 0 else -1)

# ── input ─────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if Util.last_input_device != Util.InputDevice.CONTROLLER:
		return
	if not event.is_pressed():
		return

	# Complete screen: either confirm button collects the orb.
	if complete_screen.visible:
		if event.is_action("ui_accept") or event.is_action("ui_cancel"):
			_on_collect_pressed()
		return

	if not input_screen.visible:
		return

	# Navigation: set cooldown to prevent _process from double-firing the same frame.
	if event.is_action("ui_up"):
		_ctrl_navigate_v(-1)
		_stick_cooldown = _STICK_REPEAT
	elif event.is_action("ui_down"):
		_ctrl_navigate_v(1)
		_stick_cooldown = _STICK_REPEAT
	elif event.is_action("ui_left"):
		_ctrl_navigate_h(-1)
		_stick_cooldown = _STICK_REPEAT
	elif event.is_action("ui_right"):
		_ctrl_navigate_h(1)
		_stick_cooldown = _STICK_REPEAT
	elif event.is_action("ui_accept"):
		_ctrl_confirm()
	elif event.is_action("ui_cancel"):
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
		var lines: Array[String] = []
		for metal: MetalData in staged_metals:
			var ability_desc: String = "new ability" if not metal.ability_pool.is_empty() else "no ability"
			var bonus_parts:  Array[String] = []
			for s: String in metal.stat_names:
				bonus_parts.append("+%s" % s)
			var bonus_desc: String = ", ".join(bonus_parts) if not bonus_parts.is_empty() else "no bonus"
			lines.append("• %s → %s, %s" % [metal.display_name, ability_desc, bonus_desc])
		preview_label.text = "Forging new orb:\n" + "\n".join(lines)
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

		var stat_names: Array[String] = []
		for metal: MetalData in staged_metals:
			for stat: String in metal.stat_names:
				if not stat_names.has(stat):
					stat_names.append(stat)
		if not stat_names.is_empty():
			_info_box.add_child(_make_label(
				"Metal bonuses to: " + ", ".join(stat_names), FONT_SIZE_SMALL, C_SUBTEXT))

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
	if forge == null or forge.result == null:
		return
	var new_orb: Orb = _build_orb_from_result(forge.result)
	var typed_name: String = result_name_input.text.strip_edges()
	if typed_name != "":
		new_orb.display_name = typed_name
	player.get_node("Inventory").add_orb(new_orb)
	forge.state = Forge.State.COMPLETE
	close()

func _on_forge_complete(result: ForgeResult) -> void:
	get_tree().paused = true
	dim_overlay.show()
	root_panel.show()
	_show_complete_screen(result)

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
		var name: String = ability.display_name if "display_name" in ability else ability.get_class()
		result_ability_list.add_child(_make_label("• " + name, FONT_SIZE_NORMAL))

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
	elif result.identity is MetalData:
		var src: MetalData = result.identity as MetalData
		orb.display_name   = src.display_name + " Orb"
		orb.sprite_texture = src.sprite_texture
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

# ── controller helpers ────────────────────────────────────────────────────────

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
					return
		return

	var count: int = _ctrl_row_count(_ctrl_panel)
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
				pass   # already at top edge
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
		_ctrl_btn   = 0

	_ctrl_refresh_focus()

func _ctrl_navigate_h(dir: int) -> void:
	if complete_screen.visible:
		return

	if _ctrl_panel == ForgePanel.BUTTONS:
		var new_btn: int = clampi(_ctrl_btn + dir, 0, 1)
		# Don't land on a disabled Activate button.
		if new_btn == 1 and activate_button.disabled:
			new_btn = 0
		_ctrl_btn = new_btn
		_ctrl_refresh_focus()
		return

	if _ctrl_panel in [ForgePanel.ORB_INV, ForgePanel.METAL_INV]:
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
	elif _ctrl_panel == ForgePanel.STAGED:
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
			pass   # already at rightmost button
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
		# Single "Stage" button — always the last Button child.
		var last_btn: Button = null
		for child in row_hbox.get_children():
			if child is Button:
				last_btn = child
		if last_btn != null:
			_apply_highlight(last_btn)
	else:
		# Metal inventory and staged: highlight the button at _ctrl_btn index.
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
		# Cancel is never disabled; make sure btn index is sane.
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

	# Panel empty — walk priority order to find a non-empty one.
	for panel: ForgePanel in [ForgePanel.ORB_INV, ForgePanel.METAL_INV,
			ForgePanel.STAGED, ForgePanel.BUTTONS]:
		if _ctrl_row_count(panel) > 0 or panel == ForgePanel.BUTTONS:
			_ctrl_panel = panel
			_ctrl_index = 0
			_ctrl_btn   = 0
			return
