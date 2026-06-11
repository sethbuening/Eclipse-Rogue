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

# ── XP gain convergence particles ─────────────────────────────────────────────
# Lightweight dict-based particles (no scene nodes) that spawn on XP gain and
# physically home toward the leading fill edge as it moves to the right.
const XP_PARTICLE_COUNT:    int   = 22    # spawned per XP gain event
const XP_PARTICLE_LIFE_MIN: float = 0.45
const XP_PARTICLE_LIFE_MAX: float = 0.85
const XP_ATTRACT_STRENGTH:  float = 480.0  # pull toward edge (px/s²)
const XP_SCATTER_X:         float = 55.0   # max right-of-edge scatter on spawn
const XP_SCATTER_Y:         float = 26.0   # vertical scatter on spawn
const XP_SPEED_MIN:         float = 90.0
const XP_SPEED_MAX:         float = 210.0
const XP_PARTICLE_RADIUS:   float = 3.2

# Two blue anchor colours — particles sample randomly between them
const XP_COLOR_A: Color = Color(0.30, 0.60, 1.00, 1.0)   # deep sapphire
const XP_COLOR_B: Color = Color(0.70, 0.90, 1.00, 1.0)   # bright ice

# Edge glow: a thin bright rect drawn on top of the fill tip each frame
const EDGE_GLOW_WIDTH: float = 3.0

var _fill_style:        StyleBoxFlat
var _bg_style:          StyleBoxFlat
var _border_style:      StyleBoxFlat
var _display_value:     float = 0.0
var _target_value:      float = 0.0
var _flash_alpha:       float = 0.0
var _pending_level_ups: int   = 0
var _pulse_t:           float = 0.0
var _total_xp:          int   = 0
var _bar_width:         float = 0.0
var _particle_timer:    float = 0.0

# ── per-level XP tracking ─────────────────────────────────────────────────────
var _current_level:      int   = 0
var _xp_spent:           int   = 0
var _current_threshold:  int   = xp_per_level_base

var _xp_label:        Label

var _glint_timer:  float          = 0.0
var _glint_active: bool           = false
var _glint_t:      float          = 0.0
var _glint_mat:    ShaderMaterial = null

# Level-up burst ColorRect particles (existing system, kept for level-up pulse)
var _particles: Array = []

# XP-gain convergence particles (new — dict-based, drawn via _draw)
var _xp_particles:     Array = []
var _xp_stream_active: bool  = false   # true while display is chasing target
var _xp_stream_timer:  float = 0.0    # drip timer for continuous stream

# Aura overlay behind the bar
var _aura_mat:    ShaderMaterial = null
var _aura_rect:   ColorRect      = null

# ── hover expand ──────────────────────────────────────────────────────────────
const HOVER_EXPAND:     float = 14.0
const HOVER_LIFT_SPEED: float = 10.0

var _base_y:        float = 0.0
var _hover_expand:  float = 0.0
var _is_hovered:    bool  = false

var _border_panel:  Panel = null

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
	_bar_width = vp_size.x
	size     = Vector2(_bar_width, xp_bar_height)
	position = Vector2(0.0, vp_size.y - xp_bar_height)
	_base_y  = position.y

	mouse_entered.connect(func() -> void: _is_hovered = true)
	mouse_exited.connect( func() -> void: _is_hovered = false)

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
	max_value = _current_threshold
	var progress_xp: int = _total_xp - _xp_spent
	_display_value = 0.0
	value          = 0.0
	if _pending_level_ups > 0:
		_target_value = float(_current_threshold)
	else:
		_target_value = float(progress_xp)
	_flash_alpha = 1.0
	if _pending_level_ups == 0:
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	_update_label()

func set_xp(current: int) -> void:
	var prev_total: int = _total_xp
	_total_xp = current

	# Walk forward through thresholds
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
		_target_value  = float(_current_threshold)
		for i in levels_gained:
			emit_signal("leveled_up")
	else:
		_target_value = float(_current_threshold) if _pending_level_ups > 0 else float(progress_xp)

	_flash_alpha = 1.0

	# Spawn convergence particles whenever XP actually increased
	if current > prev_total:
		_xp_stream_active = true
		_xp_stream_timer  = 0.0
		_spawn_xp_particles()

# ── XP convergence particle spawn ─────────────────────────────────────────────
func _spawn_xp_particles() -> void:
	var edge_x: float  = (_display_value / float(_current_threshold)) * _bar_width
	var bar_cy: float  = xp_bar_height * 0.5

	for i in range(XP_PARTICLE_COUNT):
		# Spawn in a tight band just right of the fill edge (the adjacent empty region)
		var px: float = edge_x + randf_range(4.0 + XP_SCATTER_X * 1.5, XP_SCATTER_X * 2.5)
		# Start above or below the bar centre — they fall/rise into it
		var side:  float = 1.0 if randf() > 0.5 else -1.0
		var py: float = bar_cy + side * randf_range(XP_SCATTER_Y * 0.4, XP_SCATTER_Y)

		# Strong leftward velocity so they clearly travel into the fill edge
		var speed: float = randf_range(XP_SPEED_MIN, XP_SPEED_MAX)
		var vx:    float = -speed                              # always left
		var vy:    float = -side * speed * randf_range(0.25, 0.55)  # fall toward centre

		# Interpolate colour between the two blue anchors
		var t:   float = randf()
		var col: Color = XP_COLOR_A.lerp(XP_COLOR_B, t)

		_xp_particles.append({
			"pos":      Vector2(px, py),
			"vel":      Vector2(vx, vy),
			"age":      0.0,
			"lifetime": randf_range(XP_PARTICLE_LIFE_MIN, XP_PARTICLE_LIFE_MAX),
			"color":    col,
		})

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

	if _pending_level_ups > 0:
		_pulse_t += delta * PULSE_SPEED
		var t := sin(_pulse_t) * 0.5 + 0.5
		var bar_color := Color(0.0, 0.4, 1.0).lerp(Color(1.0, 0.85, 0.1), t * 0.8)
		_fill_style.bg_color = bar_color
		_bg_style.bg_color   = Color(0.08, 0.08, 0.12, 0.85)
		_border_style.border_color = Color(0.45, 0.45, 0.50, 0.75).lerp(
			Color(1.0, 0.88, 0.15, 1.0), t)
		_particle_timer -= delta
		if _particle_timer <= 0.0:
			_spawn_particle()
			_particle_timer = PARTICLE_RATE
	else:
		if _flash_alpha > 0.0:
			_flash_alpha = maxf(0.0, _flash_alpha - FLASH_FADE * delta)
			_fill_style.bg_color = Color(0.0, 0.4, 1.0).lerp(Color(1.0, 1.0, 1.0), _flash_alpha * 0.6)
			if _flash_alpha == 0.0:
				_bg_style.bg_color = Color(0.1, 0.1, 0.15, 0.8)
		_border_style.border_color = _border_style.border_color.lerp(
			Color(0.45, 0.45, 0.50, 0.75), delta * 3.0)

	_tick_glint(delta)
	_tick_xp_particles(delta)
	_update_aura(delta)

	# ── continuous particle stream while bar is filling ────────────────────────
	# Keep dripping particles as long as the visual fill is still moving.
	# Once it catches up to the target we switch the stream off.
	if _xp_stream_active:
		if absf(_display_value - _target_value) < 0.5:
			_xp_stream_active = false
		else:
			_xp_stream_timer -= delta
			if _xp_stream_timer <= 0.0:
				_xp_stream_timer = 0.04   # one small burst every 40 ms
				_spawn_xp_particles()

	# ── hover expand ──────────────────────────────────────────────────────────
	var expand_target: float = HOVER_EXPAND if _is_hovered else 0.0
	_hover_expand = lerpf(_hover_expand, expand_target, HOVER_LIFT_SPEED * delta)
	if absf(_hover_expand - expand_target) < 0.3:
		_hover_expand = expand_target
	var new_h: float = xp_bar_height + _hover_expand
	size      = Vector2(_bar_width, new_h)
	position.y = _base_y - _hover_expand
	if _border_panel:
		_border_panel.size = Vector2(_bar_width, new_h)

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

# ── XP convergence particle tick ──────────────────────────────────────────────
func _tick_xp_particles(delta: float) -> void:
	var edge_x: float = (_display_value / float(_current_threshold)) * _bar_width
	var bar_cy: float = xp_bar_height * 0.5
	var target: Vector2 = Vector2(edge_x, bar_cy)

	var alive: Array = []
	for p in _xp_particles:
		p["age"] += delta
		if p["age"] >= p["lifetime"]:
			continue

		# Attract toward the fill edge; strength ramps up as particle ages
		# so they accelerate into the tip rather than flying past it.
		var age_frac: float  = p["age"] / p["lifetime"]
		var pull:     float  = XP_ATTRACT_STRENGTH * (0.5 + age_frac * 1.2)
		var diff:     Vector2 = target - p["pos"]
		if diff.length_squared() > 1.0:
			p["vel"] += diff.normalized() * pull * delta

		# Drag particles down to 40% speed once they enter the filled section
		var current_edge: float = (_display_value / float(_current_threshold)) * _bar_width
		if p["pos"].x < current_edge:
			p["vel"] = p["vel"].lerp(Vector2.ZERO, 0.08)

		p["pos"] += p["vel"] * delta
		alive.append(p)

	_xp_particles = alive

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

	# XP convergence particles
	for p in _xp_particles:
		var age_t:  float = p["age"] / p["lifetime"]
		var alpha:  float
		if age_t < 0.15:
			alpha = age_t / 0.15
		else:
			alpha = 1.0 - smoothstep(0.5, 1.0, age_t)
		var radius: float = XP_PARTICLE_RADIUS * (1.0 - age_t * 0.35)
		# Darken particles that have crossed into the filled section
		var in_fill:    bool  = p["pos"].x < edge_x
		var brightness: float = 0.75 if in_fill else 1.0
		var col: Color = Color(
			p["color"].r * brightness,
			p["color"].g * brightness,
			p["color"].b * brightness,
			alpha
		)
		draw_circle(p["pos"], radius, col)

# ── Aura glow driven by fill ratio & flash ────────────────────────────────────
func _update_aura(_delta: float) -> void:
	if _aura_mat == null:
		return
	var fill_ratio: float = _display_value / float(_current_threshold)
	# Aura fades in as the bar fills; gets a bonus during flash or level-up pulse
	var base_alpha: float = fill_ratio * 0.13
	var bonus:      float = _flash_alpha * 0.10
	if _pending_level_ups > 0:
		bonus = maxf(bonus, 0.10)
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
		if _pending_level_ups == 0:
			_glint_mat.set_shader_parameter("glint_phase", 0.0)
			return
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
