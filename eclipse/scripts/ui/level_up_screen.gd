# level_up_screen.gd
# Add as a CanvasLayer node named "LevelUpScreen" in your HUD.
# Set process_mode to PROCESS_MODE_WHEN_PAUSED in the inspector.
extends CanvasLayer

signal upgrade_chosen(upgrade: LevelUpUpgrade)

const CARD_WIDTH:  float = 280.0
const CARD_HEIGHT: float = 340.0
const CARD_GAP:    float = 32.0
const CARD_RADIUS: float = 12.0

const COST_ICON_SIZE: float = 18.0

const COLOR_AFFORDABLE:   Color = Color(0.75, 0.95, 0.55, 1.0)
const COLOR_UNAFFORDABLE: Color = Color(0.95, 0.35, 0.35, 1.0)

# ── skip button ───────────────────────────────────────────────────────────────
const SKIP_MARGIN_X:  float = 32.0
const SKIP_MARGIN_Y:  float = 32.0
const SKIP_WIDTH:     float = 180.0
const SKIP_HEIGHT:    float = 44.0
const SKIP_RADIUS:    float = 10.0

var _player:  CharacterBody2D = null
var _overlay: ColorRect
var _cards:   Array[PanelContainer] = []
var _skip_button: PanelContainer = null

func _ready() -> void:
	layer        = 128
	visible      = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	_overlay               = ColorRect.new()
	_overlay.color         = Color(0.0, 0.0, 0.0, 0.0)
	_overlay.anchor_right  = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.process_mode  = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(_overlay)

var _chaining: bool = false

func show_upgrades(player: CharacterBody2D, upgrades: Array) -> void:
	_chaining  = true
	_player    = player
	visible    = true
	get_tree().paused = true

	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tween.tween_property(_overlay, "color", Color(0.0, 0.0, 0.0, 0.65), 0.25)

	for card in _cards:
		card.queue_free()
	_cards.clear()

	if _skip_button != null:
		_skip_button.queue_free()
		_skip_button = null

	# Build all cards first (hidden) so the engine can measure their sizes.
	for i in upgrades.size():
		var upgrade: LevelUpUpgrade = upgrades[i]
		var card := _make_card(upgrade)
		card.visible = false
		add_child(card)
		_cards.append(card)

	# Wait two frames: one for layout, one to be safe.
	await get_tree().process_frame
	await get_tree().process_frame

	var vp_size := get_viewport().get_visible_rect().size

	# Measure the widest card so all cards share the same width.
	var max_card_w: float = CARD_WIDTH
	for card in _cards:
		max_card_w = maxf(max_card_w, card.size.x)

	# Distribute cards with equal gaps, centred on screen.
	var n: int       = _cards.size()
	var total_w: float = max_card_w * n + CARD_GAP * (n - 1)
	# Clamp so cards never overflow the viewport; shrink gap if needed.
	var gap: float = CARD_GAP
	if total_w > vp_size.x - 32.0:
		total_w = vp_size.x - 32.0
		gap = (total_w - max_card_w * n) / maxf(n - 1, 1)

	var start_x  := (vp_size.x - total_w) / 2.0
	var target_y := (vp_size.y - CARD_HEIGHT) / 2.0

	for i in n:
		var card: PanelContainer = _cards[i]
		card.custom_minimum_size.x = max_card_w
		var dest_x: float = start_x + i * (max_card_w + gap)
		card.position = Vector2(dest_x, target_y + 60.0)
		card.visible  = true

		var tw := create_tween()
		tw.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
		tw.tween_property(card, "position:y", target_y, 0.22) \
			.set_delay(i * 0.07) \
			.set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)

	# ── skip button — bottom-right of the card area ──────────────────────────
	_skip_button = _make_skip_button()
	_skip_button.visible = false
	add_child(_skip_button)

	await get_tree().process_frame

	var card_area_right: float = start_x + total_w
	var card_area_bottom: float = target_y + CARD_HEIGHT
	var skip_target := Vector2(card_area_right - SKIP_WIDTH, card_area_bottom + SKIP_MARGIN_Y)
	_skip_button.position = skip_target + Vector2(0, 40.0)
	_skip_button.visible  = true

	var skip_tw := create_tween()
	skip_tw.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	skip_tw.tween_property(_skip_button, "position", skip_target, 0.22) \
		.set_delay(n * 0.07) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)

func _make_card(upgrade: LevelUpUpgrade) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	panel.process_mode        = Node.PROCESS_MODE_WHEN_PAUSED
	# Make the whole card receive mouse input and show a pointer cursor
	panel.mouse_filter        = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var inventory: Node  = _player.get_node("Inventory")
	var affordable: bool = upgrade.is_affordable(inventory)

	var rarity_col: Color = Util.rarity_color(upgrade.rarity)
	var rarity_dim: Color = Color(rarity_col.r * 0.5, rarity_col.g * 0.5, rarity_col.b * 0.5, 0.8)

	var style := StyleBoxFlat.new()
	style.bg_color                       = Color(0.10, 0.11, 0.15, 0.97)
	style.border_color                   = rarity_dim
	style.set_border_width_all(2)
	style.corner_radius_top_left         = CARD_RADIUS
	style.corner_radius_top_right        = CARD_RADIUS
	style.corner_radius_bottom_left      = CARD_RADIUS
	style.corner_radius_bottom_right     = CARD_RADIUS
	panel.add_theme_stylebox_override("panel", style)

	if not affordable:
		# Dim the whole card — unaffordable upgrades can't be selected.
		panel.modulate = Color(1.0, 1.0, 1.0, 0.55)
		panel.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	# VBox should not consume mouse events — the panel handles them
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var icon_wrap := CenterContainer.new()
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if upgrade.icon != null:
		var icon_tex          := TextureRect.new()
		icon_tex.texture       = upgrade.icon
		icon_tex.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_tex.custom_minimum_size = Vector2(64.0, 64.0)
		icon_tex.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		icon_wrap.add_child(icon_tex)
	else:
		var icon_placeholder      := ColorRect.new()
		icon_placeholder.color     = Color(0.0, 0.0, 0.0, 0.0)
		icon_placeholder.custom_minimum_size = Vector2(64.0, 64.0)
		icon_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_wrap.add_child(icon_placeholder)
	vbox.add_child(icon_wrap)

	var name_label                    := Label.new()
	name_label.text                    = upgrade.display_name
	name_label.horizontal_alignment    = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode           = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	name_label.custom_minimum_size     = Vector2(CARD_WIDTH - 24.0, 0.0)
	name_label.mouse_filter            = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var desc_label                    := Label.new()
	desc_label.text                    = upgrade.description
	desc_label.horizontal_alignment    = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode           = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", Color(0.65, 0.70, 0.80))
	desc_label.custom_minimum_size     = Vector2(CARD_WIDTH - 24.0, 0.0)
	desc_label.mouse_filter            = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)

	# ── ore cost row(s) ──────────────────────────────────────────────────────
	# One row per required metal: icon (or color swatch) + "owned / needed".
	if not upgrade.metal_cost.is_empty():
		for metal: MetalData in upgrade.metal_cost.keys():
			var needed: int = upgrade.metal_cost[metal]
			var owned:  int = inventory.get_metal_quantity(metal)
			var row := _make_cost_row(metal, owned, needed)
			vbox.add_child(row)
	else:
		# Free upgrades (e.g. the Skip option) get a small "Free" label so the
		# layout stays visually consistent with costed cards.
		var free_label := Label.new()
		free_label.text                 = "Free"
		free_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		free_label.add_theme_font_size_override("font_size", 13)
		free_label.add_theme_color_override("font_color", COLOR_AFFORDABLE)
		free_label.mouse_filter          = Control.MOUSE_FILTER_IGNORE
		free_label.custom_minimum_size   = Vector2(CARD_WIDTH - 32.0, 18.0)
		vbox.add_child(free_label)

	# "Choose" hint label at the bottom instead of a button
	var hint_label := Label.new()
	hint_label.text                 = Util.rarity_name(upgrade.rarity).to_upper()
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_color", Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.75))
	hint_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	hint_label.custom_minimum_size  = Vector2(CARD_WIDTH - 32.0, 32.0)
	vbox.add_child(hint_label)

	if affordable:
		# Hover: brighten border + background, brighten the hint text
		panel.mouse_entered.connect(func():
			style.border_color = rarity_col
			style.bg_color     = Color(0.15, 0.18, 0.28, 0.97)
			hint_label.add_theme_color_override("font_color", Color(rarity_col.r, rarity_col.g, rarity_col.b, 1.0))
		)
		panel.mouse_exited.connect(func():
			style.border_color = rarity_dim
			style.bg_color     = Color(0.10, 0.11, 0.15, 0.97)
			hint_label.add_theme_color_override("font_color", Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.75))
		)

		# Clicking anywhere on the card selects the upgrade
		panel.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton \
					and event.button_index == MOUSE_BUTTON_LEFT \
					and event.pressed:
				_on_card_chosen(upgrade)
		)

	return panel

## Builds a single "icon  owned / needed" row for the ore cost section.
## Text is colored green if the player can afford this metal's portion of
## the cost, red otherwise.
func _make_cost_row(metal: MetalData, owned: int, needed: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment       = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter    = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(CARD_WIDTH - 32.0, COST_ICON_SIZE)

	if metal.sprite_texture != null:
		var icon := TextureRect.new()
		icon.texture      = metal.sprite_texture
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(COST_ICON_SIZE, COST_ICON_SIZE)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	else:
		var swatch := ColorRect.new()
		swatch.color = Util.rarity_color(clampi(metal.rarity, 0, 4))
		swatch.custom_minimum_size = Vector2(COST_ICON_SIZE, COST_ICON_SIZE)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)

	var can_afford: bool = owned >= needed
	var label := Label.new()
	label.text = "%s  %d / %d" % [metal.display_name, owned, needed]
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", COLOR_AFFORDABLE if can_afford else COLOR_UNAFFORDABLE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	return row

func _on_card_chosen(upgrade: LevelUpUpgrade) -> void:
	var inventory: Node = _player.get_node("Inventory")
	if not upgrade.is_affordable(inventory):
		return
	upgrade.pay_cost(inventory)

	upgrade.apply(_player)
	_chaining = false
	emit_signal("upgrade_chosen", upgrade)
	if not _chaining:
		_dismiss()

## Builds the small "SKIP (+1 LUCK)" button shown bottom-left of the screen.
## Always free and always selectable — lets the player decline every
## ore-cost upgrade in favor of Prosperity (permanent Luck).
func _make_skip_button() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SKIP_WIDTH, SKIP_HEIGHT)
	panel.process_mode        = Node.PROCESS_MODE_WHEN_PAUSED
	panel.mouse_filter        = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var rarity_col: Color = Util.rarity_color(Util.Rarity.COMMON)
	var rarity_dim: Color = Color(rarity_col.r * 0.5, rarity_col.g * 0.5, rarity_col.b * 0.5, 0.8)

	var style := StyleBoxFlat.new()
	style.bg_color                   = Color(0.10, 0.11, 0.15, 0.92)
	style.border_color               = rarity_dim
	style.set_border_width_all(2)
	style.corner_radius_top_left     = SKIP_RADIUS
	style.corner_radius_top_right    = SKIP_RADIUS
	style.corner_radius_bottom_left  = SKIP_RADIUS
	style.corner_radius_bottom_right = SKIP_RADIUS
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	var amount: String = UpgradeSkipProsperity._format_amount(UpgradeSkipProsperity.PROSPERITY_AMOUNT)
	label.text                 = "SKIP (+%s LUCK)" % amount
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.85, 0.90, 0.95))
	label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)

	panel.mouse_entered.connect(func():
		style.border_color = rarity_col
		style.bg_color     = Color(0.16, 0.18, 0.24, 0.95)
	)
	panel.mouse_exited.connect(func():
		style.border_color = rarity_dim
		style.bg_color     = Color(0.10, 0.11, 0.15, 0.92)
	)

	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton \
				and event.button_index == MOUSE_BUTTON_LEFT \
				and event.pressed:
			_on_skip_chosen()
	)

	return panel

func _on_skip_chosen() -> void:
	var upgrade := UpgradeSkipProsperity.build()
	upgrade.apply(_player)
	_chaining = false
	emit_signal("upgrade_chosen", upgrade)
	if not _chaining:
		_dismiss()

func _dismiss() -> void:
	visible        = false
	_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	for card in _cards:
		card.queue_free()
	_cards.clear()
	if _skip_button != null:
		_skip_button.queue_free()
		_skip_button = null
	get_tree().paused = false
