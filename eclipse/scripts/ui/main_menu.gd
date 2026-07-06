# main_menu.gd
# ---------------------------------------------------------------------------
# Top-level main menu. Flow: CONTINUE (stub) / NEW MISSION (biome -> depth ->
# class) / CRAFT (meta-crafting stub) / SETTINGS / QUIT.
# Game starts paused on this menu; confirming a mission unpauses and hides it.
# ---------------------------------------------------------------------------
extends CanvasLayer

const FONT_TITLE: String = "res://assets/fonts/Orbitron-Bold.ttf"
const FONT_MENU:  String = "res://assets/fonts/Rajdhani-SemiBold.ttf"

const C_BG:        Color = Color(0.01, 0.03, 0.05, 1.0)
const C_TITLE:     Color = Color("#a0e8f0")
const C_SUBTITLE:  Color = Color("#2a6070")
const C_MENU:      Color = Color("#7ac8d8")
const C_HOVER:     Color = Color("#e0f8ff")
const C_DISABLED:  Color = Color("#1e3a40")
const C_DIVIDER:   Color = Color("#0e2a38")

const _STICK_DEAD: float = 0.4

const MissionSetupMenuScript: GDScript = preload("res://scripts/ui/mission_setup_menu.gd")
const CraftMenuScript:        GDScript = preload("res://scripts/ui/craft_menu.gd")

var _ctrl_index: int = 0
var _buttons: Array[Button] = []
var _stick_was_active: Dictionary = {}

var _settings_menu:      Control     = null
var _mission_setup_menu: CanvasLayer = null
var _craft_menu:         CanvasLayer = null

var _continue_btn: Button = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build()
	# The run hasn't started yet -- hold the tree paused until a mission is confirmed.
	get_tree().paused = true

func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 8)
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var title := Label.new()
	title.text = "DEEPVEIN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", load(FONT_TITLE))
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", C_TITLE)
	panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "// DESCENT SYSTEM ONLINE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", load(FONT_MENU))
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", C_SUBTITLE)
	panel.add_child(subtitle)

	var div := HSeparator.new()
	div.add_theme_color_override("color", C_DIVIDER)
	div.custom_minimum_size = Vector2(0, 20)
	panel.add_child(div)

	for item in [
		{"label": "CONTINUE",     "cb": _on_continue},
		{"label": "NEW MISSION",  "cb": _on_new_mission},
		{"label": "CRAFT",        "cb": _on_open_craft},
		{"label": "SETTINGS",     "cb": _on_settings},
		{"label": "QUIT",         "cb": _on_quit},
	]:
		var btn := _make_btn(item["label"])
		btn.pressed.connect(item["cb"])
		panel.add_child(btn)
		var idx: int = _buttons.size()
		btn.mouse_entered.connect(func(): _ctrl_index = idx; btn.grab_focus())
		btn.focus_entered.connect(func(): _ctrl_index = idx)
		_buttons.append(btn)
		if item["label"] == "CONTINUE":
			_continue_btn = btn

	_refresh_continue_state()

	_settings_menu = preload("res://scenes/ui/settings_menu.tscn").instantiate()
	_settings_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_menu.visible = false
	_settings_menu.closed.connect(_on_settings_closed)
	add_child(_settings_menu)

	_mission_setup_menu = MissionSetupMenuScript.new()
	_mission_setup_menu.visible = false
	_mission_setup_menu.mission_confirmed.connect(_on_mission_confirmed)
	_mission_setup_menu.cancelled.connect(_on_mission_setup_closed)
	add_child(_mission_setup_menu)

	_craft_menu = CraftMenuScript.new()
	_craft_menu.visible = false
	_craft_menu.closed.connect(_on_craft_closed)
	add_child(_craft_menu)

	_ctrl_refresh_focus()

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
	btn.add_theme_color_override("font_disabled_color", C_DISABLED)
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	return btn

# ── Continue (stub -- no save system yet) ──────────────────────────────────
func _refresh_continue_state() -> void:
	var has_save: bool = false
	if has_node("/root/SaveManager"):
		has_save = SaveManager.has_save()
	_continue_btn.disabled = not has_save
	if not has_save:
		_continue_btn.tooltip_text = "No run in progress."

func _on_continue() -> void:
	if has_node("/root/SaveManager") and SaveManager.has_save():
		SaveManager.load_game()

# ── New mission flow ────────────────────────────────────────────────────────
func _on_new_mission() -> void:
	_set_buttons_blocked(true)
	_mission_setup_menu.visible = true
	_mission_setup_menu.layer = 2
	_mission_setup_menu.open()
	visible = false

func _on_mission_setup_closed() -> void:
	_mission_setup_menu.visible = false
	_set_buttons_blocked(false)
	visible = true
	_ctrl_refresh_focus()

func _on_mission_confirmed(biome: BiomeData, depth: int, char_class: ClassData) -> void:
	_mission_setup_menu.visible = false
	if has_node("/root/RunConfig"):
		RunConfig.start_mission(biome, depth, char_class)
	else:
		push_warning("[MainMenu] RunConfig autoload missing -- mission selection won't reach the game.")
	# Hand off to the run: hide the menu entirely and let the game unpause.
	visible = false
	get_tree().paused = false

# ── Craft (stub) ─────────────────────────────────────────────────────────────
func _on_open_craft() -> void:
	_set_buttons_blocked(true)
	_craft_menu.visible = true
	_craft_menu.open()

func _on_craft_closed() -> void:
	_craft_menu.visible = false
	_set_buttons_blocked(false)
	_ctrl_refresh_focus()

# ── Settings ─────────────────────────────────────────────────────────────────
func _on_settings() -> void:
	_settings_menu.visible = true
	_settings_menu.open()

func _on_settings_closed() -> void:
	_settings_menu.visible = false
	_ctrl_refresh_focus()

# ── Quit ─────────────────────────────────────────────────────────────────────
func _on_quit() -> void:
	get_tree().paused = false
	get_tree().quit()

# ── shared helpers ───────────────────────────────────────────────────────────
func _set_buttons_blocked(blocked: bool) -> void:
	for btn in _buttons:
		btn.focus_mode = Control.FOCUS_NONE if blocked else Control.FOCUS_ALL
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE if blocked else Control.MOUSE_FILTER_STOP

func _any_submenu_open() -> bool:
	return _settings_menu.visible or _mission_setup_menu.visible or _craft_menu.visible

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _any_submenu_open():
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
	elif event.is_action_pressed("confirm"):
		if not _buttons[_ctrl_index].disabled:
			_buttons[_ctrl_index].emit_signal("pressed")
	else: return
	get_viewport().set_input_as_handled()

func _ctrl_navigate(dir: int) -> void:
	var n: int = _buttons.size()
	for _i in range(n):
		_ctrl_index = (_ctrl_index + dir + n) % n
		if not _buttons[_ctrl_index].disabled:
			break
	_ctrl_refresh_focus()

func _ctrl_refresh_focus() -> void:
	for i in _buttons.size():
		if i == _ctrl_index: _buttons[i].grab_focus()
		else: _buttons[i].release_focus()
