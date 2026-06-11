extends CanvasLayer

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

const _STICK_DEAD: float = 0.4

signal resumed

# ── controller navigation ────────────────────────────────────────────────────
var _ctrl_index:       int        = 0   # currently focused button index
var _buttons:          Array      = []  # ordered list of menu Buttons
var _stick_was_active: Dictionary = {}  # axis index → bool (debounce)


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

	# ── Full-viewport anchor so children use the screen coordinate space ────
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	# ── Panel: anchored to screen centre, offsets extend outward symmetrically
	const HALF_W: float = 130.0   # half of 260 px width
	const HALF_H: float = 80.0    # approximate half-height (title + divider + 2 btns)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 8)
	panel.custom_minimum_size = Vector2(260, 0)

	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -HALF_W
	panel.offset_right  =  HALF_W
	panel.offset_top    = -HALF_H
	panel.offset_bottom =  HALF_H

	# Let the container grow downward from the top offset without shrinking
	panel.grow_vertical   = Control.GROW_DIRECTION_END
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH

	anchor.add_child(panel)

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
		{"label": "Resume", "cb": _on_resume},
		{"label": "Quit",   "cb": _on_quit},
	]
	_buttons.clear()
	for item in items:
		var btn := _menu_btn(item["label"])
		btn.pressed.connect(item["cb"])
		panel.add_child(btn)
		_buttons.append(btn)

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
	_ctrl_index = 0
	_ctrl_refresh_focus()

func close() -> void:
	visible = false
	get_tree().paused = false

# ----------------------------------------------------------------- callbacks

func _on_resume() -> void:
	close()
	resumed.emit()

func _on_quit() -> void:
	get_tree().paused = false
	get_tree().quit()

# ================================================================= input

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	# ── Non-joypad events (keyboard / mouse) ───────────────────────────────
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		if event.is_action_pressed("pause"):
			_on_resume()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventJoypadButton and not event.is_pressed():
		return

	# Analogue stick dead-zone debounce (mirrors forge_ui / orb_graph_menu)
	if event is InputEventJoypadMotion:
		var axis:   int  = (event as InputEventJoypadMotion).axis
		var active: bool = absf(event.get_axis_value()) > _STICK_DEAD
		if not active:
			_stick_was_active[axis] = false
			return
		if _stick_was_active.get(axis, false):
			return
		_stick_was_active[axis] = true

	# Navigation
	if event.is_action_pressed("ui_navigate_up"):
		_ctrl_navigate(-1)
	elif event.is_action_pressed("ui_navigate_down"):
		_ctrl_navigate(1)
	elif event.is_action_pressed("confirm"):
		_ctrl_confirm()
	elif event.is_action_pressed("cancel"):
		_on_resume()

	get_viewport().set_input_as_handled()

# ----------------------------------------------------------------- controller helpers

func _ctrl_navigate(dir: int) -> void:
	if _buttons.is_empty():
		return
	_ctrl_index = (_ctrl_index + dir + _buttons.size()) % _buttons.size()
	_ctrl_refresh_focus()

func _ctrl_confirm() -> void:
	if _buttons.is_empty():
		return
	_buttons[_ctrl_index].emit_signal("pressed")

func _ctrl_refresh_focus() -> void:
	for i in _buttons.size():
		var btn: Button = _buttons[i]
		if i == _ctrl_index:
			btn.grab_focus()
		else:
			btn.release_focus()
