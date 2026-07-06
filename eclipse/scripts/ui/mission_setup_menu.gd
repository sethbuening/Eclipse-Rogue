# mission_setup_menu.gd
# Order: BIOME+DEPTH (radial planet) -> CLASS -> confirm.
extends CanvasLayer

const FONT_TITLE: String = "res://assets/fonts/Orbitron-Bold.ttf"
const FONT_MENU:  String = "res://assets/fonts/Rajdhani-SemiBold.ttf"
const FONT_UI:    String = "res://assets/fonts/ShareTechMono-Regular.ttf"

const C_BG:             Color = Color(0.01, 0.03, 0.05, 1.0)
const C_TITLE:          Color = Color("#a0e8f0")
const C_LABEL:          Color = Color("#7ac8d8")
const C_HOVER:          Color = Color("#e0f8ff")
const C_CARD_BG:        Color = Color("#040e14")
const C_CARD_BG_HOVER:  Color = Color("#0a1e28")
const C_CARD_BORDER:    Color = Color("#0e3850")
const C_CARD_BORDER_SEL:Color = Color("#00b4cc")
const C_DISABLED:       Color = Color("#1e3a40")

# Only 2 steps now: PLANET (biome+depth combined) and CLASS
enum Step { PLANET, CLASS }

signal mission_confirmed(biome: BiomeData, depth: int, char_class: ClassData)
signal cancelled

var _step: Step = Step.PLANET
var _selected_depth: int       = -1
var _selected_biome: BiomeData = null
var _selected_class: ClassData = null

var _breadcrumb:  Label   = null
var _content:     Control = null
var _back_btn:    Button  = null

var _nav_buttons: Array[Button] = []
var _nav_index:   int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build()

func open() -> void:
	_step           = Step.PLANET
	_selected_depth = -1
	_selected_biome = null
	_selected_class = null
	_render_step()

func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	add_child(bg)

	var top_bar := Control.new()
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_bar)

	_breadcrumb = Label.new()
	_breadcrumb.position = Vector2(28, 24)
	_breadcrumb.add_theme_font_override("font", load(FONT_UI))
	_breadcrumb.add_theme_font_size_override("font_size", 14)
	_breadcrumb.add_theme_color_override("font_color", C_LABEL)
	top_bar.add_child(_breadcrumb)

	_back_btn = _footer_btn("← BACK")
	_back_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_back_btn.position = Vector2(28, -72)
	_back_btn.pressed.connect(_on_back)
	top_bar.add_child(_back_btn)

	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_content)

	top_bar.get_parent().move_child(top_bar, -1)

func _on_back() -> void:
	match _step:
		Step.PLANET: cancelled.emit()
		Step.CLASS:  _step = Step.PLANET; _render_step()

func _on_next() -> void:
	match _step:
		Step.PLANET:
			if _selected_depth < 0 or _selected_biome == null: return
			_step = Step.CLASS; _render_step()
		Step.CLASS:
			if _selected_class == null: return
			mission_confirmed.emit(_selected_biome, _selected_depth, _selected_class)

# ── rendering ─────────────────────────────────────────────────────────────────

func _render_step() -> void:
	for c in _content.get_children(): c.queue_free()
	for c in get_children():
		if c is _PlanetPicker: c.queue_free()
	_nav_buttons.clear()
	_nav_index = 0

	match _step:
		Step.PLANET: _render_planet_step()
		Step.CLASS:  _render_class_step()

	_nav_buttons.append(_back_btn)
	_ctrl_refresh_focus()

	var steps := ["BIOME + DEPTH", "CLASS"]
	var idx   := int(_step)
	var parts: Array = []
	for i in steps.size():
		if i < idx:    parts.append("[done] " + steps[i])
		elif i == idx: parts.append("▶ " + steps[i])
		else:          parts.append("· " + steps[i])
	_breadcrumb.text = "  /  ".join(parts)

# ── PLANET: combined biome+depth radial picker ────────────────────────────────

func _render_planet_step() -> void:
	var depth_labels := ["Trivial", "Easy", "Moderate", "Hard", "Extreme"]
	var depth_colors := [
		Color("#2a9d5c"), Color("#8ab520"), Color("#d4a017"),
		Color("#d06020"), Color("#cc2222")
	]

	var node := _PlanetPicker.new()
	node.position = Vector2.ZERO
	node.biomes       = MissionContent.get_biomes()
	node.depth_labels = depth_labels
	node.depth_colors = depth_colors
	node.sel_depth    = _selected_depth
	node.sel_biome    = _selected_biome
	node.menu_font    = load(FONT_MENU)
	node.title_font   = load(FONT_TITLE)
	node.sector_chosen.connect(func(biome: BiomeData, depth: int):
		_selected_biome = biome
		_selected_depth = depth
		node.sel_biome  = biome
		node.sel_depth  = depth
		node.queue_redraw()
		var t := get_tree().create_timer(0.35)
		t.timeout.connect(_on_next))
	add_child(node)

# ── CLASS step ────────────────────────────────────────────────────────────────

func _render_class_step() -> void:
	var title := Label.new()
	title.text = "SELECT CLASS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 60; title.offset_bottom = 110
	title.add_theme_font_override("font", load(FONT_TITLE))
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", C_TITLE)
	_content.add_child(title)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 110
	_content.add_child(center)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	center.add_child(grid)

	for char_class: ClassData in MissionContent.get_classes():
		var card := _option_card(char_class.display_name, char_class.description, Color.WHITE)
		card.pressed.connect(func():
			_selected_class = char_class
			_select_card(card)
			_on_next())
		grid.add_child(card)
		if _selected_class == char_class: _select_card(card)
		_nav_buttons.append(card)

# ── shared widgets ────────────────────────────────────────────────────────────

func _option_card(title_text: String, desc_text: String, accent: Color) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(280, 96)
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.text = title_text + "\n" + desc_text
	card.add_theme_font_override("font", load(FONT_UI))
	card.add_theme_font_size_override("font_size", 13)
	card.add_theme_color_override("font_color", C_LABEL)
	card.add_theme_color_override("font_hover_color", C_HOVER)
	card.add_theme_stylebox_override("normal",  _card_style(false, accent))
	card.add_theme_stylebox_override("hover",   _card_style(false, accent, true))
	card.add_theme_stylebox_override("pressed", _card_style(true, accent))
	card.add_theme_stylebox_override("focus",   _card_style(false, accent, true))
	card.set_meta("selected", false)
	var idx := _nav_buttons.size()
	card.mouse_entered.connect(func(): _nav_index = idx; card.grab_focus())
	card.focus_entered.connect(func(): _nav_index = idx)
	return card

func _select_card(selected: Button) -> void:
	for c in selected.get_parent().get_children():
		if c is Button:
			c.set_meta("selected", c == selected)
			var accent := C_CARD_BORDER_SEL if c == selected else C_CARD_BORDER
			c.add_theme_stylebox_override("normal", _card_style(c == selected, accent))

func _card_style(selected: bool, accent: Color, hover: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color     = C_CARD_BG_HOVER if (hover or selected) else C_CARD_BG
	s.border_color = C_CARD_BORDER_SEL if selected else C_CARD_BORDER
	s.set_border_width_all(2 if selected else 1)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(12)
	return s

func _footer_btn(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(140, 44)
	btn.add_theme_font_override("font", load(FONT_MENU))
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", C_LABEL)
	btn.add_theme_color_override("font_hover_color", C_HOVER)
	btn.add_theme_color_override("font_disabled_color", C_DISABLED)
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	return btn

# ── input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
	if event.is_action_pressed("cancel"):
		_on_back(); get_viewport().set_input_as_handled(); return
	if   event.is_action_pressed("ui_navigate_right"): _ctrl_navigate(1)
	elif event.is_action_pressed("ui_navigate_left"):  _ctrl_navigate(-1)
	elif event.is_action_pressed("ui_navigate_down"):  _ctrl_navigate(1)
	elif event.is_action_pressed("ui_navigate_up"):    _ctrl_navigate(-1)
	elif event.is_action_pressed("confirm"):
		if _nav_index < _nav_buttons.size() and not _nav_buttons[_nav_index].disabled:
			_nav_buttons[_nav_index].emit_signal("pressed")
	else: return
	get_viewport().set_input_as_handled()

func _ctrl_navigate(dir: int) -> void:
	if _nav_buttons.is_empty(): return
	_nav_index = (_nav_index + dir + _nav_buttons.size()) % _nav_buttons.size()
	_ctrl_refresh_focus()

func _ctrl_refresh_focus() -> void:
	if _nav_buttons.is_empty(): return
	_nav_buttons[_nav_index].grab_focus()

# ═══════════════════════════════════════════════════════════════════════════════
# Inner class: Combined planet picker (5 biome slices × 5 depth rings = 25 sectors)
# ═══════════════════════════════════════════════════════════════════════════════
class _PlanetPicker extends Control:
	signal sector_chosen(biome: BiomeData, depth: int)

	var biomes:       Array        = []   # Array[BiomeData]
	var depth_labels: Array        = []
	var depth_colors: Array        = []
	var sel_depth:    int          = -1
	var sel_biome:    BiomeData    = null
	var menu_font:    Font         = null
	var title_font:   Font         = null

	var _hov_biome_i: int = -1
	var _hov_depth_i: int = -1

	const STEPS := 40   # arc subdivisions per sector

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		call_deferred("_apply_size")

	func _apply_size() -> void:
		var v := get_viewport().get_visible_rect().size
		set_position(Vector2.ZERO); set_size(v); queue_redraw()

	func _vp()     -> Vector2: return get_viewport().get_visible_rect().size
	func _origin() -> Vector2: var v := _vp(); return Vector2(v.x * 0.5, v.y)

	# Ring radii for depth index i (0=outermost/easiest, 4=innermost/hardest)
	func _ring_radii(i: int) -> Vector2:
		var depth_count := maxi(biomes.size(), 1)
		# 70% of viewport height → outermost arc peak sits ~30% down from top, leaving room for title
		var max_r := _vp().y * 0.70
		var step  := max_r / depth_count
		var outer := max_r - step * i
		var inner := outer - step
		return Vector2(maxf(inner, 0.0), outer)

	# Angle span per biome sector, centered on top (PI*1.5 = straight up)
	# Biomes spread across the full semicircle (PI) centered upward
	# Each biome gets a equal angular slice of PI radians total
	func _biome_angles(bi: int) -> Vector2:
		var n     := maxi(biomes.size(), 1)
		var span  := PI          # total arc = half circle
		var start := PI - PI * 0.5  # leftmost angle (pointing left = PI)
		# Distribute evenly: biome 0 is leftmost, biome n-1 is rightmost
		# Angles in Godot: right=0, up=-PI/2, left=PI
		# We want left-to-right across the top
		# "straight up from center" = angle -PI/2 in standard coords
		# Our origin is at bottom-center. Angles measured from positive-x axis.
		# Up from origin = angle -PI/2 (or 270 deg)
		# We want biomes arranged left → right, outermost ring = surface of planet
		# Full planet arc: from angle PI (left) to angle 0 (right)
		var a0 := PI - (PI / n) * bi
		var a1 := PI - (PI / n) * (bi + 1)
		return Vector2(a1, a0)  # a1 < a0 (going counter-clockwise = left to right visually)

	func _point_in_sector(pt: Vector2, bi: int, di: int) -> bool:
		var o   := _origin()
		var rel := pt - o
		# Must be in upper half (y < 0 relative to origin, plus small tolerance)
		if rel.y > 8.0: return false
		var r  := rel.length()
		var rr := _ring_radii(di)
		if r < rr.x or r > rr.y: return false
		var ang := fposmod(atan2(rel.y, rel.x), TAU)
		var aa  := _biome_angles(bi)
		# aa is in [0, PI] range; atan2 for upper half gives angles in (PI, 2PI) ... actually
		# atan2(-y, x) where y is screen y. In Godot screen coords y increases downward.
		# rel.y < 0 means point is ABOVE origin on screen = upper half
		# atan2(rel.y, rel.x) for upper half gives negative values [-PI, 0]
		# normalise to [PI, 2*PI] via fposmod
		# Our _biome_angles returns angles in [0, PI], so we need to remap.
		# Simpler: just use atan2 directly and compare in [-PI, 0] space.
		var a := atan2(rel.y, rel.x)  # in [-PI, 0] for upper half
		# _biome_angles gives [0,PI]. Map: our a_screen = -a_math  =>  a_math = -a_screen
		# aa.x and aa.y are math angles. a_screen = atan2(rel.y,rel.x).
		# Upper half: a_screen in (-PI, 0). Math angle = PI + a_screen? No.
		# Let's just redefine angles in terms of screen atan2 directly:
		# leftmost = atan2(0, -1) = PI (or -PI), rightmost = atan2(0,1)=0
		# So screen angle for "left edge" = PI/-PI, "right edge" = 0, "top" = -PI/2
		# Biome angles in screen space: evenly spaced from -PI to 0
		var n  := maxi(biomes.size(), 1)
		var sa0 := -PI + (PI / n) * bi        # left edge of this biome slice
		var sa1 := -PI + (PI / n) * (bi + 1)  # right edge
		return a >= sa0 and a <= sa1

	func _draw() -> void:
		var o        := _origin()
		var n_biomes := biomes.size()
		var n_depths := depth_colors.size()

		# Title — drawn first, will never be overlapped (it's above the arc)
		if title_font:
			var txt := "SELECT BIOME & DEPTH"
			var tw  := title_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			draw_string(title_font, Vector2(o.x - tw * 0.5, 38),
				txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("#a0e8f0"))

		# Pass 1: hover/selection fills (behind lines)
		for di in n_depths:
			var rr      := _ring_radii(di)
			var inner_r := rr.x
			var outer_r := rr.y
			for bi in n_biomes:
				var biome: BiomeData = biomes[bi]
				var is_sel := (sel_depth == di + 1 and sel_biome == biome)
				var is_hov := (_hov_depth_i == di and _hov_biome_i == bi)
				if not is_sel and not is_hov: continue
				var sa0  := -PI + (PI / n_biomes) * bi
				var sa1  := -PI + (PI / n_biomes) * (bi + 1)
				var fill := Color(biome.tint)
				fill.a   = 0.30 if is_sel else 0.16
				var pts  := PackedVector2Array()
				for s in (STEPS + 1):
					var a := sa0 + (sa1 - sa0) * s / STEPS
					pts.append(o + Vector2(cos(a), sin(a)) * outer_r)
				for s in (STEPS + 1):
					var a := sa1 - (sa1 - sa0) * s / STEPS
					pts.append(o + Vector2(cos(a), sin(a)) * (inner_r if inner_r > 1.0 else 0.0))
				draw_colored_polygon(pts, fill)

		# Pass 2a: base lines for every sector (non-hover, non-sel)
		for di in n_depths:
			var rr      := _ring_radii(di)
			var inner_r := rr.x
			var outer_r := rr.y
			for bi in n_biomes:
				var biome: BiomeData = biomes[bi]
				var is_sel := (sel_depth == di + 1 and sel_biome == biome)
				var is_hov := (_hov_depth_i == di and _hov_biome_i == bi)
				if is_sel or is_hov: continue  # drawn in 2b
				var sa0 := -PI + (PI / n_biomes) * bi
				var sa1 := -PI + (PI / n_biomes) * (bi + 1)
				var bc  := Color(0.10, 0.42, 0.58, 1.0)
				var bw  := 2.5
				var prev := o + Vector2(cos(sa0), sin(sa0)) * outer_r
				for s in range(1, STEPS + 1):
					var a   := sa0 + (sa1 - sa0) * s / STEPS
					var cur := o + Vector2(cos(a), sin(a)) * outer_r
					draw_line(prev, cur, bc, bw); prev = cur
				if inner_r > 1.0:
					prev = o + Vector2(cos(sa0), sin(sa0)) * inner_r
					for s in range(1, STEPS + 1):
						var a   := sa0 + (sa1 - sa0) * s / STEPS
						var cur := o + Vector2(cos(a), sin(a)) * inner_r
						draw_line(prev, cur, bc, bw); prev = cur
				var r0 := inner_r if inner_r > 1.0 else 0.0
				draw_line(o + Vector2(cos(sa0), sin(sa0)) * r0,
						  o + Vector2(cos(sa0), sin(sa0)) * outer_r, bc, bw)
				draw_line(o + Vector2(cos(sa1), sin(sa1)) * r0,
						  o + Vector2(cos(sa1), sin(sa1)) * outer_r, bc, bw)

		# Pass 2b: hover and selected sector lines — drawn after all base lines
		for di in n_depths:
			var rr      := _ring_radii(di)
			var inner_r := rr.x
			var outer_r := rr.y
			for bi in n_biomes:
				var biome: BiomeData = biomes[bi]
				var is_sel := (sel_depth == di + 1 and sel_biome == biome)
				var is_hov := (_hov_depth_i == di and _hov_biome_i == bi)
				if not is_sel and not is_hov: continue
				var sa0 := -PI + (PI / n_biomes) * bi
				var sa1 := -PI + (PI / n_biomes) * (bi + 1)
				var bc  := Color("#00e5ff") if is_sel else biome.tint.lightened(0.3)
				var bw  := 5.0 if is_sel else 3.5
				var prev := o + Vector2(cos(sa0), sin(sa0)) * outer_r
				for s in range(1, STEPS + 1):
					var a   := sa0 + (sa1 - sa0) * s / STEPS
					var cur := o + Vector2(cos(a), sin(a)) * outer_r
					draw_line(prev, cur, bc, bw); prev = cur
				if inner_r > 1.0:
					prev = o + Vector2(cos(sa0), sin(sa0)) * inner_r
					for s in range(1, STEPS + 1):
						var a   := sa0 + (sa1 - sa0) * s / STEPS
						var cur := o + Vector2(cos(a), sin(a)) * inner_r
						draw_line(prev, cur, bc, bw); prev = cur
				var r0 := inner_r if inner_r > 1.0 else 0.0
				draw_line(o + Vector2(cos(sa0), sin(sa0)) * r0,
						  o + Vector2(cos(sa0), sin(sa0)) * outer_r, bc, bw)
				draw_line(o + Vector2(cos(sa1), sin(sa1)) * r0,
						  o + Vector2(cos(sa1), sin(sa1)) * outer_r, bc, bw)

		# Pass 3: all labels drawn on top of every line
		if menu_font == null: return

		# Pass 3: biome name labels — outside the outermost arc, angle-aware push-out
		if menu_font == null: return
		var outer_r := _ring_radii(0).y
		for bi in n_biomes:
			var sa0   := -PI + (PI / n_biomes) * bi
			var sa1   := -PI + (PI / n_biomes) * (bi + 1)
			var mid_a := (sa0 + sa1) * 0.5
			var biome: BiomeData = biomes[bi]
			var is_sel := (sel_biome == biome)
			var lcol   := biome.tint.lightened(0.4) if is_sel else C_LABEL
			var lbl    := biome.display_name
			var font_size := 18
			var ls     := menu_font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			# Angle-aware push: near-horizontal slices (|cos| large) need extra radial clearance
			# so the text half-width doesn't overlap the arc line
			var horiz_factor : float = abs(cos(mid_a))           # 0 at top, 1 at sides
			var base_gap     : float = 28.0
			var extra_gap    : float = horiz_factor * ls.x * 0.55
			var label_r      : float = outer_r + base_gap + extra_gap
			var lpos  : Vector2 = o + Vector2(cos(mid_a), sin(mid_a)) * label_r
			draw_string(menu_font, lpos - Vector2(ls.x * 0.5, ls.y * 0.3),
				lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, lcol)

		# Center dot
		draw_circle(o, 6.0, Color("#00b4cc", 0.8))

	func _input(event: InputEvent) -> void:
		if not visible: return
		var mpos := get_viewport().get_mouse_position()
		if event is InputEventMouseMotion:
			var old_bi := _hov_biome_i; var old_di := _hov_depth_i
			_hov_biome_i = -1; _hov_depth_i = -1
			var n_biomes := biomes.size(); var n_depths := depth_colors.size()
			for di in n_depths:
				for bi in n_biomes:
					if _point_in_sector(mpos, bi, di):
						_hov_biome_i = bi; _hov_depth_i = di; break
				if _hov_biome_i >= 0: break
			if _hov_biome_i != old_bi or _hov_depth_i != old_di:
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var n_biomes := biomes.size(); var n_depths := depth_colors.size()
			for di in n_depths:
				for bi in n_biomes:
					if _point_in_sector(mpos, bi, di):
						sector_chosen.emit(biomes[bi], di + 1)
						get_viewport().set_input_as_handled()
						return
