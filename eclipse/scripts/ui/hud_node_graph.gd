class_name HudNodeGraph
extends Control

# ── wiring ────────────────────────────────────────────────────────────────────
# In game.gd _ready(), add:
#   %HudNodeGraph.player        = %Player
#   %HudNodeGraph.graph_manager = %GraphManager

@onready var player:        CharacterBody2D = $"../../Player"
@onready var graph_manager: Node            = $"../../GraphManager"

# ── positioning ───────────────────────────────────────────────────────────────
# XP bar is full viewport width, flush to the bottom.
# We reserve XP_BAR_HEIGHT + XP_HOVER_EXPAND so the HUD never overlaps
# even when the bar is fully expanded on hover.
const XP_BAR_HEIGHT:   int = 65    # must match xp_bar_height in xp_bar.gd
const XP_HOVER_EXPAND: int = 14    # must match HOVER_EXPAND in xp_bar.gd
const SCREEN_INSET:    int = 8     # gap from screen/xp-bar edges

# Total vertical floor the HUD must sit above
const XP_FLOOR: int = XP_BAR_HEIGHT + XP_HOVER_EXPAND

# ── layout ────────────────────────────────────────────────────────────────────
const PANEL_PAD:  float   = 14.0
const NODE_R:     float   = 28.0
const RING_W:     float   = 5.0
const CONN_W:     float   = 2.5
const ICON_SIZE:  Vector2 = Vector2(30.0, 30.0)
const LABEL_SIZE: int     = 9
const CHARGE_SIZE:int     = 8
const SPREAD_R:   float   = 80.0

# ── colors ────────────────────────────────────────────────────────────────────
const C_BG:            Color = Color(0.06, 0.07, 0.10, 0.82)
const C_NODE_EMPTY:    Color = Color(0.18, 0.20, 0.28, 1.0)
const C_NODE_FILLED:   Color = Color(0.22, 0.35, 0.58, 1.0)
const C_CONN_INACTIVE: Color = Color(0.25, 0.28, 0.38, 0.6)
const C_CONN_ACTIVE:   Color = Color(0.35, 0.95, 0.55, 1.0)
const C_RING_TRACK:    Color = Color(0.10, 0.12, 0.18, 1.0)
const C_RING_FILL:     Color = Color(0.30, 0.65, 1.00, 1.0)
const C_RING_READY:    Color = Color(0.35, 0.95, 0.55, 0.55)
const C_RING_EMPTY:    Color = Color(0.25, 0.28, 0.38, 0.55)
const C_LABEL:         Color = Color(0.85, 0.90, 1.00, 0.90)
const C_LABEL_DIM:     Color = Color(0.45, 0.50, 0.65, 0.80)
const C_CHARGE:        Color = Color(1.00, 0.88, 0.30, 1.0)
const C_DIM:           Color = Color(0.05, 0.05, 0.10, 0.55)

# ── internal ──────────────────────────────────────────────────────────────────
var _node_positions: Array[Vector2] = []
var _panel_size:     Vector2        = Vector2(200.0, 200.0)

# ── setup ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	mouse_filter        = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = _panel_size
	# Anchor to bottom-left corner so offset math is straightforward
	anchor_left   = 0.0
	anchor_top    = 1.0
	anchor_right  = 0.0
	anchor_bottom = 1.0
	get_viewport().size_changed.connect(_reposition)
	_reposition()

func _reposition() -> void:
	# HUD sits just above the xp bar's max possible top edge (including hover expand).
	offset_left   = SCREEN_INSET
	offset_top    = -(XP_FLOOR + _panel_size.y + SCREEN_INSET)
	offset_right  = offset_left + _panel_size.x
	offset_bottom = offset_top  + _panel_size.y

func _process(_delta: float) -> void:
	_recompute_layout()
	queue_redraw()

# ── layout ────────────────────────────────────────────────────────────────────

func _recompute_layout() -> void:
	if graph_manager == null:
		return
	var nodes: Array = graph_manager.graph.nodes
	var count: int   = nodes.size()
	if count == 0:
		return

	_node_positions.resize(count)

	for i in range(count):
		var angle: float = (float(i) / float(count)) * TAU - PI * 0.5
		_node_positions[i] = Vector2(cos(angle), sin(angle)) * (0.0 if count == 1 else SPREAD_R)

	# Bounding box
	var min_x: float =  INF;  var max_x: float = -INF
	var min_y: float =  INF;  var max_y: float = -INF
	var margin: float = NODE_R + RING_W + LABEL_SIZE + 8.0
	for p in _node_positions:
		min_x = minf(min_x, p.x - margin)
		max_x = maxf(max_x, p.x + margin)
		min_y = minf(min_y, p.y - margin)
		max_y = maxf(max_y, p.y + margin)

	# Shift positions so everything sits inside the padded panel
	var offset: Vector2 = Vector2(-min_x + PANEL_PAD, -min_y + PANEL_PAD)
	for i in range(count):
		_node_positions[i] += offset

	_panel_size         = Vector2(max_x - min_x + PANEL_PAD * 2.0,
								  max_y - min_y + PANEL_PAD * 2.0)
	custom_minimum_size = _panel_size
	_reposition()

# ── draw ──────────────────────────────────────────────────────────────────────

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font

	# Always draw background so it's visible even when not yet wired
	draw_rect(Rect2(Vector2.ZERO, _panel_size), C_BG)
	draw_rect(Rect2(Vector2.ZERO, _panel_size), Color(1, 1, 1, 0.07), false, 1.0)

	if graph_manager == null or _node_positions.is_empty():
		# Not wired yet — draw a placeholder
		draw_string(font, Vector2(PANEL_PAD, _panel_size.y * 0.5 + 5),
			"no graph", HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, C_LABEL_DIM)
		return

	var nodes:       Array = graph_manager.graph.nodes
	var connections: Array = graph_manager.graph.connections

	# ── connections ───────────────────────────────────────────────────────────
	for conn in connections:
		if conn.from_node >= _node_positions.size() or conn.to_node >= _node_positions.size():
			continue
		var a: Vector2 = _node_positions[conn.from_node]
		var b: Vector2 = _node_positions[conn.to_node]

		var active: bool = nodes[conn.from_node].placed_orb != null \
			and nodes[conn.to_node].placed_orb != null \
			and conn.charge_stacks > 0
		var col: Color = C_CONN_ACTIVE if active else C_CONN_INACTIVE

		# Shorten so line doesn't overdraw the circles
		var dir: Vector2 = (b - a).normalized()
		draw_line(a + dir * (NODE_R + RING_W + 2.0),
				  b - dir * (NODE_R + RING_W + 2.0), col, CONN_W)

		# Arrowhead at midpoint
		var mid:  Vector2 = (a + b) * 0.5
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([
			mid + dir  * 6.0,
			mid - dir  * 4.0 + perp * 4.0,
			mid - dir  * 4.0 - perp * 4.0,
		]), col)

		if active and conn.charge_stacks > 0:
			draw_string(font, mid + perp * 10.0 - Vector2(4.0, 4.0),
				"×%d" % conn.charge_stacks,
				HORIZONTAL_ALIGNMENT_LEFT, -1, CHARGE_SIZE, C_CHARGE)

	# ── nodes ─────────────────────────────────────────────────────────────────
	for i in range(nodes.size()):
		if i >= _node_positions.size():
			break
		var node:   GraphNodeData = nodes[i]
		var center: Vector2       = _node_positions[i]
		var orb:    Orb           = node.placed_orb

		# Cooldown fraction: 1.0 = just fired (full arc), 0.0 = ready (no arc)
		var cd_frac: float = 0.0
		if orb != null and player != null:
			var ov = player._orb_visual_map.get(orb, null)
			if ov != null and ov.cooldown > 0.0:
				cd_frac = clampf(1.0 - (ov.cooldown_age / ov.cooldown), 0.0, 1.0)

		var on_cooldown: bool = cd_frac > 0.001
		var is_dimmed:   bool = on_cooldown or orb == null

		# Node fill
		var fill_col: Color = C_NODE_FILLED if orb != null else C_NODE_EMPTY
		if on_cooldown:
			fill_col = fill_col.lerp(Color(0.06, 0.07, 0.10), 0.5)
		draw_circle(center, NODE_R, fill_col)

		# Ring track
		var ring_r: float = NODE_R + RING_W * 0.5 + 1.0
		draw_arc(center, ring_r, 0.0, TAU, 64, C_RING_TRACK, RING_W)

		if on_cooldown:
			# Arc fills clockwise from top, draining as orb recharges
			var start: float = -PI * 0.5
			draw_arc(center, ring_r, start, start + cd_frac * TAU,
				max(8, int(cd_frac * 64)), C_RING_FILL, RING_W)
		else:
			# Ready: full ring — green if filled, gray if empty
			var ring_col: Color = C_RING_READY if orb != null else C_RING_EMPTY
			draw_arc(center, ring_r, 0.0, TAU, 64, ring_col, RING_W)

		# Dim overlay while on cooldown or slot is empty
		if is_dimmed:
			draw_circle(center, NODE_R - 1.0, C_DIM)

		# Orb icon
		if orb != null and orb.sprite_texture != null:
			var tint: Color = Color(1, 1, 1, 0.40) if on_cooldown else Color.WHITE
			draw_texture_rect(orb.sprite_texture,
				Rect2(center - ICON_SIZE * 0.5, ICON_SIZE), false, tint)
		elif orb == null:
			draw_line(center - Vector2(7, 0), center + Vector2(7, 0),
				Color(1, 1, 1, 0.15), 1.5)

		# Orb name below node
		if orb != null:
			var s:  String = _short_name(orb.display_name)
			var tw: float  = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
			draw_string(font, center + Vector2(-tw * 0.5, NODE_R + RING_W + 10.0),
				s, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE,
				C_LABEL_DIM if on_cooldown else C_LABEL)

		# Stat name above node
		var ss:  String = node.stat_name.replace("_", " ")
		var stw: float  = font.get_string_size(ss, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
		draw_string(font, center + Vector2(-stw * 0.5, -NODE_R - RING_W - 4.0),
			ss, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE,
			C_LABEL_DIM if is_dimmed else C_LABEL)

# ── helpers ───────────────────────────────────────────────────────────────────

func _short_name(s: String) -> String:
	return s if s.length() <= 10 else s.substr(0, 9) + "…"
