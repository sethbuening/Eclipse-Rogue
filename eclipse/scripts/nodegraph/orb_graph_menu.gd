class_name OrbGraphMenu
extends CanvasLayer

# ── references ────────────────────────────────────────────────────────────────
var player: CharacterBody2D

@onready var graph_manager: Node = %GraphManager

# ── ui state ──────────────────────────────────────────────────────────────────
var selected_orb:          Orb     = null
var dragging_orb:          Orb     = null
var drag_origin_node:      int     = -1
var drag_pos:              Vector2 = Vector2.ZERO
var hover_node:            int     = -1
var pressed_inventory_orb: Orb     = null
var inventory_press_pos:   Vector2 = Vector2.ZERO

const DRAG_THRESHOLD: float = 8.0
const MAX_ORB_SLOTS:  int   = 5

var orb_display_order: Array[Orb] = []

var _orb_tooltip:     OrbTooltip     = null
var _ability_tooltip: AbilityTooltip = null

var _kb_reassigning_orb: Orb = null

# ── controller navigation ─────────────────────────────────────────────────────

enum FocusPanel { GRAPH, LIST }

var ctrl_panel:        FocusPanel = FocusPanel.GRAPH
var ctrl_node:         int        = 0
var ctrl_list:         int        = 0
var ctrl_held_orb:     Orb        = null
var ctrl_held_from:    int        = -1

# Slot reassign mode: entered with RT on any focused orb.
var ctrl_reassigning:  bool       = false
var ctrl_preview_slot: int        = 1   # 1–MAX_ORB_SLOTS, shown while reassigning

var _stick_was_active: Dictionary = {}  # axis index → bool
const STICK_DEADZONE:  float = 0.4

# ── colors ────────────────────────────────────────────────────────────────────
const COLOR_NODE_EMPTY:   Color = Color(0.2, 0.2, 0.3)
const COLOR_NODE_FILLED:  Color = Color(0.4, 0.6, 0.9)
const COLOR_NODE_HOVER:   Color = Color(0.6, 0.8, 1.0)
const COLOR_NODE_FOCUS:   Color = Color(1.0, 0.85, 0.3)
const COLOR_NODE_HOLDING: Color = Color(0.3, 1.0, 0.5)
const COLOR_REASSIGN:     Color = Color(1.0, 0.4, 0.9)
const COLOR_CONNECTION:   Color = Color(0.3, 0.8, 0.3)

# ── key cap appearance ────────────────────────────────────────────────────────
const KEY_CAP_SELF:  Color = Color(0.25, 0.25, 0.25)   # own slot in reassign mode: non-outline, darkened
const KEY_CAP_TAKEN: Color = Color(1.0, 1.0, 1.0, 1.0)   # other orb's slot: outlined, dimmed
const KEY_CAP_FREE:  Color = Color(1.0,  1.0,  1.0)    # unassigned or normal view: full brightness
const KEY_CAP_PREVIEW: Color = Color(0.2, 0.2, 0.2)   # added to cap color when controller-previewed

# ── graph sizing ──────────────────────────────────────────────────────────────
const NODE_RADIUS:          float   = 88.0
const NODE_OUTLINE:         float   = 3.0
const CONNECTION_WIDTH:     float   = 5.0
const CONNECTION_FONT_SIZE: int     = 18
const NODE_FONT_SIZE:       int     = 16
const ORB_FONT_SIZE:        int     = 14
const ORB_ICON_SIZE:        Vector2 = Vector2(40, 40)
const DRAG_ICON_SIZE:       Vector2 = Vector2(52, 52)
const ARROW_SIZE:           float   = 14.0

var node_input_icon_size := Vector2(72, 72)
var node_input_icon_pos  := Vector2(NODE_RADIUS - 40, -NODE_RADIUS - 4)

# ── orb bar sizing ────────────────────────────────────────────────────────────
const ORB_CARD_W:   float   = 400.0
const ORB_CARD_H:   float   = 190.0
const ORB_CARD_PAD: float   = 10.0
const ORB_BAR_LEFT: float   = 320.0
const ORB_BAR_TOP:  float   = 16.0
const ORB_TEX_SIZE: Vector2 = Vector2(56, 56)
const KEY_CAP_SIZE: Vector2 = Vector2(72, 72)

@onready var graph_canvas: Control = %GraphCanvas
@onready var orb_list:     Control = %OrbList

var dim_overlay:  ColorRect = null
var hint_overlay: Control   = null   # full-viewport Control used to draw the hint bar

# Glyph icon size in the hint bar.
var HINT_ICON_SIZE: Vector2
var HINT_FONT_SIZE: int
const HINT_SEP:       float   = 28.0   # gap between hint groups
const HINT_PAIR_GAP:  float   = 7.0    # gap between icon and its label
const HINT_BAR_H:     float   = 93.0   # total height of the hint bar strip


# ── ready ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	graph_canvas.draw.connect(_draw_graph)

	dim_overlay              = ColorRect.new()
	dim_overlay.color        = Color(0, 0, 0, 0.55)
	dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim_overlay)
	move_child(dim_overlay, 0)
	dim_overlay.hide()

	%OrbList.anchor_left   = 0.0
	%OrbList.anchor_right  = 0.0
	%OrbList.anchor_top    = 0.0
	%OrbList.anchor_bottom = 1.0
	%OrbList.offset_left   = ORB_BAR_LEFT
	%OrbList.offset_right  = ORB_BAR_LEFT + ORB_CARD_W
	%OrbList.offset_top    = ORB_BAR_TOP
	%OrbList.offset_bottom = 0.0

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.add_theme_constant_override("separation", int(ORB_CARD_PAD))
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	%OrbList.add_child(vbox)

	# Full-viewport overlay used exclusively for the controller hint bar so it
	# can be centred across the real screen width, independent of graph_canvas.
	hint_overlay              = Control.new()
	hint_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hint_overlay)
	hint_overlay.draw.connect(_draw_hint_bar)
	hint_overlay.hide()
	
	var icon_size: float = HINT_BAR_H * 0.65
	HINT_ICON_SIZE = Vector2(icon_size, icon_size)
	HINT_FONT_SIZE = int(HINT_BAR_H * 0.24)

	Util.input_device_changed.connect(_on_input_device_changed)
	
	_ability_tooltip = AbilityTooltip.new()
	add_child(_ability_tooltip)
	_orb_tooltip = OrbTooltip.new()
	_orb_tooltip.set_ability_tooltip(_ability_tooltip)
	_orb_tooltip.set_graph_context(graph_manager)
	add_child(_orb_tooltip)


# ── open / close ──────────────────────────────────────────────────────────────
func open() -> void:
	_layout_nodes()
	if orb_display_order.is_empty():
		var inventory: Node = player.get_node("Inventory")
		orb_display_order = inventory.orbs.duplicate()
	ctrl_node        = 0
	ctrl_list        = 0
	ctrl_panel       = FocusPanel.LIST
	ctrl_held_orb    = null
	ctrl_held_from   = -1
	ctrl_reassigning = false
	_rebuild_orb_list()
	dim_overlay.show()
	hint_overlay.show()
	show()
	get_tree().paused = true

func close() -> void:
	_kb_reassigning_orb = null
	_orb_tooltip.hide_now()
	_ability_tooltip.hide_now()
	if ctrl_held_orb != null:
		if ctrl_held_from != -1:
			_place_orb(ctrl_held_from, ctrl_held_orb)
		ctrl_held_orb  = null
		ctrl_held_from = -1
	ctrl_reassigning = false
	dim_overlay.hide()
	hint_overlay.hide()
	hide()
	get_tree().paused = false


# ── layout ────────────────────────────────────────────────────────────────────
func _layout_nodes() -> void:
	var nodes: Array[GraphNodeData] = graph_manager.graph.nodes
	var count: int                  = nodes.size()
	if count == 0:
		return
	for i in range(count):
		var angle: float  = (float(i) / float(count)) * TAU
		nodes[i].position = Vector2(cos(angle), sin(angle)) * 540.0
	for _iter in range(200):
		var forces: Array[Vector2] = []
		forces.resize(count)
		forces.fill(Vector2.ZERO)
		for i in range(count):
			for j in range(i + 1, count):
				var diff:  Vector2 = nodes[i].position - nodes[j].position
				var dist:  float   = maxf(diff.length(), 1.0)
				var force: Vector2 = diff.normalized() * 30000.0 / (dist * dist)
				forces[i] += force
				forces[j] -= force
			forces[i] += -nodes[i].position * 0.01
		for i in range(count):
			nodes[i].position += forces[i] * 0.016


# ── input ─────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("open_graph"):
		# Block graph while the forge input screen is open
		var forge_ui = get_node_or_null("%ForgeUI")
		if forge_ui != null and forge_ui.input_screen != null and forge_ui.input_screen.visible:
			return
		# Block graph while the level-up screen is open
		var level_up_screen = get_node_or_null("%LevelUpScreen")
		if level_up_screen != null and level_up_screen.visible:
			return
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			Util.last_input_device = Util.InputDevice.CONTROLLER
		else:
			Util.last_input_device = Util.InputDevice.KEYBOARD_MOUSE
		if visible:
			close()
		else:
			open()
		return

	if not visible:
		return

	if Util.last_input_device == Util.InputDevice.KEYBOARD_MOUSE:
		_handle_mouse_input(event)
		return

	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_handle_controller_input(event)


func _handle_mouse_input(event: InputEvent) -> void:
	var canvas_mouse: Vector2 = graph_canvas.get_local_mouse_position()
	var graph_mouse:  Vector2 = canvas_mouse - graph_canvas.size / 2.0

	if event is InputEventMouseMotion:
		var prev_hover: int = hover_node
		hover_node = graph_manager.graph.get_node_at(graph_mouse, NODE_RADIUS)
		if dragging_orb != null:
			drag_pos = get_viewport().get_mouse_position()
		if hover_node != prev_hover:
			if hover_node != -1:
				var hovered_orb: Orb = graph_manager.graph.nodes[hover_node].placed_orb
				if hovered_orb != null:
					_orb_tooltip.request_show(hovered_orb, get_viewport().get_mouse_position())
				else:
					_orb_tooltip.request_hide()
			else:
				_orb_tooltip.request_hide()
		elif hover_node != -1 and _orb_tooltip.visible:
			_orb_tooltip.update_position(get_viewport().get_mouse_position())
		graph_canvas.queue_redraw()

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var clicked: int = graph_manager.graph.get_node_at(graph_mouse, NODE_RADIUS)
				if clicked != -1:
					var node: GraphNodeData = graph_manager.graph.nodes[clicked]
					if dragging_orb == null and node.placed_orb != null:
						dragging_orb     = node.placed_orb
						drag_origin_node = clicked
						drag_pos         = get_viewport().get_mouse_position()
						_remove_orb(clicked)
						selected_orb = null
						_rebuild_orb_list()
			else:
				var clicked: int = graph_manager.graph.get_node_at(graph_mouse, NODE_RADIUS)
				if dragging_orb != null:
					if clicked != -1:
						var target_node: GraphNodeData = graph_manager.graph.nodes[clicked]
						if target_node.placed_orb != null and clicked != drag_origin_node:
							var displaced: Orb = target_node.placed_orb
							_remove_orb(clicked)
							_place_orb(clicked, dragging_orb)
							if drag_origin_node != -1:
								_place_orb(drag_origin_node, displaced)
						else:
							_place_orb(clicked, dragging_orb)
					elif drag_origin_node != -1:
						_place_orb(drag_origin_node, dragging_orb)
					dragging_orb     = null
					drag_origin_node = -1
				elif selected_orb != null:
					if clicked != -1:
						_place_orb(clicked, selected_orb)
						selected_orb = null
				elif clicked != -1:
					var node: GraphNodeData = graph_manager.graph.nodes[clicked]
					if node.placed_orb != null:
						selected_orb = node.placed_orb
						_remove_orb(clicked)
				else:
					selected_orb = null
				_rebuild_orb_list()

		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var clicked: int = graph_manager.graph.get_node_at(graph_mouse, NODE_RADIUS)
			if clicked != -1:
				_remove_orb(clicked)
			if dragging_orb != null:
				if drag_origin_node != -1:
					_place_orb(drag_origin_node, dragging_orb)
				dragging_orb     = null
				drag_origin_node = -1
			selected_orb = null
			_rebuild_orb_list()


# ── controller button handler ──────────────────────────────────────────────────
#
#  Normal mode:
#    D-pad / sticks  navigate nodes (graph) or scroll list (list panel)
#    A               pick up / place orb
#    B               cancel hold → back → close
#    X               eject orb from focused node (graph) OR enter slot-reassign
#                    mode for the hovered inventory orb (list panel)
#    Y               toggle graph ↔ inventory panel
#    RT              enter slot-reassign mode for the focused orb
#
#  Slot-reassign mode:
#    D-pad / sticks  cycle preview slot (←/→ or ↑/↓ both work)
#    A               confirm — assign preview slot to orb, exit mode
#    B               cancel — restore old slot, exit mode
#
func _handle_controller_input(event: InputEvent) -> void:
	# ── shared axis gate for motion events ───────────────────────────────────
	if event is InputEventJoypadMotion:
		var axis:   int  = (event as InputEventJoypadMotion).axis
		var active: bool = absf(event.get_axis_value()) > STICK_DEADZONE
		if not active:
			_stick_was_active[axis] = false
			return
		if _stick_was_active.get(axis, false):
			return
		_stick_was_active[axis] = true

	# ── slot-reassign mode ────────────────────────────────────────────────────
	if ctrl_reassigning:
		if event.is_action_pressed("ui_navigate_left") or event.is_action_pressed("ui_navigate_up"):
			ctrl_preview_slot = wrapi(ctrl_preview_slot - 2, 0, MAX_ORB_SLOTS) + 1
		elif event.is_action_pressed("ui_navigate_right") or event.is_action_pressed("ui_navigate_down"):
			ctrl_preview_slot = wrapi(ctrl_preview_slot - 1 + 1, 0, MAX_ORB_SLOTS) + 1
		elif event.is_action_pressed("confirm"):
			_ctrl_confirm_slot()
		elif event.is_action_pressed("cancel"):
			ctrl_reassigning = false
		_rebuild_orb_list()
		graph_canvas.queue_redraw()
		return

	# ── normal mode ───────────────────────────────────────────────────────────
	var is_nav: bool = event.is_action_pressed("ui_navigate_up") \
		or event.is_action_pressed("ui_navigate_down") \
		or event.is_action_pressed("ui_navigate_left") \
		or event.is_action_pressed("ui_navigate_right")

	if is_nav:
		var dpad: int
		if event.is_action_pressed("ui_navigate_up"):      dpad = JOY_BUTTON_DPAD_UP
		elif event.is_action_pressed("ui_navigate_down"):  dpad = JOY_BUTTON_DPAD_DOWN
		elif event.is_action_pressed("ui_navigate_left"):  dpad = JOY_BUTTON_DPAD_LEFT
		elif event.is_action_pressed("ui_navigate_right"): dpad = JOY_BUTTON_DPAD_RIGHT
		_ctrl_navigate(dpad)

	elif event.is_action_pressed("confirm"):
		if ctrl_panel == FocusPanel.GRAPH:
			_ctrl_graph_confirm()
		else:
			_ctrl_list_confirm()

	elif event.is_action_pressed("cancel"):
		if ctrl_held_orb != null:
			if ctrl_held_from != -1:
				_place_orb(ctrl_held_from, ctrl_held_orb)
				ctrl_node = ctrl_held_from
			else:
				ctrl_panel = FocusPanel.LIST
			ctrl_held_orb  = null
			ctrl_held_from = -1
			_rebuild_orb_list()
		else:
			close()

	elif event.is_action_pressed("ui_eject"):
		if ctrl_panel == FocusPanel.GRAPH and ctrl_held_orb == null:
			var nodes: Array[GraphNodeData] = graph_manager.graph.nodes
			if ctrl_node < nodes.size() and nodes[ctrl_node].placed_orb != null:
				_remove_orb(ctrl_node)
		elif ctrl_panel == FocusPanel.LIST:
			var orb: Orb = _get_focused_orb()
			if orb != null and orb.node_index == -1:
				ctrl_reassigning  = true
				ctrl_preview_slot = 1
				if orb.input_action != "":
					ctrl_preview_slot = int(orb.input_action.trim_prefix("orb_"))
				_rebuild_orb_list()

	elif event.is_action_pressed("ui_switch_panel"):
		if ctrl_panel == FocusPanel.GRAPH:
			ctrl_panel = FocusPanel.LIST
			_focus_nearest_orb_card()
		else:
			ctrl_panel = FocusPanel.GRAPH
			_focus_nearest_graph_node()
		_rebuild_orb_list()

	elif event.is_action_pressed("ui_reassign_input"):
		var orb: Orb = _get_focused_orb()
		if orb != null and orb.node_index == -1:
			ctrl_reassigning  = true
			ctrl_preview_slot = 1
			if orb.input_action != "":
				ctrl_preview_slot = int(orb.input_action.trim_prefix("orb_"))
			_rebuild_orb_list()

	graph_canvas.queue_redraw()


# ── slot reassign confirm ─────────────────────────────────────────────────────

func _ctrl_confirm_slot() -> void:
	var orb: Orb = _get_focused_orb()
	if orb == null:
		ctrl_reassigning = false
		return
	var action:    String = "orb_%d" % ctrl_preview_slot
	var inventory: Node   = player.get_node("Inventory")
	# Unassign whoever currently owns this slot.
	for other: Orb in inventory.orbs:
		if other != orb and other.input_action == action:
			other.input_action = ""
	orb.input_action = action
	ctrl_reassigning = false   # exit mode on confirm


# ── controller navigation ─────────────────────────────────────────────────────

func _ctrl_navigate(dpad: int) -> void:
	var nodes: Array[GraphNodeData] = graph_manager.graph.nodes

	if ctrl_panel == FocusPanel.GRAPH:
		var dir: Vector2
		match dpad:
			JOY_BUTTON_DPAD_LEFT:  dir = Vector2(-1,  0)
			JOY_BUTTON_DPAD_RIGHT: dir = Vector2( 1,  0)
			JOY_BUTTON_DPAD_UP:    dir = Vector2( 0, -1)
			JOY_BUTTON_DPAD_DOWN:  dir = Vector2( 0,  1)

		if not nodes.is_empty():
			var current_pos: Vector2 = nodes[ctrl_node].position
			var best_index:  int     = ctrl_node
			var best_score:  float   = -INF

			for i in range(nodes.size()):
				if i == ctrl_node:
					continue
				var offset: Vector2 = nodes[i].position - current_pos
				var dot:    float   = offset.normalized().dot(dir)
				if dot <= 0.0:
					continue
				var score: float = dot / maxf(offset.length(), 1.0)
				if score > best_score:
					best_score = score
					best_index = i

			if best_index != ctrl_node:
				ctrl_node = best_index
			elif dpad == JOY_BUTTON_DPAD_LEFT:
				# No node to the left — switch to inventory list and land on
				# the card whose orb's node position is nearest to the current node.
				ctrl_panel = FocusPanel.LIST
				_focus_nearest_orb_card()
	else:
		var unplaced: Array[Orb] = _get_unplaced_orbs()
		match dpad:
			JOY_BUTTON_DPAD_RIGHT:
				# Switch to graph and land on the node nearest to the focused orb card.
				ctrl_panel = FocusPanel.GRAPH
				_focus_nearest_graph_node()
			JOY_BUTTON_DPAD_UP:
				if not unplaced.is_empty():
					ctrl_list = max(ctrl_list - 1, 0)
			JOY_BUTTON_DPAD_DOWN:
				if not unplaced.is_empty():
					ctrl_list = min(ctrl_list + 1, unplaced.size() - 1)
			JOY_BUTTON_DPAD_LEFT:
				if not unplaced.is_empty():
					ctrl_list = max(ctrl_list - 1, 0)

	_rebuild_orb_list()
	graph_canvas.queue_redraw()


# ── controller confirm actions ────────────────────────────────────────────────

func _ctrl_graph_confirm() -> void:
	var nodes: Array[GraphNodeData] = graph_manager.graph.nodes
	if ctrl_node >= nodes.size():
		return
	var node: GraphNodeData = nodes[ctrl_node]

	if ctrl_held_orb != null:
		if node.placed_orb != null:
			var displaced: Orb = node.placed_orb
			_remove_orb(ctrl_node)
			_place_orb(ctrl_node, ctrl_held_orb)
			if ctrl_held_from != -1:
				_place_orb(ctrl_held_from, displaced)
		else:
			_place_orb(ctrl_node, ctrl_held_orb)
		ctrl_held_orb  = null
		ctrl_held_from = -1
	elif node.placed_orb != null:
		ctrl_held_orb  = node.placed_orb
		ctrl_held_from = ctrl_node
		_remove_orb(ctrl_node)
	# Empty node with no held orb: do nothing (don't auto-grab from inventory).

	_rebuild_orb_list()


func _ctrl_list_confirm() -> void:
	var unplaced: Array[Orb] = _get_unplaced_orbs()
	if unplaced.is_empty():
		return
	ctrl_list  = clampi(ctrl_list, 0, unplaced.size() - 1)
	if ctrl_held_orb != null:
		ctrl_panel = FocusPanel.GRAPH
	else:
		ctrl_held_orb  = unplaced[ctrl_list]
		ctrl_held_from = -1
		ctrl_panel     = FocusPanel.GRAPH
	_rebuild_orb_list()
	graph_canvas.queue_redraw()


# ── helpers ───────────────────────────────────────────────────────────────────

func _get_focused_orb() -> Orb:
	if ctrl_panel == FocusPanel.GRAPH:
		var nodes: Array[GraphNodeData] = graph_manager.graph.nodes
		if ctrl_node < nodes.size():
			return nodes[ctrl_node].placed_orb
		return null
	else:
		var unplaced: Array[Orb] = _get_unplaced_orbs()
		if ctrl_list < unplaced.size():
			return unplaced[ctrl_list]
		return null


func _get_unplaced_orbs() -> Array[Orb]:
	var placed: Array[Orb] = []
	for node: GraphNodeData in graph_manager.graph.nodes:
		if node.placed_orb != null:
			placed.append(node.placed_orb)
	var result: Array[Orb] = []
	for orb: Orb in orb_display_order:
		if not placed.has(orb):
			result.append(orb)
	return result


func _focus_nearest_graph_node() -> void:
	var nodes: Array[GraphNodeData] = graph_manager.graph.nodes
	if nodes.is_empty():
		return
	var canvas_origin: Vector2 = graph_canvas.global_position + graph_canvas.size * 0.5
	var best:      int   = 0
	var best_dist: float = INF
	for i in range(nodes.size()):
		var node_vp: Vector2 = canvas_origin + nodes[i].position
		# Top-left-most = smallest distance from the top-left corner of the viewport.
		var d: float = node_vp.distance_to(Vector2.ZERO)
		if d < best_dist:
			best_dist = d
			best      = i
	ctrl_node = best


func _focus_nearest_orb_card() -> void:
	ctrl_list = 0


# ── process (stick navigation with repeat) ────────────────────────────────────

func _process(delta: float) -> void:
	if not visible:
		return
	graph_canvas.queue_redraw()
	hint_overlay.queue_redraw()


# ── drawing ───────────────────────────────────────────────────────────────────

func _draw_graph() -> void:
	var nodes:       Array[GraphNodeData]       = graph_manager.graph.nodes
	var connections: Array[GraphConnectionData] = graph_manager.graph.connections
	var origin:      Vector2                    = graph_canvas.size / 2.0
	var using_ctrl:  bool = Util.last_input_device == Util.InputDevice.CONTROLLER

	# connections
	for conn: GraphConnectionData in connections:
		var a:   Vector2 = nodes[conn.from_node].position + origin
		var b:   Vector2 = nodes[conn.to_node].position   + origin
		graph_canvas.draw_line(a, b, COLOR_CONNECTION, CONNECTION_WIDTH)
		var mid:  Vector2 = (a + b) / 2.0
		var dir:  Vector2 = (b - a).normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x) * (ARROW_SIZE * 0.5)
		graph_canvas.draw_colored_polygon(
			PackedVector2Array([
				mid + dir * ARROW_SIZE,
				mid - dir * ARROW_SIZE + perp,
				mid - dir * ARROW_SIZE - perp,
			]),
			COLOR_CONNECTION
		)
		graph_canvas.draw_string(
			ThemeDB.fallback_font,
			mid + Vector2(-dir.y, dir.x) * 18.0,
			"charges (%d)" % conn.charge_stacks,
			HORIZONTAL_ALIGNMENT_LEFT, -1, CONNECTION_FONT_SIZE, Color.WHITE
		)

	# nodes
	for i in range(nodes.size()):
		var node:   GraphNodeData = nodes[i]
		var center: Vector2       = node.position + origin
		var is_focused: bool      = using_ctrl and ctrl_panel == FocusPanel.GRAPH and i == ctrl_node

		var color: Color
		if i == hover_node and not using_ctrl: color = COLOR_NODE_HOVER
		elif node.placed_orb != null:          color = COLOR_NODE_FILLED
		else:                                  color = COLOR_NODE_EMPTY
		graph_canvas.draw_circle(center, NODE_RADIUS, color)
		graph_canvas.draw_arc(center, NODE_RADIUS, 0, TAU, 48, Color.WHITE, NODE_OUTLINE)

		if is_focused:
			var ring_col: Color = COLOR_REASSIGN  if ctrl_reassigning else COLOR_NODE_FOCUS
			graph_canvas.draw_arc(center, NODE_RADIUS + 8, 0, TAU, 48, ring_col, 4.0)

		var sign_str: String = "-" if graph_manager.is_inverse(node.stat_name) else "+"
		var pct_str:  String = "%s%.0f%%" % [sign_str, (node.stat_value - 1.0) * 100.0]
		graph_canvas.draw_string(ThemeDB.fallback_font,
			center + Vector2(-NODE_RADIUS + 8, -10),
			node.stat_name.replace("_", " "),
			HORIZONTAL_ALIGNMENT_LEFT, -1, NODE_FONT_SIZE, Color.WHITE)
		graph_canvas.draw_string(ThemeDB.fallback_font,
			center + Vector2(-NODE_RADIUS + 8, 12),
			pct_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, NODE_FONT_SIZE, Color(0.8, 1.0, 0.6))

		if node.placed_orb != null:
			if node.placed_orb.sprite_texture != null:
				graph_canvas.draw_texture_rect(
					node.placed_orb.sprite_texture,
					Rect2(center - ORB_ICON_SIZE / 2.0 + Vector2(0, 24), ORB_ICON_SIZE), false)
			graph_canvas.draw_string(ThemeDB.fallback_font,
				center + Vector2(-NODE_RADIUS + 8, 32),
				node.placed_orb.display_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, ORB_FONT_SIZE, Color(1, 1, 0.6))

			# Show preview slot icon while reassigning this node's orb.
			var show_preview: bool = using_ctrl and ctrl_reassigning and is_focused
			var icon: Texture2D = Util.get_action_icon(
				"orb_%d" % ctrl_preview_slot if show_preview else node.placed_orb.input_action,
				true)
			if icon != null:
				graph_canvas.draw_rect(
					Rect2(center + node_input_icon_pos - Vector2(3, 3), node_input_icon_size + Vector2(6, 6)),
					Color(0, 0, 0, 0.65))
				graph_canvas.draw_texture_rect(
					icon, Rect2(center + node_input_icon_pos, node_input_icon_size), false)
			else:
				var label: String = ("orb_%d" % ctrl_preview_slot if show_preview \
					else node.placed_orb.input_action).trim_prefix("orb_")
				var lpos: Vector2 = center + Vector2(NODE_RADIUS - 28, -NODE_RADIUS + 20)
				graph_canvas.draw_rect(Rect2(lpos - Vector2(3, -14), Vector2(24, 20)), Color(0,0,0,0.65))
				graph_canvas.draw_string(ThemeDB.fallback_font, lpos,
					"[%s]" % label, HORIZONTAL_ALIGNMENT_LEFT, -1, NODE_FONT_SIZE,
					COLOR_REASSIGN if show_preview else Color(1.0, 0.85, 0.3))

		if selected_orb != null and i == hover_node:
			graph_canvas.draw_arc(center, NODE_RADIUS + 6, 0, TAU, 48, Color(1.0, 0.85, 0.3), 4.0)

	# Held orb ghost above focused node.
	if using_ctrl and ctrl_held_orb != null and ctrl_panel == FocusPanel.GRAPH \
			and ctrl_node < nodes.size():
		var center:    Vector2 = nodes[ctrl_node].position + origin
		var ghost_pos: Vector2 = center + Vector2(0, -NODE_RADIUS - DRAG_ICON_SIZE.y * 0.5 - 8)
		if ctrl_held_orb.sprite_texture != null:
			graph_canvas.draw_texture_rect(ctrl_held_orb.sprite_texture,
				Rect2(ghost_pos - DRAG_ICON_SIZE / 2.0, DRAG_ICON_SIZE), false)
		graph_canvas.draw_string(ThemeDB.fallback_font,
			ghost_pos + Vector2(-NODE_RADIUS + 8, DRAG_ICON_SIZE.y * 0.5 + 4),
			ctrl_held_orb.display_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, ORB_FONT_SIZE, Color.WHITE)

	# Mouse drag icon.
	if dragging_orb != null:
		var local_drag: Vector2 = graph_canvas.get_local_mouse_position()
		if dragging_orb.sprite_texture != null:
			graph_canvas.draw_texture_rect(dragging_orb.sprite_texture,
				Rect2(local_drag - DRAG_ICON_SIZE / 2.0, DRAG_ICON_SIZE), false)
		graph_canvas.draw_string(ThemeDB.fallback_font, local_drag + Vector2(18, 4),
			dragging_orb.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, NODE_FONT_SIZE, Color.WHITE)

	# Hint bar is drawn by hint_overlay._draw_hint_bar() separately.
	# (hint_overlay spans the full viewport so centering is exact.)


# ── controller hint bar ───────────────────────────────────────────────────────
#
# Icons are fetched directly from Util.INPUT_ICONS by joypad constant so we
# are never dependent on InputMap bindings.  Each hint is [Texture2D, label].
# A null texture falls back to a short bracketed label string.
#
# Requires one extra entry in Util.INPUT_ICONS (see comment below):
#   Util._JOY_DPAD_ALL  →  xbox_dpad_all.png   (full 4-way dpad glyph)

func _hint_icon(joy_button: int) -> Texture2D:
	return Util.INPUT_ICONS.get(Util._JOY_BUTTON_OFFSET | joy_button, null)

func _hint_icon_axis(joy_axis: int) -> Texture2D:
	return Util.INPUT_ICONS.get(Util._JOY_AXIS_OFFSET | joy_axis, null)

func _hint_icon_dpad_all() -> Texture2D:
	var icon: Texture2D = Util.INPUT_ICONS.get(Util._JOY_DPAD_ALL, null)
	if icon == null:
		icon = _hint_icon(JOY_BUTTON_DPAD_LEFT)
	return icon

# A "navigate" hint shows the dpad glyph AND both stick glyphs side by side.
# Returns them as an Array[Texture2D] (1–3 entries) so the caller can draw each.
func _hint_nav_icons() -> Array:
	var icons: Array = []
	var dpad: Texture2D = _hint_icon_dpad_all()
	if dpad != null:
		icons.append(dpad)
	var ls: Texture2D = _hint_icon(JOY_BUTTON_LEFT_STICK)   # stick-click glyph reused as stick icon
	# Prefer a dedicated "stick move" glyph if one was added under _JOY_STICK_L.
	var ls_move: Texture2D = Util.INPUT_ICONS.get(Util._JOY_STICK_L, null)
	if ls_move != null:
		icons.append(ls_move)
	elif ls != null:
		icons.append(ls)
	var rs_move: Texture2D = Util.INPUT_ICONS.get(Util._JOY_STICK_R, null)
	if rs_move != null:
		icons.append(rs_move)
	return icons

func _draw_hint_bar() -> void:
	if not visible:
		return
	if Util.last_input_device != Util.InputDevice.CONTROLLER:
		return

	var btn_a:  Texture2D   = _hint_icon(JOY_BUTTON_A)
	var btn_b:  Texture2D   = _hint_icon(JOY_BUTTON_B)
	var btn_x:  Texture2D   = _hint_icon(JOY_BUTTON_X)
	var btn_y:  Texture2D   = _hint_icon(JOY_BUTTON_Y)
	var trig_r: Texture2D   = _hint_icon_axis(JOY_AXIS_TRIGGER_RIGHT)
	var nav:    Array       = _hint_nav_icons()   # [dpad, ls, rs] or subset

	# Each hint is [icons_array, label_string] where icons_array: Array[Texture2D].
	# Single-icon hints wrap the texture in an array for uniform handling.
	var hints: Array
	if ctrl_reassigning:
		hints = [
			[nav,        "Cycle slot"],
			[[btn_a],    "Confirm"],
			[[btn_b],    "Cancel"],
		]
	elif ctrl_held_orb != null:
		hints = [
			[nav,        "Navigate"],
			[[btn_a],    "Place"],
			[[btn_b],    "Cancel"],
		]
	elif ctrl_panel == FocusPanel.GRAPH:
		hints = [
			[nav,        "Navigate"],
			[[btn_a],    "Pick up"],
			[[btn_x],    "Eject"],
			[[btn_y],    "Inventory"],
			[[btn_b],    "Close"],
		]
	else:
		hints = [
			[nav,        "Navigate"],
			[[btn_a],    "Pick up"],
			[[btn_x],    "Reassign input"],
			[[btn_y],    "Graph"],
			[[btn_b],    "Close"],
		]

	var font:     Font    = ThemeDB.fallback_font
	var vp_size:  Vector2 = hint_overlay.size
	var text_col: Color   = Color(1, 1, 1, 0.85)
	var bg_col:   Color   = Color(0, 0, 0, 0.55)
	# Small gap between icons within the same hint group (e.g. dpad + sticks).
	const ICON_CLUSTER_GAP: float = 2.0

	# ── helper: width of one hint's icon cluster ──────────────────────────────
	var _icon_cluster_w: Callable = func(icons: Array) -> float:
		if icons.is_empty():
			return font.get_string_size("[?]", HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE).x
		var w: float = 0.0
		for i in range(icons.size()):
			if icons[i] != null:
				w += HINT_ICON_SIZE.x
			if i < icons.size() - 1:
				w += ICON_CLUSTER_GAP
		return w

	# ── pre-measure total row width ───────────────────────────────────────────
	var total_w: float = 0.0
	for pair in hints:
		total_w += _icon_cluster_w.call(pair[0]) + HINT_PAIR_GAP
		total_w += font.get_string_size(pair[1], HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE).x
		total_w += HINT_SEP
	total_w -= HINT_SEP

	# ── draw background strip ─────────────────────────────────────────────────
	var bar_y:  float = vp_size.y - HINT_BAR_H
	hint_overlay.draw_rect(Rect2(0, bar_y, vp_size.x, HINT_BAR_H), bg_col)

	# ── draw each hint ────────────────────────────────────────────────────────
	var x:      float = (vp_size.x - total_w) * 0.5
	var icon_y: float = bar_y + (HINT_BAR_H - HINT_ICON_SIZE.y) * 0.5
	var text_y: float = bar_y + (HINT_BAR_H + HINT_FONT_SIZE * 0.7) * 0.5

	for pair in hints:
		var icons: Array  = pair[0]
		var label: String = pair[1]

		if icons.is_empty() or (icons.size() == 1 and icons[0] == null):
			var fb_w: float = font.get_string_size("[?]", HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE).x
			hint_overlay.draw_string(font, Vector2(x, text_y), "[?]",
				HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE, Color(1, 1, 0.5, 0.85))
			x += fb_w + HINT_PAIR_GAP
		else:
			for i in range(icons.size()):
				var icon: Texture2D = icons[i]
				if icon != null:
					hint_overlay.draw_texture_rect(icon,
						Rect2(Vector2(x, icon_y), HINT_ICON_SIZE), false)
					x += HINT_ICON_SIZE.x
				if i < icons.size() - 1:
					x += ICON_CLUSTER_GAP
			x += HINT_PAIR_GAP

		hint_overlay.draw_string(font, Vector2(x, text_y), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE, text_col)
		x += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE).x + HINT_SEP


# ── orb placement ─────────────────────────────────────────────────────────────

func _place_orb(node_index: int, orb: Orb) -> void:
	if _kb_reassigning_orb == orb:
		_kb_reassigning_orb = null
	var node: GraphNodeData = graph_manager.graph.nodes[node_index]
	if node.placed_orb != null:
		_remove_orb(node_index)
	node.placed_orb = orb
	orb.node_index  = node_index
	_apply_node_to_orb(node, orb)
	player._recalculate_orb_offsets()
	_rebuild_orb_list()

func _remove_orb(node_index: int) -> void:
	var node: GraphNodeData = graph_manager.graph.nodes[node_index]
	if node.placed_orb == null:
		return
	if _kb_reassigning_orb == node.placed_orb:
		_kb_reassigning_orb = null
	var orb: Orb = node.placed_orb
	for conn: GraphConnectionData in graph_manager.graph.connections:
		if conn.charge_stacks == 0:
			continue
		if conn.to_node == node_index:
			for ability: AbilityData in orb.abilities:
				ability.stats.power -= conn.charge_stacks * 0.1
			conn.charge_stacks = 0
		elif conn.from_node == node_index:
			var target_orb: Orb = graph_manager.graph.nodes[conn.to_node].placed_orb
			if target_orb != null:
				for ability: AbilityData in target_orb.abilities:
					ability.stats.power -= conn.charge_stacks * 0.1
			conn.charge_stacks = 0
	_unapply_node_from_orb(node, orb)
	orb_display_order.erase(orb)
	orb_display_order.append(orb)
	node.placed_orb.node_index = -1
	node.placed_orb            = null
	player._recalculate_orb_offsets()
	_rebuild_orb_list()

func _apply_node_to_orb(node: GraphNodeData, orb: Orb) -> void:
	var modifier      := OrbModifier.new()
	modifier.stat_name = node.stat_name
	modifier.mod_type  = OrbModifier.ModType.MULTIPLICATIVE
	modifier.value     = (1.0 / node.stat_value) if graph_manager.is_inverse(node.stat_name) else node.stat_value
	modifier.apply(orb)

func _unapply_node_from_orb(node: GraphNodeData, orb: Orb) -> void:
	var modifier      := OrbModifier.new()
	modifier.stat_name = node.stat_name
	modifier.mod_type  = OrbModifier.ModType.MULTIPLICATIVE
	modifier.value     = (1.0 / node.stat_value) if graph_manager.is_inverse(node.stat_name) else node.stat_value
	modifier.unapply(orb)


# ── orb list ──────────────────────────────────────────────────────────────────

func _rebuild_orb_list() -> void:
	var vbox: VBoxContainer
	if %OrbList.get_child_count() > 0:
		vbox = %OrbList.get_child(0) as VBoxContainer
		for child in vbox.get_children():
			child.queue_free()
	else:
		vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
		vbox.add_theme_constant_override("separation", int(ORB_CARD_PAD))
		vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		%OrbList.add_child(vbox)

	if player == null:
		return

	var taken_slots: Dictionary = {}
	var inventory:   Node       = player.get_node("Inventory")
	for orb: Orb in inventory.orbs:
		if orb.input_action != "":
			taken_slots[orb.input_action] = orb

	var unplaced: Array[Orb] = _get_unplaced_orbs()
	for idx in range(unplaced.size()):
		var orb:        Orb  = unplaced[idx]
		var is_focused: bool = Util.last_input_device == Util.InputDevice.CONTROLLER \
			and ctrl_panel == FocusPanel.LIST and idx == ctrl_list
		var kb_expanding: bool = _kb_reassigning_orb == orb   # ← new
		vbox.add_child(_build_orb_card(orb, taken_slots, inventory, is_focused, kb_expanding))


func _build_orb_card(orb: Orb, taken_slots: Dictionary, inventory: Node,
		ctrl_focused: bool = false, kb_expanding: bool = false) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ORB_CARD_W, ORB_CARD_H)

	var highlight: bool = selected_orb == orb or dragging_orb == orb \
		or ctrl_held_orb == orb or ctrl_focused
	if highlight:
		var focused_orb:     Orb  = _get_focused_orb()
		var reassign_active: bool = ctrl_reassigning and focused_orb == orb
		var col: Color = COLOR_REASSIGN.lerp(Color(0, 0, 0, 0), 0.65) if reassign_active \
			else (Color(0.3, 1.0, 0.5, 0.35) if ctrl_focused else Color(1.0, 0.85, 0.3, 0.3))
		panel.add_theme_stylebox_override("panel", _make_highlight_style(col))

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var tex := TextureRect.new()
	tex.texture             = orb.sprite_texture
	tex.custom_minimum_size = ORB_TEX_SIZE
	tex.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tex.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(tex)

	var name_label := Label.new()
	name_label.text                 = orb.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_label)

	var focused_orb:      Orb  = _get_focused_orb()
	var is_ctrl:          bool = Util.last_input_device == Util.InputDevice.CONTROLLER
	var reassigning_this: bool = ctrl_reassigning and is_ctrl and focused_orb == orb

	var key_row := HBoxContainer.new()
	key_row.alignment = BoxContainer.ALIGNMENT_CENTER
	key_row.add_theme_constant_override("separation", 3)
	vbox.add_child(key_row)

	if reassigning_this or kb_expanding:
		for n in range(1, MAX_ORB_SLOTS + 1):
			var action:     String = "orb_%d" % n
			var appearance: Array  = _key_cap_appearance(orb, action, taken_slots, true)
			var btn        := Button.new()
			btn.icon             = appearance[0]
			btn.text             = "" if btn.icon != null else str(n)
			btn.expand_icon      = true
			btn.custom_minimum_size = KEY_CAP_SIZE
			btn.icon_alignment   = HORIZONTAL_ALIGNMENT_CENTER
			btn.toggle_mode      = false
			var cap_col: Color = appearance[1]
			if reassigning_this and n == ctrl_preview_slot:
				btn.add_theme_stylebox_override("normal", btn.get_theme_stylebox("hover"))
			btn.modulate = cap_col

			if reassigning_this:
				btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			else:
				var orb_ref:    Orb    = orb
				var action_ref: String = action
				btn.pressed.connect(func() -> void:
					for other: Orb in inventory.orbs:
						if other != orb_ref and other.input_action == action_ref:
							other.input_action = ""
					orb_ref.input_action = action_ref
					_kb_reassigning_orb  = null
					_rebuild_orb_list()
				)
			key_row.add_child(btn)
	else:
		if orb.input_action != "":
			var slot_num: int = int(orb.input_action.trim_prefix("orb_"))
			var cap: Button   = _build_key_cap(orb, orb.input_action, slot_num,
				taken_slots, inventory, true)
			key_row.add_child(cap)
		else:
			var placeholder := Button.new()
			placeholder.text                = "—"
			placeholder.custom_minimum_size = KEY_CAP_SIZE
			placeholder.disabled            = (orb.node_index != -1)
			placeholder.modulate            = Color(0.5, 0.5, 0.5)
			placeholder.add_theme_font_size_override("font_size", 18)
			var orb_ref: Orb = orb
			placeholder.pressed.connect(func() -> void:
				_kb_reassigning_orb = orb_ref
				_rebuild_orb_list())
			key_row.add_child(placeholder)

	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.mouse_filter  = Control.MOUSE_FILTER_PASS
	tex.mouse_filter   = Control.MOUSE_FILTER_PASS

	var orb_ref: Orb = orb
	panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					pressed_inventory_orb = orb_ref
					inventory_press_pos   = get_viewport().get_mouse_position()
					selected_orb          = orb_ref
				else:
					pressed_inventory_orb = null
					_rebuild_orb_list()
		elif ev is InputEventMouseMotion:
			if pressed_inventory_orb == orb_ref and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				var dist: float = inventory_press_pos.distance_to(get_viewport().get_mouse_position())
				if dist >= DRAG_THRESHOLD:
					dragging_orb          = orb_ref
					selected_orb          = null
					drag_origin_node      = -1
					drag_pos              = get_viewport().get_mouse_position()
					pressed_inventory_orb = null
					_rebuild_orb_list()
	)

	var orb_ref_tip: Orb = orb
	panel.mouse_entered.connect(func() -> void:
		_orb_tooltip.request_show(orb_ref_tip, get_viewport().get_mouse_position()))
	panel.mouse_exited.connect(func() -> void:
		_orb_tooltip.request_hide())

	return panel


# single_cap_mode: true means this cap is the lone "current binding" button,
# so clicking it on KB/M opens the full slot picker instead of toggling.
func _build_key_cap(orb: Orb, action: String, slot_num: int,
		taken_slots: Dictionary, inventory: Node,
		single_cap_mode: bool = false) -> Button:
	var btn := Button.new()
	btn.expand_icon         = true
	btn.toggle_mode         = not single_cap_mode
	btn.button_pressed      = (orb.input_action == action)
	btn.custom_minimum_size = KEY_CAP_SIZE
	btn.icon_alignment      = HORIZONTAL_ALIGNMENT_CENTER

	if orb.node_index != -1:
		btn.icon     = Util.get_action_icon(action, true)
		btn.text     = "" if btn.icon != null else str(slot_num)
		btn.disabled = true
		btn.modulate = Color(0.35, 0.35, 0.35)
		return btn

	var appearance: Array = _key_cap_appearance(orb, action, taken_slots, false)
	btn.icon     = appearance[0]
	btn.text     = "" if btn.icon != null else str(slot_num)
	btn.modulate = appearance[1]

	var orb_ref:    Orb    = orb
	var action_ref: String = action

	if single_cap_mode:
		btn.toggle_mode = false
		btn.pressed.connect(func() -> void:
			_kb_reassigning_orb = orb_ref
			_rebuild_orb_list())
	else:
		btn.toggled.connect(func(pressed: bool) -> void:
			if pressed:
				for other: Orb in inventory.orbs:
					if other != orb_ref and other.input_action == action_ref:
						other.input_action = ""
				orb_ref.input_action = action_ref
			else:
				if orb_ref.input_action == action_ref:
					orb_ref.input_action = ""
			_rebuild_orb_list()
		)

	return btn

# ── key cap state helper ──────────────────────────────────────────────────────
# Returns [icon: Texture2D, modulate: Color] for a key cap given the orb being
# displayed and which action slot the cap represents.  Centralises all three
# states so tweaking KEY_CAP_* constants is the only change needed.
func _key_cap_appearance(orb: Orb, action: String, taken_slots: Dictionary,
		reassigning: bool = false) -> Array:
	var is_self:  bool = orb.input_action == action
	var is_taken: bool = taken_slots.has(action) and taken_slots[action] != orb
	if not reassigning:
		return [Util.get_action_icon(action, false), KEY_CAP_FREE]
	# Reassign picker: self = non-outlined + darkened, taken = outlined + dimmed, free = outlined + full.
	if is_self:
		return [Util.get_action_icon(action, false), KEY_CAP_SELF]
	var icon: Texture2D = Util.get_action_icon(action, true) if is_taken else Util.get_action_icon(action, false)
	var col:  Color     = KEY_CAP_TAKEN if is_taken else KEY_CAP_FREE
	return [icon, col]

func _make_highlight_style(color: Color) -> StyleBoxFlat:
	var style                        := StyleBoxFlat.new()
	style.bg_color                    = color
	style.corner_radius_top_left      = 6
	style.corner_radius_top_right     = 6
	style.corner_radius_bottom_left   = 6
	style.corner_radius_bottom_right  = 6
	return style

func _on_input_device_changed() -> void:
	Util._sync_cursor()
	if visible:
		# Force both draw surfaces and the orb list to refresh immediately so
		# glyphs and the hint bar appear/disappear without waiting a frame.
		graph_canvas.queue_redraw()
		hint_overlay.queue_redraw()
		_rebuild_orb_list()
	if Util.last_input_device == Util.InputDevice.CONTROLLER:
		_kb_reassigning_orb = null
