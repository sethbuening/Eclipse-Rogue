# xp_bar.gd
extends ProgressBar

@export var xp_per_level_base: int   = 15
@export var xp_level_scale:    float = 2.2  # log coefficient
@export var xp_bar_height:     int   = 65
@export var bottom_margin:     int   = 0

const LERP_SPEED:     float = 8.0
const FLASH_FADE:     float = 4.0
const PULSE_SPEED:    float = 2.5
const PARTICLE_RATE:  float = 0.02
const PARTICLE_SPEED: float = 55.0
const PARTICLE_RISE:  float = 33.0
const PARTICLE_LIFE:  float = 1.8

const GLINT_INTERVAL_MIN: float = 4.0
const GLINT_INTERVAL_MAX: float = 9.0
const GLINT_DURATION:     float = 0.55

# Edge glow: a thin bright rect drawn on top of the fill tip each frame
const EDGE_GLOW_WIDTH: float = 3.0

var _fill_style:        StyleBoxFlat
var _bg_style:          StyleBoxFlat
var _border_style:      StyleBoxFlat
var _display_value:     float = 0.0
var _target_value:      float = 0.0
var _flash_alpha:       float = 0.0
var _total_xp:          int   = 0
var _bar_width:         float = 0.0

# ── per-level XP tracking ─────────────────────────────────────────────────────
var _current_level:      int   = 0
var _xp_spent:           int   = 0
var _current_threshold:  int   = xp_per_level_base

var _glint_timer:  float          = 0.0
var _glint_active: bool           = false
var _glint_t:      float          = 0.0
var _glint_mat:    ShaderMaterial = null

# Level-up burst ColorRect particles (existing system, kept for level-up pulse)
var _particles: Array = []

# Aura overlay behind the bar
var _aura_mat:    ShaderMaterial = null
var _aura_rect:   ColorRect      = null

var _border_panel:  Panel = null

signal leveled_up

func _ready() -> void:
	min_value       = 0
	max_value       = _current_threshold
	value           = 0
	show_percentage = false
	mouse_filter    = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, xp_bar_height)

	await get_tree().process_frame
	var vp_size := get_viewport().get_visible_rect().size
	_bar_width = vp_size.x
	size     = Vector2(_bar_width, xp_bar_height)
	position = Vector2(0.0, vp_size.y - xp_bar_height)

	_bg_style = StyleBoxFlat.new()
	_bg_style.bg_color = Color(0.1, 0.1, 0.15, 0.8)
	add_theme_stylebox_override("background", _bg_style)

	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = Color(0.0, 0.4, 1.0, 1.0)
	add_theme_stylebox_override("fill", _fill_style)
	add_theme_stylebox_override("over", StyleBoxEmpty.new())

	# ── Aura glow behind the bar ──────────────────────────────────────────────
	# bar_aura.gdshader is an additive feathered glow; we put it BEHIND the bar
	# by adding it as the first child (z_index -1 relative to parent).
	const AURA_OVERHANG: float = 18.0   # bleed above the bar top
	var aura_shader := load("res://scripts/ui/bar_aura.gdshader") as Shader
	_aura_mat        = ShaderMaterial.new()
	_aura_mat.shader = aura_shader
	_aura_mat.set_shader_parameter("aura_color",  Color(0.0, 0.4, 1.0, 1.0))
	_aura_mat.set_shader_parameter("alpha",       0.0)
	_aura_mat.set_shader_parameter("falloff_x",   2.2)
	_aura_mat.set_shader_parameter("falloff_y",   4.5)

	_aura_rect          = ColorRect.new()
	_aura_rect.color    = Color.WHITE
	_aura_rect.size     = Vector2(_bar_width, xp_bar_height + AURA_OVERHANG * 2.0)
	_aura_rect.position = Vector2(0.0, -AURA_OVERHANG)
	_aura_rect.material = _aura_mat
	_aura_rect.z_index  = -1
	_aura_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_aura_rect)

	# Border panel
	_border_style = StyleBoxFlat.new()
	_border_style.bg_color     = Color(0, 0, 0, 0)
	_border_style.border_color = Color(0.55, 0.55, 0.60, 0.90)
	_border_style.set_border_width_all(3)
	_border_panel = Panel.new()
	_border_panel.add_theme_stylebox_override("panel", _border_style)
	_border_panel.size         = Vector2(_bar_width, xp_bar_height)
	_border_panel.position     = Vector2.ZERO
	_border_panel.z_index      = 10
	_border_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_border_panel)

	var shader     := load("res://scripts/ui/bar_glint.gdshader") as Shader
	_glint_mat     = ShaderMaterial.new()
	_glint_mat.shader = shader
	_glint_mat.set_shader_parameter("glint_phase",  0.0)
	_glint_mat.set_shader_parameter("fill_ratio",   0.0)
	_glint_mat.set_shader_parameter("glint_color",  Color(1.0, 1.0, 1.0, 0.38))
	_glint_mat.set_shader_parameter("streak_width", 0.07)
	_glint_mat.set_shader_parameter("skew",         0.18)

	var overlay          := ColorRect.new()
	overlay.color         = Color.WHITE
	overlay.size          = Vector2(_bar_width, xp_bar_height)
	overlay.position      = Vector2.ZERO
	overlay.material      = _glint_mat
	overlay.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	_glint_timer = randf_range(GLINT_INTERVAL_MIN, GLINT_INTERVAL_MAX)

func set_xp(current: int) -> void:
	_total_xp = current

	# Walk forward through thresholds
	var levels_gained := 0
	while current >= _xp_spent + _current_threshold:
		_xp_spent          += _current_threshold
		_current_level     += 1
		_current_threshold  = xp_per_level_base + int(float(xp_per_level_base) * log(float(_current_level) + 2.0) * xp_level_scale)
		max_value           = _current_threshold
		levels_gained      += 1

	var progress_xp: int = current - _xp_spent
	if levels_gained > 0:
		_display_value = 0.0
		value          = 0.0
		_target_value  = float(_current_threshold)
		for i in levels_gained:
			emit_signal("leveled_up")
	else:
		_target_value = float(progress_xp)

	_flash_alpha = 1.0

# ── Level-up burst particle (original ColorRect system) ───────────────────────
func _spawn_particle() -> void:
	var orb_size := randf_range(3.0, 7.0)
	var orb      := ColorRect.new()
	orb.color    = _fill_style.bg_color
	orb.size     = Vector2(orb_size, orb_size)
	var px := randf_range(0.0, _bar_width - orb_size)
	var py := randf_range(0.0, xp_bar_height * 2.0 - orb_size)
	orb.position = Vector2(px, py)
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center_x := _bar_width / 2.0
	var vx := PARTICLE_SPEED * randf_range(0.5, 1.5)
	if px < center_x:
		vx = -vx
	var vy := -PARTICLE_RISE * randf_range(0.6, 1.4)
	add_child(orb)
	_particles.append([orb, vx, vy, PARTICLE_LIFE])

func _process(delta: float) -> void:
	var prev := _display_value
	_display_value = lerpf(_display_value, _target_value, LERP_SPEED * delta)
	if absf(_display_value - _target_value) < 0.2:
		_display_value = _target_value
	if _display_value != prev:
		value = _display_value

	if _glint_mat:
		_glint_mat.set_shader_parameter("fill_ratio",
			_display_value / float(_current_threshold))

	if _flash_alpha > 0.0:
		_flash_alpha = maxf(0.0, _flash_alpha - FLASH_FADE * delta)
		_fill_style.bg_color = Color(0.0, 0.4, 1.0).lerp(Color(1.0, 1.0, 1.0), _flash_alpha * 0.6)
		if _flash_alpha == 0.0:
			_bg_style.bg_color = Color(0.1, 0.1, 0.15, 0.8)
	_border_style.border_color = _border_style.border_color.lerp(
		Color(0.45, 0.45, 0.50, 0.75), delta * 3.0)

	_tick_glint(delta)
	_update_aura(delta)
	# Tick ColorRect level-up burst particles
	var i := _particles.size() - 1
	while i >= 0:
		var p     = _particles[i]
		var orb:  ColorRect = p[0]
		var vx:   float     = p[1]
		var vy:   float     = p[2]
		var life: float     = p[3]
		life -= delta
		_particles[i][3] = life
		orb.position += Vector2(vx, vy) * delta
		var c   = _fill_style.bg_color
		c.a     = clampf(life / PARTICLE_LIFE, 0.0, 1.0)
		orb.color = c
		if life <= 0.0:
			orb.queue_free()
			_particles.remove_at(i)
		i -= 1

	queue_redraw()

# ── _draw: render XP convergence particles on top of the ProgressBar ──────────
func _draw() -> void:
	var edge_x: float = (_display_value / float(_current_threshold)) * _bar_width

	# Soft edge glow strip at the fill tip
	if edge_x > EDGE_GLOW_WIDTH:
		var glow_col: Color = Color(
			_fill_style.bg_color.r,
			_fill_style.bg_color.g,
			_fill_style.bg_color.b,
			0.55
		)
		draw_rect(
			Rect2(edge_x - EDGE_GLOW_WIDTH, 0.0, EDGE_GLOW_WIDTH * 2.0, xp_bar_height),
			glow_col
		)

# ── Aura glow driven by fill ratio & flash ────────────────────────────────────
func _update_aura(_delta: float) -> void:
	if _aura_mat == null:
		return
	var fill_ratio: float = _display_value / float(_current_threshold)
	var base_alpha: float = fill_ratio * 0.13
	var bonus:      float = _flash_alpha * 0.10
	_aura_mat.set_shader_parameter("alpha", base_alpha + bonus)
	_aura_mat.set_shader_parameter("aura_color", _fill_style.bg_color)

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
			var fill_ratio := _display_value / float(_current_threshold)
			if fill_ratio > 0.05:
				_glint_active = true
				_glint_t      = 0.0
			else:
				_glint_timer = randf_range(GLINT_INTERVAL_MIN, GLINT_INTERVAL_MAX)
