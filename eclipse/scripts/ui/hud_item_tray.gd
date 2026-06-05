# hud_item_tray.gd
# Displays acquired upgrades and relics as icon rows in the top-left corner.
#
# Setup:
#   1. Add a Control node anywhere in your HUD scene, attach this script.
#   2. That's it — it finds the player via the "player" group automatically.
#      No wiring in game.gd required.

extends Control

# ── tunables ──────────────────────────────────────────────────────────────────

const ICON_SIZE:    int   = 48     # fallback size when no texture is assigned
const ICON_GAP:     int   = 10
const ROW_GAP:      int   = 8
const TOP_MARGIN:   int   = 20
const LEFT_MARGIN:  int   = 20
const ICON_PADDING: int   = 6      # padding around icon inside the bg rect
const BADGE_FONT:   int   = 16     # stack count label font size

const RELIC_TINT:   Color = Color(1.0,  0.85, 0.3,  1.0)
const UPGRADE_TINT: Color = Color(0.45, 0.7,  1.0,  1.0)
const BADGE_TEXT:   Color = Color(1.0,  1.0,  1.0,  1.0)
const ICON_BG:      Color = Color(0.0, 0.0, 0.0, 0.0)

# ── internal ──────────────────────────────────────────────────────────────────

var _player:        CharacterBody2D = null
var _relic_row:     HBoxContainer   = null
var _upgrade_row:   HBoxContainer   = null
var _tooltip_panel: PanelContainer  = null
var _tooltip_name:  Label           = null
var _tooltip_desc:  Label           = null

var _last_upgrade_fingerprint: Array = []

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

	_player.get_node("Inventory").relic_added.connect(_on_inventory_changed)
	_player.get_node("Inventory").relic_removed.connect(_on_inventory_changed)
	_rebuild_all()

func _process(_delta: float) -> void:
	if _player == null:
		return
	var fp := _upgrade_fingerprint()
	if fp != _last_upgrade_fingerprint:
		_last_upgrade_fingerprint = fp
		_rebuild_upgrades()

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

	_upgrade_row = HBoxContainer.new()
	_upgrade_row.add_theme_constant_override("separation", ICON_GAP)
	_upgrade_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_upgrade_row)

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
	_rebuild_upgrades()

func _rebuild_relics() -> void:
	for c in _relic_row.get_children():
		c.queue_free()
	if _player == null:
		return
	var inventory := _player.get_node("Inventory")
	for relic: RelicData in inventory.relics:
		var qty: int = inventory.get_relic_quantity(relic)
		var tint: Color = Util.rarity_color(relic.rarity)
		_relic_row.add_child(_make_icon(relic.icon, relic.display_name, relic.description, qty, tint))

func _rebuild_upgrades() -> void:
	for c in _upgrade_row.get_children():
		c.queue_free()
	if _player == null:
		return

	var counts: Dictionary = {}
	for upgrade: LevelUpUpgrade in _player.acquired_upgrades:
		var key := upgrade.display_name
		if counts.has(key):
			counts[key]["count"] += 1
		else:
			counts[key] = { "upgrade": upgrade, "count": 1 }

	for key in counts:
		var entry   = counts[key]
		var upgrade: LevelUpUpgrade = entry["upgrade"]
		var qty:     int            = entry["count"]
		var tint: Color = Util.rarity_color(upgrade.rarity)
		_upgrade_row.add_child(_make_icon(upgrade.icon, upgrade.display_name, upgrade.description, qty, tint))

# ── icon factory ──────────────────────────────────────────────────────────────

func _make_icon(tex: Texture2D, iname: String, desc: String, qty: int, tint: Color) -> Control:
	var sz: int = ICON_SIZE
	if tex != null:
		sz = maxi(tex.get_width(), tex.get_height())

	var outer: int = sz + ICON_PADDING * 2

	var root := Control.new()
	root.custom_minimum_size = Vector2(outer, outer)
	root.mouse_filter        = Control.MOUSE_FILTER_STOP
	root.clip_contents       = false

	# Vignette background — sized generously beyond the icon, centred on it
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

	# Texture centred inside padding
	if tex != null:
		var img           := TextureRect.new()
		img.texture        = tex
		img.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.size           = Vector2(sz, sz)
		img.position       = Vector2(ICON_PADDING, ICON_PADDING)
		img.modulate       = tint
		img.mouse_filter   = Control.MOUSE_FILTER_IGNORE
		root.add_child(img)

	# Stack badge — larger font, bottom-right corner
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

	# Tooltip on hover
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

func _upgrade_fingerprint() -> Array:
	if _player == null:
		return []
	var ids: Array = []
	for u: LevelUpUpgrade in _player.acquired_upgrades:
		ids.append(u.display_name)
	return ids

func _on_inventory_changed(_a = null, _b = null) -> void:
	_rebuild_relics()
