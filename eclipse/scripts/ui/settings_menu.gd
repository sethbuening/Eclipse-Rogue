extends Control

# ============================================================ scene: SettingsMenu
# Tab: General (audio/video). Controls tab is stubbed — remapping comes later.

const FONT_TITLE: String = "res://assets/fonts/Orbitron-Bold.ttf"
const FONT_LABEL: String = "res://assets/fonts/Rajdhani-SemiBold.ttf"
const FONT_UI:    String = "res://assets/fonts/ShareTechMono-Regular.ttf"

# Sci-fi palette
const C_BG:          Color = Color(0.02, 0.04, 0.06, 0.96)   # deep navy
const C_PANEL:       Color = Color(0.04, 0.07, 0.10, 1.0)    # dark steel
const C_BORDER:      Color = Color("#0e2a38")
const C_TITLE:       Color = Color("#a0e8f0")   # icy cyan
const C_LABEL:       Color = Color("#7ac8d8")   # teal
const C_LABEL_MUTED: Color = Color("#2a6070")   # dim teal
const C_LABEL_DIM:   Color = Color("#1e3a40")   # very dim
const C_HOVER:       Color = Color("#e0f8ff")   # bright white-cyan
const C_BTN_BG:      Color = Color("#040e14")
const C_BTN_HOVER:   Color = Color("#0a1e28")
const C_BTN_BORDER:  Color = Color("#0e3850")
const C_ACCENT:      Color = Color("#00b4cc")   # cyan accent
const C_INFO:        Color = Color("#2a7a8a")

signal closed

enum Tab { GENERAL, CONTROLS }

var _tab: Tab = Tab.GENERAL
var _general_panel:  Control = null
var _controls_panel: Control = null
var _tab_btns: Array[Button] = []

func _ready() -> void:
	_build()
	visible = false

func open() -> void:
	visible = true

func request_close() -> void:
	visible = false
	closed.emit()

func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 500)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	vbox.add_child(_build_header())
	vbox.add_child(_build_tab_bar())
	vbox.add_child(_build_separator())

	var content := MarginContainer.new()
	content.add_theme_constant_override("margin_left",   32)
	content.add_theme_constant_override("margin_right",  32)
	content.add_theme_constant_override("margin_top",    24)
	content.add_theme_constant_override("margin_bottom", 24)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content)

	var panels := Control.new()
	panels.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(panels)

	_general_panel = _build_general_panel()
	_general_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panels.add_child(_general_panel)

	_controls_panel = _build_controls_stub()
	_controls_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panels.add_child(_controls_panel)

	vbox.add_child(_build_separator())
	vbox.add_child(_build_footer())

	_switch_tab(Tab.GENERAL)

func _build_header() -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left",   32)
	m.add_theme_constant_override("margin_right",  32)
	m.add_theme_constant_override("margin_top",    24)
	m.add_theme_constant_override("margin_bottom", 16)
	var lbl := Label.new()
	lbl.text = "SYSTEM CONFIG"
	lbl.add_theme_font_override("font", load(FONT_TITLE))
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", C_TITLE)
	m.add_child(lbl)
	return m

func _build_tab_bar() -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left",  32)
	m.add_theme_constant_override("margin_right", 32)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	m.add_child(hbox)
	_tab_btns.clear()
	for i in range(2):
		var lbl: String = ["General", "Controls"][i]
		var btn := _tab_btn(lbl)
		var idx: int = i
		btn.pressed.connect(func(): _switch_tab(idx as Tab))
		hbox.add_child(btn)
		_tab_btns.append(btn)
	return m

func _build_general_panel() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.add_child(_slider_row("Master volume", 1.0, func(v): _set_bus_safe("Master", v)))
	vbox.add_child(_slider_row("Music volume",  0.8, func(v): _set_bus_safe("Music",  v)))
	vbox.add_child(_slider_row("SFX volume",    1.0, func(v): _set_bus_safe("SFX",    v)))
	vbox.add_child(_spacer(8))
	vbox.add_child(_toggle_row("Fullscreen",
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN,
		func(v): DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if v
			else DisplayServer.WINDOW_MODE_WINDOWED)))
	return vbox

func _build_controls_stub() -> Control:
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)

	var icon := Label.new()
	icon.text = "[ CONTROL REMAPPING ]"
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_override("font", load(FONT_LABEL))
	icon.add_theme_font_size_override("font_size", 16)
	icon.add_theme_color_override("font_color", C_ACCENT)
	vbox.add_child(icon)

	var lbl := Label.new()
	lbl.text = "SYSTEM OFFLINE\nControl remapping module pending installation."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", load(FONT_UI))
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", C_LABEL_MUTED)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(lbl)
	return vbox

func _build_footer() -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left",   32)
	m.add_theme_constant_override("margin_right",  32)
	m.add_theme_constant_override("margin_top",    16)
	m.add_theme_constant_override("margin_bottom", 20)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	m.add_child(hbox)

	var reset_btn := _action_btn("Reset defaults")
	reset_btn.pressed.connect(_on_reset_pressed)
	hbox.add_child(reset_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var back_btn := _action_btn("Back")
	back_btn.pressed.connect(request_close)
	hbox.add_child(back_btn)
	return m

func _switch_tab(tab: Tab) -> void:
	_tab = tab
	_general_panel.visible  = tab == Tab.GENERAL
	_controls_panel.visible = tab == Tab.CONTROLS
	for i in range(_tab_btns.size()):
		_set_tab_active(_tab_btns[i], i == tab as int)

func _set_bus_safe(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))
	else:
		push_warning("[OptionsMenu] Audio bus '%s' not found." % bus_name)

func _on_reset_pressed() -> void:
	if _tab == Tab.GENERAL:
		_set_bus_safe("Master", 1.0)
		_set_bus_safe("Music",  0.8)
		_set_bus_safe("SFX",    1.0)
		var parent := _general_panel.get_parent()
		_general_panel.queue_free()
		_general_panel = _build_general_panel()
		_general_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		parent.add_child(_general_panel)
		_general_panel.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if InputMap.event_is_action(event, "cancel", true) \
			or InputMap.event_is_action(event, "pause", true):
		request_close()
		get_viewport().set_input_as_handled()

# ================================================================= widgets

func _slider_row(label_text: String, val: float, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var lbl := Label.new()
	lbl.text                = label_text
	lbl.custom_minimum_size = Vector2(180, 0)
	lbl.add_theme_font_override("font", load(FONT_UI))
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", C_LABEL)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value             = 0.0
	slider.max_value             = 1.0
	slider.value                 = val
	slider.step                  = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.text                = "%d%%" % int(val * 100)
	val_lbl.custom_minimum_size = Vector2(44, 0)
	val_lbl.add_theme_font_override("font", load(FONT_UI))
	val_lbl.add_theme_font_size_override("font_size", 13)
	val_lbl.add_theme_color_override("font_color", C_LABEL_MUTED)
	slider.value_changed.connect(func(v: float):
		val_lbl.text = "%d%%" % int(v * 100)
		on_change.call(v))
	row.add_child(val_lbl)
	return row

func _toggle_row(label_text: String, initial: bool, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var lbl := Label.new()
	lbl.text                  = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_override("font", load(FONT_UI))
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", C_LABEL)
	row.add_child(lbl)

	var chk := CheckButton.new()
	chk.button_pressed = initial
	chk.toggled.connect(on_change)
	row.add_child(chk)
	return row

func _build_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", C_BORDER)
	sep.add_theme_constant_override("separation", 1)
	return sep

func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s

# ================================================================= styles

func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color     = C_PANEL
	s.border_color = C_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.set_content_margin_all(0)
	return s

func _tab_btn(label_text: String) -> Button:
	var btn := Button.new()
	btn.text                = label_text
	btn.flat                = false
	btn.toggle_mode         = true
	btn.focus_mode          = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 38)
	btn.add_theme_font_override("font", load(FONT_UI))
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color",         C_LABEL_MUTED)
	btn.add_theme_color_override("font_hover_color",   C_LABEL)
	btn.add_theme_color_override("font_pressed_color", C_LABEL)
	btn.add_theme_color_override("font_focus_color",   C_LABEL)
	btn.add_theme_stylebox_override("normal",  _tab_style(false))
	btn.add_theme_stylebox_override("hover",   _tab_style(false))
	btn.add_theme_stylebox_override("pressed", _tab_style(true))
	btn.add_theme_stylebox_override("focus",   _tab_style(false))
	return btn

func _tab_style(active: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color            = C_BTN_HOVER if active else Color(0, 0, 0, 0)
	s.border_color        = C_ACCENT    if active else Color(0, 0, 0, 0)
	s.set_border_width_all(0)
	s.border_width_bottom = 2 if active else 0
	s.set_corner_radius_all(0)
	s.set_content_margin_all(8)
	return s

func _set_tab_active(btn: Button, active: bool) -> void:
	btn.button_pressed = active
	btn.add_theme_stylebox_override("normal",  _tab_style(active))
	btn.add_theme_stylebox_override("pressed", _tab_style(active))
	btn.add_theme_color_override("font_color",
		C_LABEL if active else C_LABEL_MUTED)

func _action_btn(label_text: String) -> Button:
	var btn := Button.new()
	btn.text                = label_text
	btn.custom_minimum_size = Vector2(140, 36)
	btn.add_theme_font_override("font", load(FONT_UI))
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color",         C_LABEL)
	btn.add_theme_color_override("font_hover_color",   C_HOVER)
	btn.add_theme_color_override("font_pressed_color", C_HOVER)
	btn.add_theme_stylebox_override("normal",  _btn_style(false))
	btn.add_theme_stylebox_override("hover",   _btn_style(true))
	btn.add_theme_stylebox_override("pressed", _btn_style(true))
	btn.add_theme_stylebox_override("focus",   _btn_style(false))
	return btn

func _btn_style(hover: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color     = C_BTN_HOVER if hover else C_BTN_BG
	s.border_color = C_BTN_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.set_content_margin_all(6)
	return s
