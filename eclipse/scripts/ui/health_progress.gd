# health_bar.gd
extends Control

@export var bar_height:    float = 48.0
@export var xp_bar_height: int   = 48

const GHOST_DELAY:      float = 0.6
const GHOST_LERP_SPEED: float = 3.0
const FLASH_SPEED: float = 6.0

var _ghost_bar:   ProgressBar
var _ghost_fill:  StyleBoxFlat
var _health_bar:  ProgressBar
var _ghost_value: float = 100.0
var _ghost_timer: float = 0.0
var _flash_t:     float = 0.0

func _ready() -> void:
	await get_tree().process_frame
	var vp_size := get_viewport().get_visible_rect().size
	var bar_width := vp_size.x * (1.0 / 2.0)
	size     = Vector2(bar_width, bar_height)
	position = Vector2((vp_size.x - bar_width) / 2.0, vp_size.y - xp_bar_height - bar_height)

	# Ghost bar — behind, flashing orange/white
	_ghost_bar            = ProgressBar.new()
	_ghost_bar.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_ghost_bar.min_value  = 0
	_ghost_bar.max_value  = 100
	_ghost_bar.value      = 100
	_ghost_bar.show_percentage = false
	_ghost_bar.size       = size
	_ghost_bar.position   = Vector2.ZERO
	var ghost_bg := StyleBoxFlat.new()
	ghost_bg.bg_color = Color(0.0, 0.0, 0.0, 0.0)  # fully transparent, nothing to bleed through
	_ghost_bar.add_theme_stylebox_override("background", ghost_bg)
	_ghost_fill = StyleBoxFlat.new()
	_ghost_fill.bg_color = Color(1.0, 0.5, 0.0, 1.0)
	_ghost_bar.add_theme_stylebox_override("fill", _ghost_fill)
	_ghost_bar.add_theme_stylebox_override("over", StyleBoxEmpty.new())
	add_child(_ghost_bar)

	# Health bar — on top, red
	_health_bar            = ProgressBar.new()
	_health_bar.min_value  = 0
	_health_bar.max_value  = 100
	_health_bar.value      = 100
	_health_bar.show_percentage = false
	_health_bar.size       = size
	_health_bar.position   = Vector2.ZERO
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	_health_bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.1, 0.1, 1.0)
	_health_bar.add_theme_stylebox_override("fill", fill)
	add_child(_health_bar)

func set_health(current: float, maximum: float = 100.0) -> void:
	if _health_bar == null:
		return
	_health_bar.max_value = maximum
	_ghost_bar.max_value  = maximum
	if current < _health_bar.value:
		_ghost_timer = GHOST_DELAY
	_health_bar.value = current

func _process(delta: float) -> void:
	if _ghost_bar == null:
		return

	# Flash the ghost bar between orange and white forever
	_flash_t = fmod(_flash_t + delta * FLASH_SPEED, 1.0)
	var t := _flash_t if _flash_t < 0.5 else 1.0 - _flash_t
	t *= 2.0  # remap 0–0.5 to 0–1
	_ghost_fill.bg_color = Color(1.0, 0.35, 0.0, 1.0).lerp(Color(1.0, 1.0, 1.0, 1.0), t)

	# Delay then lerp ghost down to actual health
	if _ghost_timer > 0.0:
		_ghost_timer -= delta
	elif _ghost_value > _health_bar.value:
		_ghost_value = lerpf(_ghost_value, _health_bar.value, GHOST_LERP_SPEED * delta)
		if absf(_ghost_value - _health_bar.value) < 0.5:
			_ghost_value = _health_bar.value
	_ghost_bar.value = _ghost_value
