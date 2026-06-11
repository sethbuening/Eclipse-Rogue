# health_progress.gd
extends Control

@export var bar_height:    float = 48.0
# xp_bar_height = xp bar height (65) + bottom_margin (20) + xp->health gap (20)
@export var xp_bar_height: int   = 105

const GHOST_DELAY:      float = 0.25
const GHOST_LERP_SPEED: float = 3.0
const FLASH_SPEED:      float = 6.0

# Glint timing
const GLINT_INTERVAL_MIN: float = 5.0
const GLINT_INTERVAL_MAX: float = 11.0
const GLINT_DURATION:     float = 0.5

var _ghost_bar:   ProgressBar
var _ghost_fill:  StyleBoxFlat
var _health_bar:  ProgressBar
var _ghost_value: float = 100.0
var _ghost_timer: float = 0.0
var _flash_t:     float = 0.0
var _bar_width:   float = 0.0

# Glint — a full-bar ColorRect child with blend_add shader on top of _health_bar
var _glint_timer:  float          = 0.0
var _glint_active: bool           = false
var _glint_t:      float          = 0.0
var _glint_mat:    ShaderMaterial = null

# ── hover lift ────────────────────────────────────────────────────────────────
const HOVER_LIFT:       float = 8.0
const HOVER_LIFT_SPEED: float = 10.0

var _base_y:     float = 0.0
var _hover_lift: float = 0.0
var _is_hovered: bool  = false

func _ready() -> void:
	await get_tree().process_frame
	var vp_size := get_viewport().get_visible_rect().size
	_bar_width = vp_size.x * (1.0 / 2.0)
	size     = Vector2(_bar_width, bar_height)
	position = Vector2((vp_size.x - _bar_width) / 2.0, vp_size.y - xp_bar_height - bar_height)
	_base_y  = position.y

	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: _is_hovered = true)
	mouse_exited.connect( func() -> void: _is_hovered = false)

	# Ghost bar — behind, flashing orange/white
	_ghost_bar               = ProgressBar.new()
	_ghost_bar.modulate      = Color(1.0, 1.0, 1.0, 1.0)
	_ghost_bar.min_value     = 0
	_ghost_bar.max_value     = 100
	_ghost_bar.value         = 100
	_ghost_bar.show_percentage = false
	_ghost_bar.size          = size
	_ghost_bar.position      = Vector2.ZERO
	var ghost_bg             := StyleBoxFlat.new()
	ghost_bg.bg_color        = Color(0.0, 0.0, 0.0, 0.0)
	_ghost_bar.add_theme_stylebox_override("background", ghost_bg)
	_ghost_fill              = StyleBoxFlat.new()
	_ghost_fill.bg_color     = Color(1.0, 0.5, 0.0, 1.0)
	_ghost_bar.add_theme_stylebox_override("fill", _ghost_fill)
	_ghost_bar.add_theme_stylebox_override("over", StyleBoxEmpty.new())
	_ghost_bar.add_theme_font_size_override("font_size", 0)
	add_child(_ghost_bar)

	# Health bar — on top, red
	_health_bar              = ProgressBar.new()
	_health_bar.min_value    = 0
	_health_bar.max_value    = 100
	_health_bar.value        = 100
	_health_bar.show_percentage = false
	_health_bar.size         = size
	_health_bar.position     = Vector2.ZERO
	var bg                   := StyleBoxFlat.new()
	bg.bg_color              = Color(0.0, 0.0, 0.0, 0.0)
	_health_bar.add_theme_stylebox_override("background", bg)
	var fill                 := StyleBoxFlat.new()
	fill.bg_color            = Color(0.85, 0.1, 0.1, 1.0)
	_health_bar.add_theme_stylebox_override("fill", fill)
	_health_bar.add_theme_font_size_override("font_size", 0)
	add_child(_health_bar)

	# Glint overlay — full-bar ColorRect added last so it draws above the bars.
	# blend_add means it only ever brightens; pixels outside fill_ratio emit nothing.
	var shader        := load("res://scripts/ui/bar_glint.gdshader") as Shader
	_glint_mat        = ShaderMaterial.new()
	_glint_mat.shader = shader
	_glint_mat.set_shader_parameter("glint_phase",  0.0)
	_glint_mat.set_shader_parameter("fill_ratio",   1.0)
	_glint_mat.set_shader_parameter("glint_color",  Color(1.0, 0.75, 0.65, 0.32))
	_glint_mat.set_shader_parameter("streak_width", 0.07)
	_glint_mat.set_shader_parameter("skew",         0.18)

	var overlay              := ColorRect.new()
	overlay.color             = Color.WHITE
	overlay.size              = Vector2(_bar_width, bar_height)
	overlay.position          = Vector2.ZERO
	overlay.material          = _glint_mat
	overlay.mouse_filter      = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	_glint_timer = randf_range(GLINT_INTERVAL_MIN, GLINT_INTERVAL_MAX)

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

	# Flash ghost bar between orange and white
	_flash_t = fmod(_flash_t + delta * FLASH_SPEED, 1.0)
	var t := _flash_t if _flash_t < 0.5 else 1.0 - _flash_t
	t *= 2.0
	_ghost_fill.bg_color = Color(1.0, 0.35, 0.0, 1.0).lerp(Color(1.0, 1.0, 1.0, 1.0), t)

	# Delay then lerp ghost down to actual health
	if _ghost_timer > 0.0:
		_ghost_timer -= delta
	elif _ghost_value > _health_bar.value:
		_ghost_value = lerpf(_ghost_value, _health_bar.value, GHOST_LERP_SPEED * delta)
		if absf(_ghost_value - _health_bar.value) < 0.5:
			_ghost_value = _health_bar.value
	_ghost_bar.value = _ghost_value

	# Keep fill_ratio in sync so the glint never overruns the red portion
	if _glint_mat and _health_bar.max_value > 0.0:
		_glint_mat.set_shader_parameter("fill_ratio",
			_health_bar.value / _health_bar.max_value)

	_tick_glint(delta)

	var lift_target: float = HOVER_LIFT if _is_hovered else 0.0
	_hover_lift = lerpf(_hover_lift, lift_target, HOVER_LIFT_SPEED * delta)
	if absf(_hover_lift - lift_target) < 0.3:
		_hover_lift = lift_target
	position.y = _base_y - _hover_lift

func _tick_glint(delta: float) -> void:
	if _glint_mat == null:
		return

	if _glint_active:
		_glint_t += delta / GLINT_DURATION
		if _glint_t >= 1.0:
			_glint_active = false
			_glint_t      = 0.0
			_glint_mat.set_shader_parameter("glint_phase", 0.0)
			_glint_timer  = randf_range(GLINT_INTERVAL_MIN, GLINT_INTERVAL_MAX)
		else:
			_glint_mat.set_shader_parameter("glint_phase", _glint_t)
	else:
		_glint_timer -= delta
		if _glint_timer <= 0.0:
			var fill_ratio := _health_bar.value / _health_bar.max_value
			if fill_ratio > 0.1:
				_glint_active = true
				_glint_t      = 0.0
			else:
				_glint_timer = randf_range(GLINT_INTERVAL_MIN, GLINT_INTERVAL_MAX)
