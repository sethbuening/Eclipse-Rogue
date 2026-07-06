# level_up_screen.gd
extends CanvasLayer

signal upgrade_chosen(upgrade: LevelUpUpgrade)

const CARD_WIDTH:     float = 300.0
const CARD_HEIGHT:    float = 380.0
const CARD_GAP:       float = 28.0
const CARD_RADIUS:    float = 12.0
const TIER_BTN_H:     float = 52.0
const COST_ICON_SIZE: float = 16.0

const SKIP_WIDTH:  float = 180.0
const SKIP_HEIGHT: float = 44.0
const SKIP_RADIUS: float = 10.0
const SKIP_MARGIN_Y: float = 16.0

const COLOR_AFFORDABLE:   Color = Color(0.75, 0.95, 0.55, 1.0)
const COLOR_UNAFFORDABLE: Color = Color(0.95, 0.35, 0.35, 1.0)

const TIER_LABELS:   Array = ["Free",      "Enhanced",   "Supercharged"]
const TIER_COLORS:   Array = [Color(0.65, 0.70, 0.80), Color(0.95, 0.80, 0.30), Color(0.95, 0.45, 0.20)]

var _player:      CharacterBody2D   = null
var _overlay:     ColorRect
var _cards:       Array[PanelContainer] = []
var _skip_button: PanelContainer    = null
var _chaining:    bool              = false

func _ready() -> void:
	layer        = 128
	visible      = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_overlay               = ColorRect.new()
	_overlay.color         = Color(0, 0, 0, 0)
	_overlay.anchor_right  = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.process_mode  = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(_overlay)

## upgrades: Array of Array[LevelUpUpgrade] — each inner array is 3 tiers for one slot.
func show_upgrades(player: CharacterBody2D, upgrades: Array) -> void:
	_chaining = true
	_player   = player
	visible   = true
	get_tree().paused = true

	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tween.tween_property(_overlay, "color", Color(0, 0, 0, 0.65), 0.25)

	for card in _cards: card.queue_free()
	_cards.clear()
	if _skip_button != null:
		_skip_button.queue_free()
		_skip_button = null

	for tiers in upgrades:
		var card := _make_card(tiers as Array)
		card.visible = false
		add_child(card)
		_cards.append(card)

	await get_tree().process_frame
	await get_tree().process_frame

	var vp   := get_viewport().get_visible_rect().size
	var n    := _cards.size()
	var max_w: float = CARD_WIDTH
	for card in _cards: max_w = maxf(max_w, card.size.x)

	var gap: float     = CARD_GAP
	var total_w: float = max_w * n + gap * (n - 1)
	if total_w > vp.x - 32.0:
		total_w = vp.x - 32.0
		gap = (total_w - max_w * n) / maxf(n - 1, 1)

	var start_x  := (vp.x - total_w) / 2.0
	var target_y := (vp.y - CARD_HEIGHT) / 2.0

	for i in n:
		var card: PanelContainer = _cards[i]
		card.custom_minimum_size.x = max_w
		card.position = Vector2(start_x + i * (max_w + gap), target_y + 60.0)
		card.visible  = true
		var tw := create_tween()
		tw.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
		tw.tween_property(card, "position:y", target_y, 0.22) \
			.set_delay(i * 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_skip_button = _make_skip_button()
	_skip_button.visible = false
	add_child(_skip_button)
	await get_tree().process_frame

	var skip_target := Vector2(start_x + total_w - SKIP_WIDTH, target_y + CARD_HEIGHT + SKIP_MARGIN_Y)
	_skip_button.position = skip_target + Vector2(0, 40.0)
	_skip_button.visible  = true
	var stw := create_tween()
	stw.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	stw.tween_property(_skip_button, "position", skip_target, 0.22) \
		.set_delay(n * 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ── card: one column per upgrade slot, 3 tier buttons at the bottom ───────────

func _make_card(tiers: Array) -> PanelContainer:
	# Use tier 0 (free) for display name / icon / rarity — shared across tiers.
	var base: LevelUpUpgrade = tiers[0]
	var rarity_col: Color    = Util.rarity_color(base.rarity)
	var rarity_dim: Color    = Color(rarity_col.r * 0.5, rarity_col.g * 0.5, rarity_col.b * 0.5, 0.8)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	panel.process_mode        = Node.PROCESS_MODE_WHEN_PAUSED
	panel.mouse_filter        = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color           = Color(0.10, 0.11, 0.15, 0.97)
	style.border_color       = rarity_dim
	style.set_border_width_all(2)
	style.corner_radius_top_left    = CARD_RADIUS
	style.corner_radius_top_right   = CARD_RADIUS
	style.corner_radius_bottom_left = CARD_RADIUS
	style.corner_radius_bottom_right = CARD_RADIUS
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	# Icon
	var icon_wrap := CenterContainer.new()
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if base.icon != null:
		var tex := TextureRect.new()
		tex.texture      = base.icon
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(56.0, 56.0)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_wrap.add_child(tex)
	else:
		var ph := ColorRect.new()
		ph.color = Color(0, 0, 0, 0)
		ph.custom_minimum_size = Vector2(56.0, 56.0)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_wrap.add_child(ph)
	vbox.add_child(icon_wrap)

	# Name
	var name_lbl := Label.new()
	name_lbl.text               = base.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode      = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	name_lbl.custom_minimum_size = Vector2(CARD_WIDTH - 24.0, 0.0)
	name_lbl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	# Rarity badge
	var rarity_lbl := Label.new()
	rarity_lbl.text               = Util.rarity_name(base.rarity).to_upper()
	rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_lbl.add_theme_font_size_override("font_size", 12)
	rarity_lbl.add_theme_color_override("font_color", Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.75))
	rarity_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(rarity_lbl)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)

	# 3 tier buttons
	var run_inv: RunInventory = _player.get_node("RunInventory")
	for t in tiers.size():
		var upgrade: LevelUpUpgrade = tiers[t]
		var btn := _make_tier_button(upgrade, t, run_inv)
		vbox.add_child(btn)

	return panel

func _make_tier_button(upgrade: LevelUpUpgrade, tier_idx: int, run_inv: RunInventory) -> PanelContainer:
	var affordable: bool  = upgrade.is_affordable(run_inv)
	var tcol: Color       = TIER_COLORS[tier_idx]
	var tcol_dim: Color   = Color(tcol.r * 0.4, tcol.g * 0.4, tcol.b * 0.4, 0.9)

	var btn := PanelContainer.new()
	btn.custom_minimum_size = Vector2(CARD_WIDTH - 16.0, TIER_BTN_H)
	btn.process_mode        = Node.PROCESS_MODE_WHEN_PAUSED
	btn.mouse_filter        = Control.MOUSE_FILTER_STOP
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if affordable \
		else Control.CURSOR_FORBIDDEN

	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.08, 0.09, 0.13, 0.95)
	style.border_color = tcol_dim if affordable else Color(0.3, 0.3, 0.3, 0.5)
	style.set_border_width_all(1)
	style.corner_radius_top_left    = 6
	style.corner_radius_top_right   = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("panel", style)
	if not affordable:
		btn.modulate = Color(1, 1, 1, 0.45)

	var col := VBoxContainer.new()
	col.alignment     = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	btn.add_child(col)

	# Tier label row
	var header_row := HBoxContainer.new()
	header_row.alignment    = BoxContainer.ALIGNMENT_CENTER
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_theme_constant_override("separation", 8)
	col.add_child(header_row)

	var tier_lbl := Label.new()
	tier_lbl.text = TIER_LABELS[tier_idx]
	tier_lbl.add_theme_font_size_override("font_size", 13)
	tier_lbl.add_theme_color_override("font_color", tcol if affordable else Color(0.5, 0.5, 0.5))
	tier_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(tier_lbl)

	# Cost display inline in header
	if upgrade.item_cost.is_empty():
		var free_lbl := Label.new()
		free_lbl.text = "· Free"
		free_lbl.add_theme_font_size_override("font_size", 12)
		free_lbl.add_theme_color_override("font_color", COLOR_AFFORDABLE)
		free_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header_row.add_child(free_lbl)
	else:
		for item: ItemData in upgrade.item_cost:
			var needed: int  = upgrade.item_cost[item]
			var owned: int   = run_inv.get_quantity(item)
			var cost_row     := _make_cost_row(item, owned, needed)
			header_row.add_child(cost_row)

	# Stat summary (first line of description, or whole if short)
	var stat_lines: Array = upgrade.description.split("\n")
	# Show lines that are stat deltas (contain ": +"/": -"), skip tier/cost lines
	var shown: Array[String] = []
	for line: String in stat_lines:
		if ": +" in line or ": -" in line:
			shown.append(line)
	if not shown.is_empty():
		var stat_lbl := Label.new()
		stat_lbl.text               = "\n".join(shown)
		stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stat_lbl.add_theme_font_size_override("font_size", 11)
		stat_lbl.add_theme_color_override("font_color", Color(0.65, 0.70, 0.80, 0.9))
		stat_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(stat_lbl)

	if affordable:
		btn.mouse_entered.connect(func():
			style.border_color = tcol
			style.bg_color     = Color(0.14, 0.16, 0.24, 0.97)
		)
		btn.mouse_exited.connect(func():
			style.border_color = tcol_dim
			style.bg_color     = Color(0.08, 0.09, 0.13, 0.95)
		)
		btn.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton \
					and event.button_index == MOUSE_BUTTON_LEFT \
					and event.pressed:
				_on_tier_chosen(upgrade)
		)

	return btn

func _make_cost_row(item: ItemData, owned: int, needed: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment    = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)

	if item.icon != null:
		var tex := TextureRect.new()
		tex.texture      = item.icon
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(COST_ICON_SIZE, COST_ICON_SIZE)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tex)
	else:
		var swatch := ColorRect.new()
		swatch.color = item.tint
		swatch.custom_minimum_size = Vector2(COST_ICON_SIZE, COST_ICON_SIZE)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)

	var lbl := Label.new()
	lbl.text = "%d/%d %s" % [owned, needed, item.display_name]
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", COLOR_AFFORDABLE if owned >= needed else COLOR_UNAFFORDABLE)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	return row

func _on_tier_chosen(upgrade: LevelUpUpgrade) -> void:
	var run_inv: RunInventory = _player.get_node("RunInventory")
	if not upgrade.is_affordable(run_inv):
		return
	upgrade.pay_cost(run_inv)
	upgrade.apply(_player)
	_chaining = false
	upgrade_chosen.emit(upgrade)
	if not _chaining:
		_dismiss()

func _make_skip_button() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SKIP_WIDTH, SKIP_HEIGHT)
	panel.process_mode        = Node.PROCESS_MODE_WHEN_PAUSED
	panel.mouse_filter        = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var rarity_col: Color = Util.rarity_color(Util.Rarity.COMMON)
	var rarity_dim: Color = Color(rarity_col.r * 0.5, rarity_col.g * 0.5, rarity_col.b * 0.5, 0.8)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.15, 0.92)
	style.border_color = rarity_dim
	style.set_border_width_all(2)
	style.corner_radius_top_left    = SKIP_RADIUS
	style.corner_radius_top_right   = SKIP_RADIUS
	style.corner_radius_bottom_left = SKIP_RADIUS
	style.corner_radius_bottom_right = SKIP_RADIUS
	panel.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	var amt: String = UpgradeSkipProsperity._format_amount(UpgradeSkipProsperity.PROSPERITY_AMOUNT)
	lbl.text               = "SKIP (+%s LUCK)" % amt
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.95))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)

	panel.mouse_entered.connect(func(): style.border_color = rarity_col; style.bg_color = Color(0.16, 0.18, 0.24, 0.95))
	panel.mouse_exited.connect(func(): style.border_color = rarity_dim;  style.bg_color = Color(0.10, 0.11, 0.15, 0.92))
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_on_skip_chosen()
	)
	return panel

func _on_skip_chosen() -> void:
	var upgrade := UpgradeSkipProsperity.build()
	upgrade.apply(_player)
	_chaining = false
	upgrade_chosen.emit(upgrade)
	if not _chaining:
		_dismiss()

func _dismiss() -> void:
	visible        = false
	_overlay.color = Color(0, 0, 0, 0)
	for card in _cards: card.queue_free()
	_cards.clear()
	if _skip_button != null:
		_skip_button.queue_free()
		_skip_button = null
	get_tree().paused = false
