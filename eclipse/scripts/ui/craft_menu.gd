# craft_menu.gd
# ---------------------------------------------------------------------------
# Stub craft menu opened from the main menu's CRAFT button. Spends MetaProgress
# currency to craft/uncraft gear between runs -- crafting itself isn't
# implemented yet, so CRAFT/UNCRAFT just show a "not built yet" notice.
# ---------------------------------------------------------------------------
extends CanvasLayer

const FONT_TITLE: String = "res://assets/fonts/Orbitron-Bold.ttf"
const FONT_MENU:  String = "res://assets/fonts/Rajdhani-SemiBold.ttf"
const FONT_UI:    String = "res://assets/fonts/ShareTechMono-Regular.ttf"

const C_BG:      Color = Color(0.01, 0.03, 0.05, 0.97)
const C_TITLE:   Color = Color("#a0e8f0")
const C_LABEL:   Color = Color("#7ac8d8")
const C_MUTED:   Color = Color("#2a6070")
const C_HOVER:   Color = Color("#e0f8ff")
const C_DIVIDER: Color = Color("#0e2a38")

signal closed

var _currency_label: Label = null
var _notice_label:    Label = null
var _buttons: Array[Button] = []
var _ctrl_index: int = 0

func _ready() -> void:
	_build()

func open() -> void:
	_refresh_currency()
	_notice_label.visible = false
	_ctrl_index = 0
	_ctrl_refresh_focus()

func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 12)
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var title := Label.new()
	title.text = "CRAFT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", load(FONT_TITLE))
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", C_TITLE)
	panel.add_child(title)

	_currency_label = Label.new()
	_currency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_currency_label.add_theme_font_override("font", load(FONT_UI))
	_currency_label.add_theme_font_size_override("font_size", 14)
	_currency_label.add_theme_color_override("font_color", C_MUTED)
	panel.add_child(_currency_label)

	var div := HSeparator.new()
	div.add_theme_color_override("color", C_DIVIDER)
	div.custom_minimum_size = Vector2(0, 16)
	panel.add_child(div)

	for item in [
		{"label": "CRAFT NEW GEAR", "cb": _on_craft},
		{"label": "UNCRAFT GEAR",   "cb": _on_uncraft},
		{"label": "BACK",           "cb": _on_back},
	]:
		var btn := _make_btn(item["label"])
		btn.pressed.connect(item["cb"])
		panel.add_child(btn)
		var idx: int = _buttons.size()
		btn.mouse_entered.connect(func(): _ctrl_index = idx; btn.grab_focus())
		btn.focus_entered.connect(func(): _ctrl_index = idx)
		_buttons.append(btn)

	_notice_label = Label.new()
	_notice_label.text = "Crafting system not built yet — coming soon."
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_label.add_theme_font_override("font", load(FONT_UI))
	_notice_label.add_theme_font_size_override("font_size", 13)
	_notice_label.add_theme_color_override("font_color", C_MUTED)
	_notice_label.visible = false
	panel.add_child(_notice_label)

func _refresh_currency() -> void:
	var amount: int = 0
	if has_node("/root/MetaProgress"):
		amount = MetaProgress.currency
	_currency_label.text = "META RESOURCES: %d" % amount

func _make_btn(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.flat = true
	btn.custom_minimum_size = Vector2(420, 52)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_theme_font_override("font", load(FONT_MENU))
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color",         C_LABEL)
	btn.add_theme_color_override("font_hover_color",   C_HOVER)
	btn.add_theme_color_override("font_focus_color",   C_HOVER)
	btn.add_theme_color_override("font_pressed_color", C_HOVER)
	for s in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	return btn

func _on_craft() -> void:
	_notice_label.visible = true

func _on_uncraft() -> void:
	_notice_label.visible = true

func _on_back() -> void:
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
	if event.is_action_pressed("cancel"):
		_on_back()
		get_viewport().set_input_as_handled()
		return
	if   event.is_action_pressed("ui_navigate_up"):   _ctrl_navigate(-1)
	elif event.is_action_pressed("ui_navigate_down"): _ctrl_navigate(1)
	elif event.is_action_pressed("confirm"):          _buttons[_ctrl_index].emit_signal("pressed")
	else: return
	get_viewport().set_input_as_handled()

func _ctrl_navigate(dir: int) -> void:
	_ctrl_index = (_ctrl_index + dir + _buttons.size()) % _buttons.size()
	_ctrl_refresh_focus()

func _ctrl_refresh_focus() -> void:
	for i in _buttons.size():
		if i == _ctrl_index: _buttons[i].grab_focus()
		else: _buttons[i].release_focus()
