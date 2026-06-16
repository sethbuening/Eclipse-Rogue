extends CanvasLayer

const FONT_TITLE: String = "res://assets/fonts/Cinzel-Bold.ttf"
const FONT_MENU:  String = "res://assets/fonts/Cinzel-Regular.ttf"

const C_BG: Color = Color(0.02, 0.01, 0.04, 0.88)
const C_TITLE:   Color = Color("#f0dfa0")
const C_MENU:    Color = Color("#c8a87a")
const C_HOVER:   Color = Color("#f5d78e")
const C_DIVIDER: Color = Color("#3a2e1e")

const _STICK_DEAD: float = 0.4

signal resumed

var _ctrl_index: int   = 0
var _buttons:    Array = []
var _stick_was_active: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	_build()

func _build() -> void:
	const HALF_W: float = 200.0
	const HALF_H: float = 130.0
	
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	add_child(bg)

	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 16)
	panel.custom_minimum_size = Vector2(400, 0)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top  = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -130.0; panel.offset_right  =  130.0
	panel.offset_top    = -130.0   # was -160 + HALF_H, now just -HALF_H
	panel.offset_bottom =  130.0
	panel.grow_vertical   = Control.GROW_DIRECTION_END
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	anchor.add_child(panel)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_override("font", load(FONT_TITLE))
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", C_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var div := HSeparator.new()
	div.add_theme_color_override("color", C_DIVIDER)
	div.custom_minimum_size = Vector2(0, 24)
	panel.add_child(div)

	for item in [{"label": "Resume", "cb": _on_resume}, {"label": "Quit", "cb": _on_quit}]:
		var btn := _make_btn(item["label"])
		btn.pressed.connect(item["cb"])
		panel.add_child(btn)
		_buttons.append(btn)

func _make_btn(text: String) -> Button:
	var btn := Button.new()
	btn.text = text; btn.flat = true
	btn.custom_minimum_size = Vector2(400, 60)
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
	%Player._pause_consumed = true  # adjust path as needed
	close()
	resumed.emit()

func _on_quit() -> void:
	get_tree().paused = false
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("pause"):
		_on_resume()
		get_viewport().set_input_as_handled()  # blocks player.gd from seeing it
		return

	if event is InputEventJoypadMotion:
		var axis: int  = event.axis
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
