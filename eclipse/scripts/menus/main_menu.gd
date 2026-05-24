extends Control

# ============================================================ scene: MainMenu
# Attach to a root Control node that fills the screen (e.g. a plain Control
# with anchors set to Full Rect, or a CanvasLayer child).
# The cave cinematic background sits BEHIND this node.
#
# Fonts: place at res://assets/fonts/
#   Cinzel-Bold.ttf, Cinzel-Regular.ttf, JosefinSans-Light.ttf
# Scenes:
#   res://scenes/ui/options_menu.tscn  ← options_menu.gd attached
#   res://scenes/game.tscn

const FONT_TITLE:    String = "res://assets/fonts/Cinzel-Bold.ttf"
const FONT_MENU:     String = "res://assets/fonts/Cinzel-Regular.ttf"
const FONT_SUBTITLE: String = "res://assets/fonts/JosefinSans-Light.ttf"

const C_TITLE:    Color = Color("#f0dfa0")
const C_MENU:     Color = Color("#c8a87a")
const C_HOVER:    Color = Color("#f5d78e")
const C_MUTED:    Color = Color("#4a3820")
const C_SUBTITLE: Color = Color("#6b5030")
const C_VERSION:  Color = Color("#3a2e1e")

const ITEM_H:   int = 38
const ITEM_GAP: int = 6

var _options_menu: Control = null

func _ready() -> void:
	_build()

func _build() -> void:
	# ── Full-screen centering container ─────────────────────────────────────
	# Everything sits inside a CenterContainer so it stays centred regardless
	# of window size or fullscreen state.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 0)
	root_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(root_vbox)

	# ── Title ────────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text = "DEEPVEIN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", load(FONT_TITLE))
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", C_TITLE)
	root_vbox.add_child(title)

	# ── Subtitle ─────────────────────────────────────────────────────────────
	var subtitle := Label.new()
	subtitle.text = "mine  ·  forge  ·  survive"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", load(FONT_SUBTITLE))
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", C_SUBTITLE)
	root_vbox.add_child(subtitle)

	# ── Spacer between subtitle and buttons ──────────────────────────────────
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 32)
	root_vbox.add_child(spacer)

	# ── Menu buttons ─────────────────────────────────────────────────────────
	var has_save: bool = FileAccess.file_exists(InputManager.SAVE_PATH)

	var items: Array[Dictionary] = [
		{"label": "New Game", "cb": _on_new_game, "enabled": true},
		{"label": "Continue", "cb": _on_continue, "enabled": has_save},
		{"label": "Options",  "cb": _on_options,  "enabled": true},
		{"label": "Quit",     "cb": _on_quit,     "enabled": true},
	]
	for item in items:
		var btn := _menu_btn(item["label"], item["enabled"])
		if item["enabled"]:
			btn.pressed.connect(item["cb"])
		root_vbox.add_child(btn)

	# ── Version label (anchored to bottom-right, outside the center column) ──
	var ver := Label.new()
	ver.text = "v0.1.0-dev"
	ver.add_theme_font_override("font", load(FONT_SUBTITLE))
	ver.add_theme_font_size_override("font_size", 11)
	ver.add_theme_color_override("font_color", C_VERSION)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position = Vector2(-90, -18)
	add_child(ver)

	# ── Options menu (lazy-instantiated overlay) ──────────────────────────────
	_options_menu = preload("res://scenes/ui/options_menu.tscn").instantiate()
	_options_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options_menu.visible = false
	_options_menu.closed.connect(_on_options_closed)
	add_child(_options_menu)

# ----------------------------------------------------------------- factory

func _menu_btn(label_text: String, enabled: bool = true) -> Button:
	var btn := Button.new()
	btn.text                = label_text
	btn.flat                = true
	btn.custom_minimum_size = Vector2(220, ITEM_H)
	btn.alignment           = HORIZONTAL_ALIGNMENT_CENTER
	btn.disabled            = not enabled
	btn.add_theme_font_override("font", load(FONT_MENU))
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color",
		C_MENU if enabled else C_MUTED)
	btn.add_theme_color_override("font_hover_color",
		C_HOVER if enabled else C_MUTED)
	btn.add_theme_color_override("font_focus_color",   C_HOVER)
	btn.add_theme_color_override("font_pressed_color", C_HOVER)
	btn.add_theme_color_override("font_disabled_color", C_MUTED)
	btn.add_theme_stylebox_override("normal",   StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover",    StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("pressed",  StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("focus",    StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	return btn

# ----------------------------------------------------------------- callbacks

func _on_new_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_continue() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_options() -> void:
	_options_menu.visible = true
	_options_menu.open()

func _on_options_closed() -> void:
	_options_menu.visible = false

func _on_quit() -> void:
	get_tree().quit()

# ----------------------------------------------------------------- controller nav

func _unhandled_input(event: InputEvent) -> void:
	# The options menu handles its own input; only act when it's closed.
	if _options_menu.visible:
		return
	if event.is_action_just_pressed("cancel"):
		_on_quit()
		get_viewport().set_input_as_handled()
