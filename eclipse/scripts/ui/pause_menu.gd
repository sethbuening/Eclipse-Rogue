# Pause menu — intentionally kept minimal (no terminal/CRT treatment for now).
# If a terminal makeover gets added later, keep it scoped to _build()/_make_btn()
# below so it can be ripped out cleanly without touching input/focus logic.
extends CanvasLayer

# Sci-fi font recommendations (drop-ins for Cinzel):
#   Title:   "Orbitron"  (geometric, NASA-esque)      → res://assets/fonts/Orbitron-Bold.ttf
#   Menu:    "Rajdhani"  (techy, military feel)        → res://assets/fonts/Rajdhani-SemiBold.ttf
#   UI/body: "Share Tech Mono" (monospace terminal)    → res://assets/fonts/ShareTechMono-Regular.ttf
#
# Using Cinzel for now until fonts are swapped in.

const FONT_TITLE: String = "res://assets/fonts/Orbitron-Bold.ttf"
const FONT_MENU:  String = "res://assets/fonts/Rajdhani-SemiBold.ttf"

const C_BG:      Color = Color(0.01, 0.03, 0.05, 0.88)
const C_TITLE:   Color = Color("#a0e8f0")
const C_MENU:    Color = Color("#7ac8d8")
const C_HOVER:   Color = Color("#e0f8ff")
const C_DIVIDER: Color = Color("#0e2a38")

const _STICK_DEAD: float = 0.4

signal resumed

var _ctrl_index: int = 0
var _buttons: Array = []
var _stick_was_active: Dictionary = {}
var _settings_menu: Control = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	_build()

func _build() -> void:
	# Dim background
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	add_child(bg)

	# CenterContainer — reliable centering, no manual anchor math
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 8)
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	# Title
	var title := Label.new()
	title.text = "// PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", load(FONT_TITLE))
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", C_TITLE)
	panel.add_child(title)

	# Divider
	var div := HSeparator.new()
	div.add_theme_color_override("color", C_DIVIDER)
	div.custom_minimum_size = Vector2(0, 16)
	panel.add_child(div)

	# Buttons
	for item in [
		{"label": "RESUME",  "cb": _on_resume},
		{"label": "SETTINGS", "cb": _on_settings},
		{"label": "QUIT",    "cb": _on_quit},
	]:
		var btn := _make_btn(item["label"])
		btn.pressed.connect(item["cb"])
		panel.add_child(btn)
		var idx: int = _buttons.size()
		# Bug fix: mouse hover never updated _ctrl_index, so after touching a
		# button with the mouse, keyboard/controller "confirm" would still
		# fire whatever button was selected last via _ctrl_navigate instead
		# of the one actually focused/hovered. Keep both input methods in sync.
		btn.mouse_entered.connect(func(): _ctrl_index = idx; btn.grab_focus())
		btn.focus_entered.connect(func(): _ctrl_index = idx)
		_buttons.append(btn)

	# Options overlay — child of the CanvasLayer so it covers everything
	_settings_menu = preload("res://scenes/ui/settings_menu.tscn").instantiate()
	_settings_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_menu.visible = false
	_settings_menu.closed.connect(_on_settings_closed)
	add_child(_settings_menu)

func _make_btn(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.flat = true
	btn.custom_minimum_size = Vector2(420, 58)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_theme_font_override("font", load(FONT_MENU))
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color",         C_MENU)
	btn.add_theme_color_override("font_hover_color",   C_HOVER)
	btn.add_theme_color_override("font_focus_color",   C_HOVER)
	btn.add_theme_color_override("font_pressed_color", C_HOVER)
	for s in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	return btn

func open() -> void:
	visible = true
	get_tree().paused = true
	_ctrl_index = 0
	_ctrl_refresh_focus()

func close() -> void:
	visible = false
	get_tree().paused = false

func _on_resume() -> void:
	%Player._pause_consumed = true
	close()
	resumed.emit()

func _on_settings() -> void:
	_settings_menu.visible = true
	_settings_menu.open()

func _on_settings_closed() -> void:
	_settings_menu.visible = false
	_ctrl_refresh_focus()

func _on_quit() -> void:
	get_tree().paused = false
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _settings_menu and _settings_menu.visible:
		return
	if event.is_action_pressed("pause"):
		_on_resume()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadMotion:
		var axis: int = event.axis
		var active: bool = absf(event.get_axis_value()) > _STICK_DEAD
		if not active:
			_stick_was_active[axis] = false
			return
		if _stick_was_active.get(axis, false):
			return
		_stick_was_active[axis] = true
	elif event is InputEventJoypadButton and not event.is_pressed():
		return
	if   event.is_action_pressed("ui_navigate_up"):   _ctrl_navigate(-1)
	elif event.is_action_pressed("ui_navigate_down"):  _ctrl_navigate(1)
	elif event.is_action_pressed("confirm"):           _buttons[_ctrl_index].emit_signal("pressed")
	elif event.is_action_pressed("cancel"):            _on_resume()
	else: return
	get_viewport().set_input_as_handled()

func _ctrl_navigate(dir: int) -> void:
	_ctrl_index = (_ctrl_index + dir + _buttons.size()) % _buttons.size()
	_ctrl_refresh_focus()

func _ctrl_refresh_focus() -> void:
	for i in _buttons.size():
		if i == _ctrl_index: _buttons[i].grab_focus()
		else: _buttons[i].release_focus()
