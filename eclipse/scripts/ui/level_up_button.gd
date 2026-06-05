# level_up_button.gd
# Add as a Control node named "LevelUpButton" in your HUD CanvasLayer.
extends Control

signal pressed

const PULSE_SPEED: float = 3.0

var _btn:        Button
var _btn_style:  StyleBoxFlat
var _badge:      Label
var _active:     bool  = false
var _pulse_t:    float = 0.0
var _count:      int   = 0

func _ready() -> void:
	process_mode               = Node.PROCESS_MODE_ALWAYS
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visible      = false

	await get_tree().process_frame
	var vp_size := get_viewport().get_visible_rect().size

	_btn_style                           = StyleBoxFlat.new()
	_btn_style.bg_color                  = Color(0.15, 0.3, 0.9, 1.0)
	_btn_style.corner_radius_top_left    = 8
	_btn_style.corner_radius_top_right   = 8
	_btn_style.corner_radius_bottom_left = 8
	_btn_style.corner_radius_bottom_right = 8
	_btn_style.border_color              = Color(0.6, 0.85, 1.0, 1.0)
	_btn_style.set_border_width_all(2)

	var hover_style                           := StyleBoxFlat.new()
	hover_style.bg_color                       = Color(0.25, 0.45, 1.0, 1.0)
	hover_style.corner_radius_top_left         = 8
	hover_style.corner_radius_top_right        = 8
	hover_style.corner_radius_bottom_left      = 8
	hover_style.corner_radius_bottom_right     = 8
	hover_style.border_color                   = Color(0.8, 0.95, 1.0, 1.0)
	hover_style.set_border_width_all(2)

	_btn                      = Button.new()
	_btn.text                 = "LEVEL UP"
	_btn.custom_minimum_size  = Vector2(160.0, 48.0)
	_btn.add_theme_stylebox_override("normal",  _btn_style)
	_btn.add_theme_stylebox_override("hover",   hover_style)
	_btn.add_theme_stylebox_override("pressed", hover_style)
	_btn.add_theme_color_override("font_color", Color.WHITE)
	_btn.add_theme_font_size_override("font_size", 16)
	_btn.pressed.connect(_on_btn_pressed)
	add_child(_btn)

	# Centered horizontally, just above the xp bar
	_btn.position = Vector2(
		(vp_size.x - _btn.custom_minimum_size.x) / 2.0,
		vp_size.y - 48.0 - _btn.custom_minimum_size.y - 8.0
	)

	# Badge — small circle in the top-right corner of the button showing pending count
	var badge_size := 22.0
	_badge = Label.new()
	_badge.add_theme_font_size_override("font_size", 12)
	_badge.add_theme_color_override("font_color", Color.WHITE)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_badge.size = Vector2(badge_size, badge_size)
	_badge.position = _btn.position + Vector2(_btn.custom_minimum_size.x - badge_size / 2.0, -badge_size / 2.0)
	_badge.visible = false

	var badge_bg := StyleBoxFlat.new()
	badge_bg.bg_color = Color(0.9, 0.2, 0.15, 1.0)
	badge_bg.corner_radius_top_left    = int(badge_size / 2)
	badge_bg.corner_radius_top_right   = int(badge_size / 2)
	badge_bg.corner_radius_bottom_left = int(badge_size / 2)
	badge_bg.corner_radius_bottom_right = int(badge_size / 2)
	_badge.add_theme_stylebox_override("normal", badge_bg)
	add_child(_badge)

# count = total pending level-ups (including this one)
func notify_level_up(count: int = 1) -> void:
	_count   = count
	_active  = true
	visible  = true
	_pulse_t = 0.0
	_update_badge()

func _update_badge() -> void:
	if _badge == null:
		return
	if _count > 1:
		_badge.text    = str(_count)
		_badge.visible = true
	else:
		_badge.visible = false

func _on_btn_pressed() -> void:
	_active = false
	visible = false
	if _badge:
		_badge.visible = false
	emit_signal("pressed")

func _process(delta: float) -> void:
	if not _active:
		return
	_pulse_t += delta * PULSE_SPEED
	var t := sin(_pulse_t) * 0.5 + 0.5
	_btn_style.border_color = Color(0.4, 0.7, 1.0).lerp(Color(1.0, 1.0, 1.0), t * 0.5)
