extends Control

# ============================================================ scene: OptionsMenu
# Two tabs: General (audio/video), Controls (Keyboard/Mouse | Controller).
#
# Controller tab behaviour:
#
#   Steam connected  → shows current Steam action → Godot action mapping
#                      with remap buttons. Remapping stores overrides via
#                      SteamInputManager (no raw joypad events involved).
#
#   No Steam         → shows raw joypad InputMap events with remap buttons.
#                      Remapping captured via InputManager (ListenMode.CONTROLLER).
#
# Both paths use the same UI layout so the experience is consistent.
# The only visible difference is the sub-header text explaining which
# backend is active.

const FONT_TITLE: String = "res://assets/fonts/Cinzel-Bold.ttf"
const FONT_LABEL: String = "res://assets/fonts/Cinzel-Regular.ttf"
const FONT_UI:    String = "res://assets/fonts/JosefinSans-Light.ttf"

const C_BG:          Color = Color(0.04, 0.02, 0.06, 0.96)
const C_PANEL:       Color = Color(0.07, 0.04, 0.10, 1.0)
const C_BORDER:      Color = Color("#2a1e38")
const C_TITLE:       Color = Color("#f0dfa0")
const C_LABEL:       Color = Color("#c8a87a")
const C_LABEL_MUTED: Color = Color("#6b5030")
const C_LABEL_DIM:   Color = Color("#4a3820")
const C_HOVER:       Color = Color("#f5d78e")
const C_BTN_BG:      Color = Color("#1a1024")
const C_BTN_HOVER:   Color = Color("#2a1a34")
const C_BTN_BORDER:  Color = Color("#3d2850")
const C_LISTENING:   Color = Color("#f0dfa0")
const C_ACCENT:      Color = Color("#7a3aaa")
const C_INFO:        Color = Color("#8a6aaa")

signal closed

enum Tab         { GENERAL, CONTROLS }
enum ControlsTab { KEYBOARD, CONTROLLER }

var _tab:  Tab         = Tab.GENERAL
var _ctab: ControlsTab = ControlsTab.KEYBOARD

# --- built nodes we need to reference later ---
var _general_panel:     Control         = null
var _controls_panel:    Control         = null
var _kb_panel:          ScrollContainer = null
var _ctrl_panel:        ScrollContainer = null
var _kb_list:           VBoxContainer   = null
var _ctrl_list:         VBoxContainer   = null
var _ctrl_info_label:   Label           = null
var _listening_overlay: Control         = null
var _listening_label:   Label           = null
var _tab_btns:          Array[Button]   = []
var _ctab_btns:         Array[Button]   = []

# --- pending remap state for Steam listen path ---
var _steam_listening:        bool   = false
var _steam_listen_action:    String = ""   # Godot action we are waiting to replace
var _steam_listen_old_steam: String = ""   # steam action that currently fires it

const ACTION_NAMES: Dictionary = {
	"move_up":            "Move up",
	"move_down":          "Move down",
	"move_left":          "Move left",
	"move_right":         "Move right",
	"orb_1":              "Orb 1",
	"orb_2":              "Orb 2",
	"orb_3":              "Orb 3",
	"orb_4":              "Orb 4",
	"orb_5":              "Orb 5",
	"basic_ability":      "Basic ability",
	"channel_light":      "Channel light",
	"open_graph":         "Open graph",
	"pause":              "Pause",
	"throw_flare":        "Throw flare",
	"interact":           "Interact",
	"confirm":            "Confirm",
	"cancel":             "Cancel",
	"ui_navigate_up":     "Navigate up",
	"ui_navigate_down":   "Navigate down",
	"ui_navigate_left":   "Navigate left",
	"ui_navigate_right":  "Navigate right",
	"ui_eject":           "Eject",
	"ui_switch_panel":    "Switch panel",
	"ui_scroll_up":       "Scroll up",
	"ui_scroll_down":     "Scroll down",
}

# ================================================================= lifecycle

func _ready() -> void:
	InputManager.bindings_changed.connect(_on_bindings_changed)
	InputManager.listen_cancelled.connect(_on_listen_cancelled)
	SteamInputManager.steam_bindings_changed.connect(_on_bindings_changed)
	_build()
	visible = false

func open() -> void:
	visible = true
	_rebuild_lists()

func request_close() -> void:
	if InputManager.is_listening():
		InputManager.stop_listening()
		_listening_overlay.visible = false
		return
	if _steam_listening:
		_cancel_steam_listen()
		return
	visible = false
	closed.emit()

# ================================================================= build

func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 560)
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

	_controls_panel = _build_controls_panel()
	_controls_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panels.add_child(_controls_panel)

	vbox.add_child(_build_separator())
	vbox.add_child(_build_footer())

	_listening_overlay = _build_listening_overlay()
	add_child(_listening_overlay)

	_switch_tab(Tab.GENERAL)

# ----------------------------------------------------------------- sub-builders

func _build_header() -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left",   32)
	m.add_theme_constant_override("margin_right",  32)
	m.add_theme_constant_override("margin_top",    24)
	m.add_theme_constant_override("margin_bottom", 16)
	var lbl := Label.new()
	lbl.text = "OPTIONS"
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
	var tab_labels: Array[String] = ["General", "Controls"]
	_tab_btns.clear()
	for i in range(tab_labels.size()):
		var btn := _tab_btn(tab_labels[i])
		var idx: int = i
		btn.pressed.connect(func(): _switch_tab(idx as Tab))
		hbox.add_child(btn)
		_tab_btns.append(btn)
	return m

func _build_general_panel() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.add_child(_slider_row("Master volume", 1.0,
		func(v): AudioServer.set_bus_volume_db(
			AudioServer.get_bus_index("Master"), linear_to_db(v))))
	vbox.add_child(_slider_row("Music volume",  0.8,
		func(v): AudioServer.set_bus_volume_db(
			AudioServer.get_bus_index("Music"), linear_to_db(v))))
	vbox.add_child(_slider_row("SFX volume",    1.0,
		func(v): AudioServer.set_bus_volume_db(
			AudioServer.get_bus_index("SFX"), linear_to_db(v))))
	vbox.add_child(_spacer(8))
	vbox.add_child(_toggle_row("Fullscreen",
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN,
		func(v): DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if v
			else DisplayServer.WINDOW_MODE_WINDOWED)))
	return vbox

func _build_controls_panel() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	# Sub-tab bar.
	var sub_hbox := HBoxContainer.new()
	sub_hbox.add_theme_constant_override("separation", 2)
	var sub_labels: Array[String] = ["Keyboard / Mouse", "Controller"]
	_ctab_btns.clear()
	for i in range(sub_labels.size()):
		var btn := _tab_btn(sub_labels[i], true)
		var idx: int = i
		btn.pressed.connect(func(): _switch_ctab(idx as ControlsTab))
		sub_hbox.add_child(btn)
		_ctab_btns.append(btn)
	vbox.add_child(sub_hbox)

	# Info label shown in the controller tab header.
	_ctrl_info_label = Label.new()
	_ctrl_info_label.add_theme_font_override("font", load(FONT_UI))
	_ctrl_info_label.add_theme_font_size_override("font_size", 11)
	_ctrl_info_label.add_theme_color_override("font_color", C_INFO)
	_ctrl_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_ctrl_info_label)

	# Keyboard scroll list.
	_kb_panel = _make_scroll()
	_kb_list   = VBoxContainer.new()
	_kb_list.add_theme_constant_override("separation", 6)
	_kb_panel.add_child(_kb_list)
	vbox.add_child(_kb_panel)

	# Controller scroll list.
	_ctrl_panel = _make_scroll()
	_ctrl_list   = VBoxContainer.new()
	_ctrl_list.add_theme_constant_override("separation", 6)
	_ctrl_panel.add_child(_ctrl_list)
	vbox.add_child(_ctrl_panel)

	_switch_ctab(ControlsTab.KEYBOARD)
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

	var reset_btn := _action_btn("Reset to defaults")
	reset_btn.pressed.connect(_on_reset_pressed)
	hbox.add_child(reset_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var back_btn := _action_btn("Back")
	back_btn.pressed.connect(request_close)
	hbox.add_child(back_btn)
	return m

func _build_listening_overlay() -> Control:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color   = Color(0.01, 0.005, 0.02, 0.92)
	overlay.visible = false

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.custom_minimum_size = Vector2(340, 0)
	center.add_child(box)

	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", load(FONT_LABEL))
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", C_LISTENING)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lbl)
	_listening_label = lbl

	var cancel_btn := _action_btn("Cancel  [Esc]")
	cancel_btn.pressed.connect(func():
		if _steam_listening:
			_cancel_steam_listen()
		else:
			InputManager.stop_listening()
			overlay.visible = false)
	box.add_child(cancel_btn)
	return overlay

# ================================================================= tab switching

func _switch_tab(tab: Tab) -> void:
	_tab = tab
	_general_panel.visible  = tab == Tab.GENERAL
	_controls_panel.visible = tab == Tab.CONTROLS
	for i in range(_tab_btns.size()):
		_set_tab_active(_tab_btns[i], i == tab as int)
	if tab == Tab.CONTROLS:
		_rebuild_lists()

func _switch_ctab(ctab: ControlsTab) -> void:
	_ctab = ctab
	_kb_panel.visible         = ctab == ControlsTab.KEYBOARD
	_ctrl_panel.visible       = ctab == ControlsTab.CONTROLLER
	_ctrl_info_label.visible  = ctab == ControlsTab.CONTROLLER
	for i in range(_ctab_btns.size()):
		_set_tab_active(_ctab_btns[i], i == ctab as int)

# ================================================================= list build

func _rebuild_lists() -> void:
	if _kb_list == null or _ctrl_list == null:
		return

	# Clear old rows.
	for c in _kb_list.get_children():   c.queue_free()
	for c in _ctrl_list.get_children(): c.queue_free()

	# Update controller info label.
	if SteamInputManager.is_controller_connected():
		_ctrl_info_label.text = "Steam Input is active. Remapping here changes which in-game action each Steam action triggers."
	else:
		_ctrl_info_label.text = "No Steam controller detected. Raw controller buttons are shown and can be rebound directly."

	for action in InputManager.REMAPPABLE_ACTIONS:
		_kb_list.add_child(_binding_row_keyboard(action))
		_ctrl_list.add_child(_binding_row_controller(action))

# ----------------------------------------------------------------- keyboard row

func _binding_row_keyboard(action: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 38)
	row.add_child(_action_label(action))

	var events: Array[InputEvent] = InputManager.get_keyboard_events(action)
	var show_defaults: bool = events.is_empty()
	if show_defaults:
		events = InputManager.get_default_keyboard_events(action)

	var shown: int = 0
	for event in events:
		if shown >= 2:
			break
		var btn  := _binding_btn(_event_str(event), show_defaults)
		var a    := action
		var e    := event if not show_defaults else null
		btn.pressed.connect(func(): _start_listen_keyboard(a, e))
		row.add_child(btn)
		shown += 1

	if shown < 2 and not show_defaults:
		var add := _binding_btn("+")
		add.custom_minimum_size = Vector2(36, 34)
		var a := action
		add.pressed.connect(func(): _start_listen_keyboard(a, null))
		row.add_child(add)

	return row

# ----------------------------------------------------------------- controller row
#
# Steam path  → each row shows the steam action name and the Godot action it
#               currently maps to (default or overridden). A remap button opens
#               the Steam-listen overlay which waits for a DIFFERENT steam action
#               to be pressed, then swaps the mappings.
#
# Non-Steam path → identical to the keyboard row but for joypad events.

func _binding_row_controller(action: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 38)
	row.add_child(_action_label(action))

	if SteamInputManager.is_controller_connected():
		_build_steam_row(row, action)
	else:
		_build_raw_joypad_row(row, action)

	return row

func _build_steam_row(row: HBoxContainer, godot_action: String) -> void:
	# Find which Steam action currently triggers this Godot action.
	var steam_action: String = SteamInputManager.get_steam_action_for_godot(godot_action)
	var is_overridden: bool  = SteamInputManager._action_overrides.has(steam_action)

	var label_text: String
	if steam_action == "":
		label_text = "—"
	else:
		# Show the steam action name, dimmed if it's just the default.
		label_text = steam_action

	var btn := _binding_btn(label_text, not is_overridden)
	var a := godot_action
	var s := steam_action
	btn.pressed.connect(func(): _start_listen_steam(a, s))
	row.add_child(btn)

func _build_raw_joypad_row(row: HBoxContainer, action: String) -> void:
	var events: Array[InputEvent] = InputManager.get_controller_events(action)
	var show_defaults: bool = events.is_empty()
	if show_defaults:
		events = InputManager.get_default_controller_events(action)

	var shown: int = 0
	for event in events:
		if shown >= 2:
			break
		var btn  := _binding_btn(_event_str(event), show_defaults)
		var a    := action
		var e    := event if not show_defaults else null
		btn.pressed.connect(func(): _start_listen_controller(a, e))
		row.add_child(btn)
		shown += 1

	if shown < 2 and not show_defaults:
		var add := _binding_btn("+")
		add.custom_minimum_size = Vector2(36, 34)
		var a := action
		add.pressed.connect(func(): _start_listen_controller(a, null))
		row.add_child(add)

func _action_label(action: String) -> Label:
	var lbl := Label.new()
	lbl.text                  = ACTION_NAMES.get(action, action)
	lbl.custom_minimum_size   = Vector2(190, 0)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_override("font", load(FONT_UI))
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", C_LABEL)
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	return lbl

# ================================================================= listen — keyboard

func _start_listen_keyboard(action: String, old_event: InputEvent) -> void:
	_listening_label.text = \
		"Press a key or mouse button for:\n%s\n\n(Escape to cancel)" \
		% ACTION_NAMES.get(action, action)
	_listening_overlay.visible = true
	InputManager.start_listening_keyboard(action, old_event)

# ================================================================= listen — raw joypad

func _start_listen_controller(action: String, old_event: InputEvent) -> void:
	_listening_label.text = \
		"Press a button or move a stick for:\n%s\n\n(Escape to cancel)" \
		% ACTION_NAMES.get(action, action)
	_listening_overlay.visible = true
	InputManager.start_listening_controller(action, old_event)

# ================================================================= listen — Steam
#
# Steam Input captures physical controller inputs before Godot, so we cannot
# watch raw joypad events. Instead we poll SteamInputManager for a newly-pressed
# digital action and reassign the mapping once detected.

func _start_listen_steam(godot_action: String, current_steam_action: String) -> void:
	_steam_listening        = true
	_steam_listen_action    = godot_action
	_steam_listen_old_steam = current_steam_action
	_listening_label.text   = \
		"Press a controller button for:\n%s\n\n(Escape to cancel)" \
		% ACTION_NAMES.get(godot_action, godot_action)
	_listening_overlay.visible = true
	set_process(true)

func _cancel_steam_listen() -> void:
	_steam_listening        = false
	_steam_listen_action    = ""
	_steam_listen_old_steam = ""
	_listening_overlay.visible = false
	set_process(false)

func _process(_delta: float) -> void:
	if not _steam_listening:
		set_process(false)
		return
	# Poll for any digital Steam action that is now pressed.
	if not SteamInputManager._enabled or SteamInputManager._controller == 0:
		_cancel_steam_listen()
		return
	for steam_action in SteamInputManager.DIGITAL_ACTION_MAP.keys():
		var data: Dictionary = Steam.getDigitalActionData(
			SteamInputManager._controller,
			SteamInputManager._digital_handles[steam_action])
		if not data.get("bActive", false):
			continue
		if not data.get("bState", false):
			continue
		# A button is held. If it's already the bound one, ignore it.
		if steam_action == _steam_listen_old_steam:
			continue
		# Apply the swap:
		# 1. If the pressed steam_action already had a custom target, clear it.
		# 2. Set the old steam action back to its default target.
		# 3. Point the pressed steam action at the requested godot action.
		var default_old: String = SteamInputManager.DIGITAL_ACTION_MAP.get(
			_steam_listen_old_steam, "")
		var default_new: String = SteamInputManager.DIGITAL_ACTION_MAP.get(steam_action, "")

		# Clear any prior override for the pressed action (it will get a new one).
		SteamInputManager._action_overrides.erase(steam_action)
		# Send the old steam action back to its default godot action.
		if _steam_listen_old_steam != "":
			SteamInputManager.set_steam_action_override(
				_steam_listen_old_steam, default_old)
		# Map the pressed steam action to the requested godot action.
		SteamInputManager.set_steam_action_override(steam_action, _steam_listen_action)

		_cancel_steam_listen()
		return

# ================================================================= reset

func _on_reset_pressed() -> void:
	match _ctab:
		ControlsTab.KEYBOARD:
			InputManager.reset_all()
		ControlsTab.CONTROLLER:
			if SteamInputManager.is_controller_connected():
				SteamInputManager.reset_steam_overrides()
			else:
				InputManager.reset_all()
	_rebuild_lists()

# ================================================================= signal handlers

func _on_bindings_changed() -> void:
	_listening_overlay.visible = false
	_rebuild_lists()

func _on_listen_cancelled() -> void:
	_listening_overlay.visible = false

# ================================================================= input (Esc / cancel action)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if InputMap.event_is_action(event, "cancel", true) \
			or InputMap.event_is_action(event, "pause", true):
		request_close()
		get_viewport().set_input_as_handled()

# ================================================================= widgets

func _slider_row(label_text: String, val: float,
		on_change: Callable = Callable()) -> Control:
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
		if on_change.is_valid():
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

func _make_scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size    = Vector2(0, 300)
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return s

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
	s.set_corner_radius_all(4)
	s.set_content_margin_all(0)
	return s

func _tab_btn(label_text: String, small: bool = false) -> Button:
	var btn := Button.new()
	btn.text                = label_text
	btn.flat                = false
	btn.toggle_mode         = true
	btn.focus_mode          = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 34 if small else 38)
	btn.add_theme_font_override("font", load(FONT_UI))
	btn.add_theme_font_size_override("font_size", 12 if small else 13)
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

func _binding_btn(label_text: String, is_default: bool = false) -> Button:
	var btn := Button.new()
	btn.text                = label_text
	btn.custom_minimum_size = Vector2(110, 34)
	btn.add_theme_font_override("font", load(FONT_UI))
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color",
		C_LABEL_DIM if is_default else C_LABEL)
	btn.add_theme_color_override("font_hover_color",   C_HOVER)
	btn.add_theme_color_override("font_pressed_color", C_HOVER)
	btn.add_theme_stylebox_override("normal",  _binding_style(false))
	btn.add_theme_stylebox_override("hover",   _binding_style(true))
	btn.add_theme_stylebox_override("pressed", _binding_style(true))
	btn.add_theme_stylebox_override("focus",   _binding_style(false))
	return btn

func _binding_style(hover: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color     = C_BTN_HOVER if hover else C_BTN_BG
	s.border_color = C_BTN_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.set_content_margin_all(6)
	return s

func _action_btn(label_text: String) -> Button:
	var btn := Button.new()
	btn.text                = label_text
	btn.custom_minimum_size = Vector2(140, 36)
	btn.add_theme_font_override("font", load(FONT_UI))
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color",         C_LABEL)
	btn.add_theme_color_override("font_hover_color",   C_HOVER)
	btn.add_theme_color_override("font_pressed_color", C_HOVER)
	btn.add_theme_stylebox_override("normal",  _binding_style(false))
	btn.add_theme_stylebox_override("hover",   _binding_style(true))
	btn.add_theme_stylebox_override("pressed", _binding_style(true))
	btn.add_theme_stylebox_override("focus",   _binding_style(false))
	return btn

# ================================================================= helpers

func _event_str(event: InputEvent) -> String:
	if event is InputEventKey:
		return OS.get_keycode_string(event.get_key_label_with_modifiers())
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:   return "Left click"
			MOUSE_BUTTON_RIGHT:  return "Right click"
			MOUSE_BUTTON_MIDDLE: return "Middle click"
			_: return "Mouse %d" % event.button_index
	if event is InputEventJoypadButton:
		match event.button_index:
			JOY_BUTTON_A:              return "A"
			JOY_BUTTON_B:              return "B"
			JOY_BUTTON_X:              return "X"
			JOY_BUTTON_Y:              return "Y"
			JOY_BUTTON_LEFT_SHOULDER:  return "LB"
			JOY_BUTTON_RIGHT_SHOULDER: return "RB"
			JOY_BUTTON_LEFT_STICK:     return "L3"
			JOY_BUTTON_RIGHT_STICK:    return "R3"
			JOY_BUTTON_START:          return "Menu"
			JOY_BUTTON_BACK:           return "View"
			JOY_BUTTON_DPAD_UP:        return "D-Up"
			JOY_BUTTON_DPAD_DOWN:      return "D-Down"
			JOY_BUTTON_DPAD_LEFT:      return "D-Left"
			JOY_BUTTON_DPAD_RIGHT:     return "D-Right"
			_: return "Btn %d" % event.button_index
	if event is InputEventJoypadMotion:
		var dir: String = "+" if event.axis_value > 0 else "-"
		match event.axis:
			JOY_AXIS_LEFT_X:       return "LS " + ("Right" if dir == "+" else "Left")
			JOY_AXIS_LEFT_Y:       return "LS " + ("Down"  if dir == "+" else "Up")
			JOY_AXIS_RIGHT_X:      return "RS " + ("Right" if dir == "+" else "Left")
			JOY_AXIS_RIGHT_Y:      return "RS " + ("Down"  if dir == "+" else "Up")
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_TRIGGER_RIGHT:return "RT"
			_: return "Axis %d%s" % [event.axis, dir]
	return event.as_text()
