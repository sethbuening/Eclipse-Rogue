# level_up_screen.gd
# Add as a CanvasLayer node named "LevelUpScreen" in your HUD.
# Set process_mode to PROCESS_MODE_WHEN_PAUSED in the inspector.
extends CanvasLayer

signal upgrade_chosen(upgrade: LevelUpUpgrade)

const CARD_WIDTH:  float = 280.0
const CARD_HEIGHT: float = 340.0
const CARD_GAP:    float = 32.0
const CARD_RADIUS: float = 12.0

var _player:  CharacterBody2D = null
var _overlay: ColorRect
var _cards:   Array[PanelContainer] = []

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

	await get_tree().process_frame
	var vp_size  := get_viewport().get_visible_rect().size
	var total_w  := CARD_WIDTH * upgrades.size() + CARD_GAP * (upgrades.size() - 1)
	var start_x  := (vp_size.x - total_w) / 2.0
	var target_y := (vp_size.y - CARD_HEIGHT) / 2.0

	for i in upgrades.size():
		var upgrade: LevelUpUpgrade = upgrades[i]
		var card := _make_card(upgrade)
		card.position = Vector2(start_x + i * (CARD_WIDTH + CARD_GAP), target_y + 60.0)
		add_child(card)
		_cards.append(card)

		var tw := create_tween()
		tw.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
		tw.tween_property(card, "position:y", target_y, 0.22) \
			.set_delay(i * 0.07) \
			.set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)

func _make_card(upgrade: LevelUpUpgrade) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	panel.process_mode        = Node.PROCESS_MODE_WHEN_PAUSED
	# Make the whole card receive mouse input and show a pointer cursor
	panel.mouse_filter        = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

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
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
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

	# "Choose" hint label at the bottom instead of a button
	var hint_label := Label.new()
	hint_label.text                 = Util.rarity_name(upgrade.rarity).to_upper()
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_color", Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.75))
	hint_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	hint_label.custom_minimum_size  = Vector2(CARD_WIDTH - 32.0, 32.0)
	vbox.add_child(hint_label)

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

func _on_card_chosen(upgrade: LevelUpUpgrade) -> void:
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
	get_tree().paused = false
