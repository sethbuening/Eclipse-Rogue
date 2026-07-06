# hud_item_tray.gd
# Displays relics (top-left) and current orbs (below relics) as icon rows.
# Hovering an orb icon shows the OrbTooltip for that orb.

extends Control

# ── tunables ──────────────────────────────────────────────────────────────────

const ICON_SIZE:    int   = 48
const ICON_GAP:     int   = 10
const ROW_GAP:      int   = 8
const TOP_MARGIN:   int   = 20
const LEFT_MARGIN:  int   = 20
const ICON_PADDING: int   = 6
const BADGE_FONT:   int   = 16

const RELIC_TINT:   Color = Color(1.0,  0.85, 0.3,  1.0)
const BADGE_TEXT:   Color = Color(1.0,  1.0,  1.0,  1.0)
const ICON_BG:      Color = Color(0.0, 0.0, 0.0, 0.0)

# ── internal ──────────────────────────────────────────────────────────────────

var _player:        CharacterBody2D = null
var _relic_row:     HBoxContainer   = null
var _orb_row:       HBoxContainer   = null
var _ability_row:   HBoxContainer   = null
var _tooltip_panel: PanelContainer  = null
var _tooltip_name:  Label           = null
var _tooltip_desc:  Label           = null


# ── lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_rows()
	_build_tooltip()

	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if _player == null:
		push_warning("HudItemTray: no node in group 'player' found")
		return

	var inv := _player.get_node("RunInventory")
	inv.relic_added.connect(_on_inventory_changed)
	inv.relic_removed.connect(_on_inventory_changed)
	inv.ability_added.connect(_on_inventory_changed)
	inv.ability_removed.connect(_on_inventory_changed)
	_rebuild_all()

# ── layout construction ───────────────────────────────────────────────────────

func _build_rows() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", ROW_GAP)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.position = Vector2(LEFT_MARGIN, TOP_MARGIN)
	add_child(vbox)

	_relic_row = HBoxContainer.new()
	_relic_row.add_theme_constant_override("separation", ICON_GAP)
	_relic_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_relic_row)

	_ability_row = HBoxContainer.new()
	_ability_row.add_theme_constant_override("separation", ICON_GAP)
	_ability_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_ability_row)

	_orb_row = HBoxContainer.new()
	_orb_row.add_theme_constant_override("separation", ICON_GAP)
	_orb_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_orb_row)

func _build_tooltip() -> void:
	_tooltip_panel              = PanelContainer.new()
	_tooltip_panel.visible      = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.z_index      = 100

	var style                        := StyleBoxFlat.new()
	style.bg_color                    = Color(0.07, 0.07, 0.1, 0.95)
	style.border_width_left           = 1
	style.border_width_right          = 1
	style.border_width_top            = 1
	style.border_width_bottom         = 1
	style.border_color                = Color(0.3, 0.3, 0.4, 1.0)
	style.corner_radius_top_left      = 4
	style.corner_radius_top_right     = 4
	style.corner_radius_bottom_left   = 4
	style.corner_radius_bottom_right  = 4
	style.content_margin_left         = 8
	style.content_margin_right        = 8
	style.content_margin_top          = 6
	style.content_margin_bottom       = 6
	_tooltip_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.add_child(vbox)

	_tooltip_name = Label.new()
	_tooltip_name.add_theme_font_size_override("font_size", 13)
	_tooltip_name.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_tooltip_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_tooltip_name)

	_tooltip_desc = Label.new()
	_tooltip_desc.add_theme_font_size_override("font_size", 11)
	_tooltip_desc.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 1.0))
	_tooltip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_desc.custom_minimum_size = Vector2(180, 0)
	_tooltip_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_tooltip_desc)

	add_child(_tooltip_panel)

# ── rebuild ───────────────────────────────────────────────────────────────────

func _rebuild_all() -> void:
	_rebuild_relics()
	_rebuild_abilities()

func _rebuild_abilities() -> void:
	for c in _ability_row.get_children():
		c.queue_free()
	if _player == null:
		return
	var inventory := _player.get_node("RunInventory")
	for ability: AbilityData in inventory.abilities:
		_ability_row.add_child(_make_ability_icon(ability))

func _rebuild_relics() -> void:
	for c in _relic_row.get_children():
		c.queue_free()
	if _player == null:
		return
	var inventory := _player.get_node("RunInventory")
	for relic: RelicData in inventory.relics:
		var qty: int = inventory.get_relic_quantity(relic)
		var tint: Color = Util.rarity_color(relic.rarity)
		_relic_row.add_child(_make_icon(relic.icon, relic.display_name, relic.description, qty, tint))


func _make_ability_icon(ability: AbilityData) -> Control:
	var tex: Texture2D = ability.icon
	var outer: int = ICON_SIZE + ICON_PADDING * 2

	# Use a Panel as root so it has real size and receives mouse events correctly
	var root := Panel.new()
	root.custom_minimum_size = Vector2(outer, outer)
	root.size                = Vector2(outer, outer)
	root.mouse_filter        = Control.MOUSE_FILTER_STOP
	root.clip_contents       = false

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color                  = Color(0.08, 0.08, 0.12, 0.85)
	bg_style.set_border_width_all(1)
	bg_style.border_color              = Color(0.3, 0.35, 0.5, 0.8)
	bg_style.corner_radius_top_left    = 4
	bg_style.corner_radius_top_right   = 4
	bg_style.corner_radius_bottom_left = 4
	bg_style.corner_radius_bottom_right = 4
	root.add_theme_stylebox_override("panel", bg_style)

	if tex != null:
		var img          := TextureRect.new()
		img.texture       = tex
		img.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.anchor_right  = 1.0
		img.anchor_bottom = 1.0
		img.offset_left   = ICON_PADDING
		img.offset_top    = ICON_PADDING
		img.offset_right  = -ICON_PADDING
		img.offset_bottom = -ICON_PADDING
		img.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		root.add_child(img)

	# Level badge — bottom-right, only shown when level > 0
	var level_label := Label.new()
	level_label.text = "L%d" % ability.level if ability.level > 0 else ""
	level_label.add_theme_font_size_override("font_size", 10)
	level_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4, 1.0))
	level_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	level_label.add_theme_constant_override("shadow_offset_x", 1)
	level_label.add_theme_constant_override("shadow_offset_y", 1)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level_label.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	level_label.anchor_right         = 1.0
	level_label.anchor_bottom        = 1.0
	level_label.offset_right         = -2.0
	level_label.offset_bottom        = -2.0
	level_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	root.add_child(level_label)

	# Tooltip — position is set immediately on enter, no await needed
	var ability_ref: AbilityData = ability
	root.mouse_entered.connect(func():
		_tooltip_name.text     = ability_ref.display_name
		_tooltip_desc.text     = ability_ref.description
		_tooltip_panel.visible = true
		_tooltip_panel.position = root.global_position + Vector2(0, outer + 4)
	)
	root.mouse_exited.connect(func():
		_tooltip_panel.visible = false
	)

	return root

func _make_icon(tex: Texture2D, iname: String, desc: String, qty: int, tint: Color) -> Control:
	var sz: int = ICON_SIZE
	if tex != null:
		sz = maxi(tex.get_width(), tex.get_height())

	var outer: int = sz + ICON_PADDING * 2

	var root := Control.new()
	root.custom_minimum_size = Vector2(outer, outer)
	root.mouse_filter        = Control.MOUSE_FILTER_STOP
	root.clip_contents       = false

	var bg_expand: int = ICON_PADDING * 4
	var bg_size := Vector2(outer + bg_expand * 2, outer + bg_expand * 2)
	var bg         := ColorRect.new()
	bg.size         = bg_size
	bg.position     = Vector2(-bg_expand, -bg_expand)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_mat          := ShaderMaterial.new()
	bg_mat.shader        = load("res://scripts/ui/icon_bg.gdshader") as Shader
	bg_mat.set_shader_parameter("color",   ICON_BG)
	bg_mat.set_shader_parameter("falloff", 2.5)
	bg.material          = bg_mat
	root.add_child(bg)

	if tex != null:
		var img           := TextureRect.new()
		img.texture        = tex
		img.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.size           = Vector2(sz, sz)
		img.position       = Vector2(ICON_PADDING, ICON_PADDING)
		img.modulate       = tint
		img.mouse_filter   = Control.MOUSE_FILTER_IGNORE
		root.add_child(img)

	if qty > 1:
		var badge := Label.new()
		badge.text = "x%d" % qty
		badge.add_theme_font_size_override("font_size", BADGE_FONT)
		badge.add_theme_color_override("font_color", BADGE_TEXT)
		badge.add_theme_constant_override("shadow_offset_x", 1)
		badge.add_theme_constant_override("shadow_offset_y", 1)
		badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
		badge.size       = Vector2(outer - 2, outer - 2)
		badge.position   = Vector2(1, 1)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(badge)

	root.mouse_entered.connect(func():
		_tooltip_name.text     = iname
		_tooltip_desc.text     = desc
		_tooltip_panel.visible = true
		await get_tree().process_frame
		var gp := root.global_position
		_tooltip_panel.position = Vector2(gp.x, gp.y + outer + 4)
	)
	root.mouse_exited.connect(func():
		_tooltip_panel.visible = false
	)

	return root

# ── helpers ───────────────────────────────────────────────────────────────────

func _on_inventory_changed(_a = null, _b = null) -> void:
	_rebuild_all()
