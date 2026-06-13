# hud_control_hints.gd
# ---------------------------------------------------------------------------
# Draws three input hint pairs above the XP bar when no menu is open.
# Shown hints (left side):   Inventory/Node Graph,  Throw Flare
# Shown hints (right side):  Pause
#
# Switches automatically between keyboard glyphs and Xbox controller glyphs
# based on Util.last_input_device, same as OrbGraphMenu.
#
# Setup:
#   1. Add a Control node that covers the full viewport in your HUD scene.
#   2. Attach this script.
#   3. That's it — no wiring needed.  The node reads Util.last_input_device
#      and redraws on input_device_changed automatically.
#
# The hint bar sits at:
#   y  =  viewport_height - xp_bar_height - xp_bottom_margin - HINT_BAR_H - HINT_BOTTOM_GAP
# These constants match xp_bar.gd exactly — update both if you change the XP bar.
# ---------------------------------------------------------------------------
extends Control

# ── match xp_bar.gd exports ───────────────────────────────────────────────────
const XP_BAR_HEIGHT:    int = 65
const XP_HOVER_EXPAND:  int = 14   # HOVER_EXPAND from xp_bar.gd
# Floor = max top edge of the xp bar (fully expanded hover state)
const XP_FLOOR:         int = XP_BAR_HEIGHT + XP_HOVER_EXPAND

# ── match hud_node_graph.gd positioning ──────────────────────────────────────
const NODE_GRAPH_SCREEN_INSET: int   = 8
# Approximate panel height — hint bar stacks above it regardless of exact size.
# Node graph bottom = vp.y - XP_FLOOR - NODE_GRAPH_SCREEN_INSET
var _node_graph: Control = null   # optionally wire for exact height; falls back to estimate

# ── hint bar layout ───────────────────────────────────────────────────────────
const HINT_BAR_H:      float = 64.0    # height of the hint strip
const HINT_BOTTOM_GAP: float = 32.0    # gap between hint strip and top of XP bar
const HINT_ICON_SIZE:  Vector2 = Vector2(52.0, 52.0)
const HINT_FONT_SIZE:  int     = 19
const HINT_PAIR_GAP:   float   = 8.0   # gap between icon and its label
const SIDE_MARGIN:     float   = 24.0  # distance from left/right screen edge

const BG_COLOR:   Color = Color(0.0, 0.0, 0.0, 0.45)
const TEXT_COLOR: Color = Color(1.0, 1.0, 1.0, 0.80)

# ── action names — must match your InputMap ───────────────────────────────────
# Update these if you rename the actions.
const ACTION_PAUSE:     String = "pause"
const ACTION_INVENTORY: String = "open_graph"

# ── menus that suppress the hint bar ─────────────────────────────────────────
# The hint bar hides itself whenever any of these CanvasLayer nodes is visible.
# Add more node paths here if you add other menus.
const SUPPRESSED_BY: Array[NodePath] = [
	# Filled in _ready from group lookups — see _is_any_menu_open()
]

# ── state ─────────────────────────────────────────────────────────────────────
var _font: Font

# ── lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	Util.input_device_changed.connect(queue_redraw)

func _process(_delta: float) -> void:
	# Queue a redraw every frame so the bar appears/disappears immediately
	# when a menu opens or closes without needing an explicit signal.
	queue_redraw()

# ── draw ──────────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _is_any_menu_open():
		return

	var vp: Vector2 = size

	# ── vertical position: just above the node graph panel ───────────────────
	# Node graph bottom = vp.y - XP_FLOOR - NODE_GRAPH_SCREEN_INSET
	var graph_h: float = 0.0
	if _node_graph != null and _node_graph.custom_minimum_size.y > 0.0:
		graph_h = _node_graph.custom_minimum_size.y
	else:
		graph_h = 220.0   # conservative fallback

	var graph_bottom: float = vp.y - XP_FLOOR - NODE_GRAPH_SCREEN_INSET
	var bar_y: float        = graph_bottom - graph_h - HINT_BOTTOM_GAP - HINT_BAR_H
	var icon_y: float       = bar_y + (HINT_BAR_H - HINT_ICON_SIZE.y) * 0.5
	var text_y: float       = bar_y + (HINT_BAR_H + HINT_FONT_SIZE * 0.7) * 0.5

	# ── hints are left-anchored above the node graph ──────────────────────────
	var all_hints: Array = [
		[ACTION_INVENTORY, "Inventory"],
		[ACTION_PAUSE,     "Pause"],
	]

	var total_w: float  = _measure_hints_width(all_hints)
	var bg_x:   float   = NODE_GRAPH_SCREEN_INSET - 8.0
	draw_rect(Rect2(bg_x, bar_y, total_w + 16.0, HINT_BAR_H), BG_COLOR)

	var x: float = float(NODE_GRAPH_SCREEN_INSET)
	for i in range(all_hints.size()):
		x = _draw_hint(all_hints[i][0], all_hints[i][1], x, icon_y, text_y)
		if i < all_hints.size() - 1:
			x += HINT_PAIR_GAP * 2.0


# ── draw one [icon + label] pair, returns x after the label ──────────────────

func _draw_hint(action: String, label: String, x: float, icon_y: float, text_y: float) -> float:
	var icon: Texture2D = Util.get_action_icon(action, false)

	if icon != null:
		draw_texture_rect(icon, Rect2(Vector2(x, icon_y), HINT_ICON_SIZE), false)
		x += HINT_ICON_SIZE.x + HINT_PAIR_GAP
	else:
		# Fallback: draw a bracketed key name if no icon is available.
		var fallback: String = _fallback_label(action)
		var fw: float = _font.get_string_size(
			fallback, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE).x
		draw_string(_font, Vector2(x, text_y), fallback,
			HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE, Color(1.0, 1.0, 0.5, 0.85))
		x += fw + HINT_PAIR_GAP

	draw_string(_font, Vector2(x, text_y), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE, TEXT_COLOR)
	x += _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE).x
	return x


# ── helpers ───────────────────────────────────────────────────────────────────

## Total pixel width of a list of [action, label] pairs including inter-group gaps.
func _measure_hints_width(hints: Array) -> float:
	var total: float = 0.0
	for i in range(hints.size()):
		var action: String = hints[i][0]
		var label:  String = hints[i][1]
		var icon: Texture2D = Util.get_action_icon(action, false)
		if icon != null:
			total += HINT_ICON_SIZE.x + HINT_PAIR_GAP
		else:
			total += _font.get_string_size(
				_fallback_label(action), HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE).x + HINT_PAIR_GAP
		total += _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE).x
		if i < hints.size() - 1:
			total += HINT_PAIR_GAP * 2.0
	return total

## Returns a short readable string for an action when no icon exists.
## E.g. "pause" → "[Esc]" on keyboard, "[Start]" on controller.
func _fallback_label(action: String) -> String:
	var is_ctrl: bool = Util.last_input_device == Util.InputDevice.CONTROLLER
	for event in InputMap.action_get_events(action):
		var is_controller: bool = event is InputEventJoypadButton \
			or event is InputEventJoypadMotion
		if is_controller != is_ctrl:
			continue
		if event is InputEventKey:
			return "[%s]" % OS.get_keycode_string(event.keycode)
		elif event is InputEventJoypadButton:
			return "[%d]" % (event as InputEventJoypadButton).button_index
	return "[?]"

## Returns true if any menu that should suppress these hints is currently open.
## Checks the orb graph menu and the forge UI by group name — add more as needed.
func _is_any_menu_open() -> bool:
	# OrbGraphMenu registers itself with process_mode ALWAYS and is hidden when closed.
	for node in get_tree().get_nodes_in_group("menus"):
		if node is CanvasLayer and (node as CanvasLayer).visible:
			return true
	# Also check common named nodes directly as a fallback.
	var graph: Node = get_node_or_null("%OrbGraphMenu")
	if graph != null and graph.visible:
		return true
	var forge: Node = get_node_or_null("%ForgeUI")
	if forge != null and forge.visible:
		return true
	return false
