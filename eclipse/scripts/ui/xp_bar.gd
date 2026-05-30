# xp_bar.gd
extends ProgressBar

@export var xp_per_level:  int = 50
@export var xp_bar_height: int = 48

const LERP_SPEED:   float = 8.0
const FLASH_FADE:   float = 4.0
const LEVELUP_HOLD: float = 0.3

var _fill_style:        StyleBoxFlat
var _display_value:     float = 0.0
var _target_value:      float = 0.0
var _flash_alpha:       float = 0.0
var _levelup_timer:     float = 0.0
var _pending_remainder: int   = 0

func _ready() -> void:
	min_value       = 0
	max_value       = xp_per_level
	value           = 0
	show_percentage = false
	custom_minimum_size = Vector2(0, 12)

	await get_tree().process_frame
	var vp_size := get_viewport().get_visible_rect().size
	size     = Vector2(vp_size.x, xp_bar_height)
	position = Vector2(0, vp_size.y - xp_bar_height)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.15, 0.8)
	add_theme_stylebox_override("background", bg)

	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = Color(0.0, 0.4, 1.0, 1.0)
	add_theme_stylebox_override("fill", _fill_style)

	add_theme_stylebox_override("over", StyleBoxEmpty.new())

func set_xp(current: int) -> void:
	var new_target := current % xp_per_level
	if current > 0 and new_target < _target_value:
		_pending_remainder = new_target
		_target_value      = xp_per_level
		_levelup_timer     = LEVELUP_HOLD
	else:
		_target_value = new_target
	_flash_alpha = 1.0

func _process(delta: float) -> void:
	if _levelup_timer > 0.0:
		_levelup_timer -= delta
		if _levelup_timer <= 0.0:
			_flash_alpha   = 1.0
			_display_value = 0.0
			_target_value  = _pending_remainder

	_display_value = lerpf(_display_value, _target_value, LERP_SPEED * delta)
	if absf(_display_value - _target_value) < 0.2:
		_display_value = _target_value
	value = _display_value

	_flash_alpha = maxf(0.0, _flash_alpha - FLASH_FADE * delta)
	_fill_style.bg_color = Color(0.0, 0.4, 1.0).lerp(Color(1.0, 1.0, 1.0), _flash_alpha * 0.6)
