# xp_bar.gd
extends ProgressBar

@export var xp_per_level_base: int   = 15
@export var xp_level_scale:    float = 2.2  # log coefficient
@export var xp_bar_height:     int   = 65
@export var bottom_margin:     int   = 20

const LERP_SPEED:     float = 8.0
const FLASH_FADE:     float = 4.0
const PULSE_SPEED:    float = 2.5
const PARTICLE_RATE:  float = 0.04
const PARTICLE_SPEED: float = 55.0
const PARTICLE_RISE:  float = 33.0
const PARTICLE_LIFE:  float = 1.8

const GLINT_INTERVAL_MIN: float = 4.0
const GLINT_INTERVAL_MAX: float = 9.0
const GLINT_DURATION:     float = 0.55

var _fill_style:        StyleBoxFlat
var _bg_style:          StyleBoxFlat
var _display_value:     float = 0.0
var _target_value:      float = 0.0
var _flash_alpha:       float = 0.0
var _pending_level_ups: int   = 0
var _pulse_t:           float = 0.0
var _total_xp:          int   = 0
var _bar_width:         float = 0.0
var _particle_timer:    float = 0.0

# ── per-level XP tracking ─────────────────────────────────────────────────────
var _current_level:      int   = 0          # how many times the player has levelled up
var _xp_spent:           int   = 0          # total XP consumed by all past level-ups
var _current_threshold:  int   = xp_per_level_base  # XP needed for the next level-up

var _xp_label:        Label
var _yellow_backing:  ColorRect

var _glint_timer:  float          = 0.0
var _glint_active: bool           = false
var _glint_t:      float          = 0.0
var _glint_mat:    ShaderMaterial = null

var _particles: Array = []

signal leveled_up
signal pressed

func _ready() -> void:
	min_value       = 0
	max_value       = _current_threshold
	value           = 0
	show_percentage = false
	mouse_filter    = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, xp_bar_height)

	await get_tree().process_frame
	var vp_size := get_viewport().get_visible_rect().size
	_bar_width = vp_size.x * (9.0 / 10.0)
	size     = Vector2(_bar_width, xp_bar_height)
	position = Vector2((vp_size.x - _bar_width) / 2.0, vp_size.y - xp_bar_height - bottom_margin)

	_yellow_backing          = ColorRect.new()
	_yellow_backing.color    = Color(0.95, 0.75, 0.05, 0.0)
	_yellow_backing.size     = Vector2(_bar_width, xp_bar_height)
	_yellow_backing.position = position
	_yellow_backing.z_index  = -1
	_yellow_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_parent().add_child(_yellow_backing)
	get_parent().move_child(_yellow_backing, get_index())

	_bg_style = StyleBoxFlat.new()
	_bg_style.bg_color = Color(0.1, 0.1, 0.15, 0.8)
	add_theme_stylebox_override("background", _bg_style)

	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = Color(0.0, 0.4, 1.0, 1.0)
	add_theme_stylebox_override("fill", _fill_style)
	add_theme_stylebox_override("over", StyleBoxEmpty.new())

	_xp_label = Label.new()
	_xp_label.text = "0"
	_xp_label.add_theme_font_size_override("font_size", 13)
	_xp_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_xp_label.size = Vector2(_bar_width, xp_bar_height)
	_xp_label.position = Vector2.ZERO
	_xp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_xp_label)

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

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _pending_level_ups > 0:
			emit_signal("pressed")

func notify_level_up(count: int) -> void:
	_pending_level_ups = count
	if count > 0:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	_update_label()

func claim_one_level_up() -> void:
	_pending_level_ups = maxi(0, _pending_level_ups - 1)
	# State (_current_level, _xp_spent, _current_threshold) was already
	# advanced in set_xp when the level-up was detected — don't touch it here.
	var progress_xp: int = _total_xp - _xp_spent
	_display_value = 0.0
	_target_value  = float(progress_xp)
	value          = 0.0
	_flash_alpha   = 1.0
	if _pending_level_ups == 0:
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	_update_label()

func set_xp(current: int) -> void:
	_total_xp = current

	# Walk forward through thresholds, committing each level as we go
	var levels_gained := 0
	while current >= _xp_spent + _current_threshold:
		_xp_spent          += _current_threshold
		_current_level     += 1
		_current_threshold  = xp_per_level_base + int(float(xp_per_level_base) * log(float(_current_level) + 2.0) * xp_level_scale)
		max_value           = _current_threshold
		levels_gained      += 1

	_update_label()

	var progress_xp: int = current - _xp_spent
	if levels_gained > 0:
		_display_value = 0.0
		value          = 0.0
		_target_value  = float(_current_threshold) if _pending_level_ups > 0 else float(progress_xp)
		for i in levels_gained:
			emit_signal("leveled_up")
	else:
		_target_value = float(_current_threshold) if _pending_level_ups > 0 else float(progress_xp)

	_flash_alpha = 1.0

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

	if _pending_level_ups > 0:
		_pulse_t += delta * PULSE_SPEED
		var t := sin(_pulse_t) * 0.5 + 0.5
		_fill_style.bg_color   = Color(0.0, 0.4, 1.0).lerp(Color(1.0, 0.85, 0.1), t * 0.8)
		_bg_style.bg_color     = Color(0.08, 0.08, 0.12, 0.85)
		_yellow_backing.color  = Color(0.95, 0.75, 0.05, 0.25 + t * 0.25)
		_particle_timer -= delta
		if _particle_timer <= 0.0:
			_spawn_particle()
			_particle_timer = PARTICLE_RATE
	else:
		var bc := _yellow_backing.color
		if bc.a > 0.0:
			bc.a = maxf(0.0, bc.a - delta * 3.0)
			_yellow_backing.color = bc
		if _flash_alpha > 0.0:
			_flash_alpha = maxf(0.0, _flash_alpha - FLASH_FADE * delta)
			_fill_style.bg_color = Color(0.0, 0.4, 1.0).lerp(Color(1.0, 1.0, 1.0), _flash_alpha * 0.6)
			if _flash_alpha == 0.0:
				_bg_style.bg_color = Color(0.1, 0.1, 0.15, 0.8)

	_tick_glint(delta)

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

func _update_label() -> void:
	if _pending_level_ups == 1:
		_xp_label.text = "LEVEL UP"
	elif _pending_level_ups > 1:
		_xp_label.text = "LEVEL UP x%d" % _pending_level_ups
	else:
		var progress_xp: int = _total_xp - _xp_spent
		_xp_label.text = "%d / %d" % [progress_xp, _current_threshold]
