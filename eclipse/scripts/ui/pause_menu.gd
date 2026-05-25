extends Control

# ============================================================ scene: PauseMenu
# Attach to a Control child of your HUD/game scene.
# Set process_mode = WHEN_PAUSED on this node so it ticks while the tree is paused.
#
# Usage:
#   pause_menu.open()    — call from player/game when "pause" action fires
#   pause_menu.resumed   — connect to resume gameplay
#
# The pause menu switches the Steam Input action set to MenuControls while
# open and restores InGameControls on close.

const FONT_TITLE:    String = "res://assets/fonts/Cinzel-Bold.ttf"
const FONT_MENU:     String = "res://assets/fonts/Cinzel-Regular.ttf"
const FONT_SUBTITLE: String = "res://assets/fonts/JosefinSans-Light.ttf"

const C_BG:      Color = Color(0.02, 0.01, 0.04, 0.82)
const C_TITLE:   Color = Color("#f0dfa0")
const C_MENU:    Color = Color("#c8a87a")
const C_HOVER:   Color = Color("#f5d78e")
const C_DIVIDER: Color = Color("#3a2e1e")

signal resumed

var _options_menu: Control = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	_build()

func _build() -> void:
	# ── Dark overlay ────────────────────────────────────────────────────────
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	add_child(bg)

	# ── Centered panel ───────────────────────────────────────────────────────
	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.add_theme_constant_override("separation", 8)
	panel.custom_minimum_size = Vector2(260, 0)
	add_child(panel)

	# Title
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_override("font", load(FONT_TITLE))
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", C_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	# Divider
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", C_DIVIDER)
	divider.custom_minimum_size = Vector2(0, 16)
	panel.add_child(divider)

	var items: Array[Dictionary] = [
		{"label": "Resume",       "cb": _on_resume},
		{"label": "Options",      "cb": _on_options},
		{"label": "Quit to Menu", "cb": _on_quit_to_menu},
	]
	for item in items:
		var btn := _menu_btn(item["label"])
		btn.pressed.connect(item["cb"])
		panel.add_child(btn)

	# ── Options overlay ──────────────────────────────────────────────────────
	_options_menu = preload("res://scenes/ui/options_menu.tscn").instantiate()
	_options_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options_menu.visible = false
	_options_menu.closed.connect(_on_options_closed)
	add_child(_options_menu)

# ----------------------------------------------------------------- factory

func _menu_btn(label_text: String) -> Button:
	var btn := Button.new()
	btn.text                = label_text
	btn.flat                = true
	btn.custom_minimum_size = Vector2(260, 40)
	btn.alignment           = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_theme_font_override("font", load(FONT_MENU))
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color",         C_MENU)
	btn.add_theme_color_override("font_hover_color",   C_HOVER)
	btn.add_theme_color_override("font_focus_color",   C_HOVER)
	btn.add_theme_color_override("font_pressed_color", C_HOVER)
	btn.add_theme_stylebox_override("normal",  StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover",   StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())
	return btn

# ================================================================= public API

func open() -> void:
	visible = true
	get_tree().paused = true
	# Switch Steam Input to menu controls while paused.
	SteamInputManager.set_action_set(SteamInputManager.ACTION_SET_MENU)

func close() -> void:
	visible = false
	get_tree().paused = false
	# Restore in-game controls.
	SteamInputManager.set_action_set(SteamInputManager.ACTION_SET_INGAME)

# ----------------------------------------------------------------- callbacks

func _on_resume() -> void:
	close()
	resumed.emit()

func _on_options() -> void:
	_options_menu.visible = true
	_options_menu.open()

func _on_options_closed() -> void:
	_options_menu.visible = false
	# Options may have changed the action set; restore menu set since we're
	# still in the pause menu.
	SteamInputManager.set_action_set(SteamInputManager.ACTION_SET_MENU)

func _on_quit_to_menu() -> void:
	get_tree().paused = false
	# Main menu will set its own action set in _ready().
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# ----------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_just_pressed("pause"):
		if _options_menu.visible:
			_options_menu.request_close()
		else:
			_on_resume()
		get_viewport().set_input_as_handled()
	elif event.is_action_just_pressed("cancel"):
		if _options_menu.visible:
			_options_menu.request_close()
		get_viewport().set_input_as_handled()
