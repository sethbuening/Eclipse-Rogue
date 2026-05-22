extends CanvasLayer

# ── references ────────────────────────────────────────────────────────────────
var player: CharacterBody2D


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

const SLOT_LABELS: Array[String] = ["1", "2", "3", "4", "5"]

var orb_display_order: Array[Orb] = []

# ── colors ────────────────────────────────────────────────────────────────────
const COLOR_NODE_EMPTY:  Color = Color(0.2, 0.2, 0.3)
const COLOR_NODE_FILLED: Color = Color(0.4, 0.6, 0.9)
const COLOR_NODE_HOVER:  Color = Color(0.6, 0.8, 1.0)
const COLOR_CONNECTION:  Color = Color(0.3, 0.8, 0.3)

# ── graph sizing ──────────────────────────────────────────────────────────────
const NODE_RADIUS:          float = 88.0
const NODE_OUTLINE:         float = 3.0
const CONNECTION_WIDTH:     float = 5.0
const CONNECTION_FONT_SIZE: int   = 18
const NODE_FONT_SIZE:       int   = 16
const ORB_FONT_SIZE:        int   = 14
const ORB_ICON_SIZE:        Vector2 = Vector2(40, 40)
const DRAG_ICON_SIZE:       Vector2 = Vector2(52, 52)
const ARROW_SIZE:           float = 14.0

var node_input_icon_size := Vector2(72, 72)  # was 32×32
var node_input_icon_pos  := Vector2(NODE_RADIUS - 40, -NODE_RADIUS - 4)
# there are two extra variables I could possibly create to define the increased 
# size of the background dark box and its offset from the input key

# ── orb bar sizing ────────────────────────────────────────────────────────────
const ORB_CARD_W:   float   = 400.0
const ORB_CARD_H:   float   = 190.0
const ORB_CARD_PAD: float   = 10.0
const ORB_BAR_LEFT: float   = 320.0    # gap from left edge — adjust to clear health bar
const ORB_BAR_TOP:  float   = 16.0    # gap from screen top
const ORB_TEX_SIZE: Vector2 = Vector2(56, 56)
const KEY_CAP_SIZE: Vector2 = Vector2(72, 72)

@onready var graph_canvas: Control = %GraphCanvas
@onready var orb_list:     Control = %OrbList

var dim_overlay: ColorRect = null

# ── ready ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	graph_canvas.draw.connect(_draw_graph)

	# Dim overlay — sits behind everything, shown only when menu is open.
	dim_overlay             = ColorRect.new()
	dim_overlay.color       = Color(0, 0, 0, 0.55)
	dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim_overlay)
	move_child(dim_overlay, 0)
	dim_overlay.hide()

	# Anchor orb list down the left side, just right of the health bar.
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

# ── open / close ──────────────────────────────────────────────────────────────
func open() -> void:
	_layout_nodes()
	if orb_display_order.is_empty():
		var inventory: Node = player.get_node("Inventory")
		orb_display_order = inventory.orbs.duplicate()
	_rebuild_orb_list()
	dim_overlay.show()
	show()
	get_tree().paused = true

func close() -> void:
	dim_overlay.hide()
	hide()
	get_tree().paused = false

# ── layout ────────────────────────────────────────────────────────────────────
func _layout_nodes() -> void:
	var nodes: Array[GraphNodeData] = GraphManager.graph.nodes
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

	var canvas_mouse: Vector2 = graph_canvas.get_local_mouse_position()
	var graph_mouse:  Vector2 = canvas_mouse - graph_canvas.size / 2.0

	if event is InputEventMouseMotion:
		hover_node = GraphManager.graph.get_node_at(graph_mouse, NODE_RADIUS)
		if dragging_orb != null:
			drag_pos = get_viewport().get_mouse_position()
		graph_canvas.queue_redraw()

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var clicked := GraphManager.graph.get_node_at(graph_mouse, NODE_RADIUS)
				if clicked != -1:
					var node: GraphNodeData = GraphManager.graph.nodes[clicked]
					if dragging_orb == null and node.placed_orb != null:
						dragging_orb     = node.placed_orb
						drag_origin_node = clicked
						drag_pos         = get_viewport().get_mouse_position()
						_remove_orb(clicked)
						selected_orb = null
						_rebuild_orb_list()
			else:
				# released an orb after dragging it
				var clicked := GraphManager.graph.get_node_at(graph_mouse, NODE_RADIUS)
				if dragging_orb != null:
					if clicked != -1:
						var target_node: GraphNodeData = GraphManager.graph.nodes[clicked]
						if target_node.placed_orb != null and clicked != drag_origin_node:
							# swap
							var displaced: Orb = target_node.placed_orb
							_remove_orb(clicked)
							_place_orb(clicked, dragging_orb)
							if drag_origin_node != -1:
								_place_orb(drag_origin_node, displaced)
							else:
								# dragged from inventory — displaced orb goes to list
								pass
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
					var node: GraphNodeData = GraphManager.graph.nodes[clicked]
					if node.placed_orb != null:
						selected_orb = node.placed_orb
						_remove_orb(clicked)
				else:
					selected_orb = null
				_rebuild_orb_list()

		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var clicked := GraphManager.graph.get_node_at(graph_mouse, NODE_RADIUS)
			if clicked != -1:
				_remove_orb(clicked)
			if dragging_orb != null:
				if drag_origin_node != -1:
					_place_orb(drag_origin_node, dragging_orb)
				dragging_orb     = null
				drag_origin_node = -1
			selected_orb = null
			_rebuild_orb_list()

# ── process ───────────────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if visible:
		graph_canvas.queue_redraw()

# ── drawing ───────────────────────────────────────────────────────────────────
func _draw_graph() -> void:
	var nodes:       Array[GraphNodeData]       = GraphManager.graph.nodes
	var connections: Array[GraphConnectionData] = GraphManager.graph.connections
	var origin:      Vector2                    = graph_canvas.size / 2.0

	# connections
	for conn: GraphConnectionData in connections:
		var a:    Vector2 = nodes[conn.from_node].position + origin
		var b:    Vector2 = nodes[conn.to_node].position   + origin
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
		var perp_offset: Vector2 = Vector2(-dir.y, dir.x) * 18.0
		graph_canvas.draw_string(
			ThemeDB.fallback_font,
			mid + perp_offset,
			"charges (%d)" % conn.charge_stacks,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1, CONNECTION_FONT_SIZE, Color.WHITE
		)

	# nodes
	for i in range(nodes.size()):
		var node:   GraphNodeData = nodes[i]
		var center: Vector2       = node.position + origin
		var color:  Color

		if i == hover_node:              color = COLOR_NODE_HOVER
		elif node.placed_orb != null:    color = COLOR_NODE_FILLED
		else:                            color = COLOR_NODE_EMPTY

		graph_canvas.draw_circle(center, NODE_RADIUS, color)
		graph_canvas.draw_arc(center, NODE_RADIUS, 0, TAU, 48, Color.WHITE, NODE_OUTLINE)

		var sign_str: String = "-" if GraphManager.is_inverse(node.stat_name) else "+"
		var pct_str:  String = "%s%.0f%%" % [sign_str, (node.stat_value - 1.0) * 100.0]
		graph_canvas.draw_string(
			ThemeDB.fallback_font,
			center + Vector2(-NODE_RADIUS + 8, -10),
			node.stat_name.replace("_", " "),
			HORIZONTAL_ALIGNMENT_LEFT, -1, NODE_FONT_SIZE, Color.WHITE
		)
		graph_canvas.draw_string(
			ThemeDB.fallback_font,
			center + Vector2(-NODE_RADIUS + 8, 12),
			pct_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, NODE_FONT_SIZE, Color(0.8, 1.0, 0.6)
		)

		if node.placed_orb != null:
			if node.placed_orb.sprite_texture != null:
				graph_canvas.draw_texture_rect(
					node.placed_orb.sprite_texture,
					Rect2(center - ORB_ICON_SIZE / 2.0 + Vector2(0, 24), ORB_ICON_SIZE),
					false
				)
			graph_canvas.draw_string(
				ThemeDB.fallback_font,
				center + Vector2(-NODE_RADIUS + 8, 32),
				node.placed_orb.display_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, ORB_FONT_SIZE, Color(1, 1, 0.6)
			)
			# Draw the input icon for orbs placed on a node
			var icon: Texture2D = Util.get_action_icon(node.placed_orb.input_action, true)
			if icon != null:
				
				
				# background pill
				graph_canvas.draw_rect(
					Rect2(center + node_input_icon_pos - Vector2(3, 3), node_input_icon_size + Vector2(6, 6)),
					Color(0, 0, 0, 0.65)
				)
				graph_canvas.draw_texture_rect(icon, Rect2(center + node_input_icon_pos, node_input_icon_size), false)
			else:
				var slot_label: String = node.placed_orb.input_action.trim_prefix("orb_")
				var label_pos  := center + Vector2(NODE_RADIUS - 28, -NODE_RADIUS + 20)
				graph_canvas.draw_rect(
					Rect2(label_pos - Vector2(3, -14), Vector2(24, 20)),
					Color(0, 0, 0, 0.65)
				)
				graph_canvas.draw_string(
					ThemeDB.fallback_font,
					label_pos,
					"[%s]" % slot_label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, NODE_FONT_SIZE, Color(1.0, 0.85, 0.3)
				)

		if selected_orb != null and i == hover_node:
			graph_canvas.draw_arc(center, NODE_RADIUS + 6, 0, TAU, 48, Color(1.0, 0.85, 0.3), 4.0)

	# floating drag icon
	if dragging_orb != null:
		var local_drag: Vector2 = graph_canvas.get_local_mouse_position()
		if dragging_orb.sprite_texture != null:
			graph_canvas.draw_texture_rect(
				dragging_orb.sprite_texture,
				Rect2(local_drag - DRAG_ICON_SIZE / 2.0, DRAG_ICON_SIZE),
				false
			)
		graph_canvas.draw_string(
			ThemeDB.fallback_font,
			local_drag + Vector2(18, 4),
			dragging_orb.display_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, NODE_FONT_SIZE, Color.WHITE
		)

# ── orb placement ─────────────────────────────────────────────────────────────
func _place_orb(node_index: int, orb: Orb) -> void:
	var node: GraphNodeData = GraphManager.graph.nodes[node_index]
	if node.placed_orb != null:
		_remove_orb(node_index)
	node.placed_orb = orb
	orb.node_index  = node_index
	_apply_node_to_orb(node, orb)
	player._recalculate_orb_offsets()
	_rebuild_orb_list()

func _remove_orb(node_index: int) -> void:
	var node: GraphNodeData = GraphManager.graph.nodes[node_index]
	if node.placed_orb == null:
		return
	var orb: Orb = node.placed_orb
	for conn: GraphConnectionData in GraphManager.graph.connections:
		if conn.charge_stacks == 0:
			continue
		if conn.to_node == node_index:
			for ability: AbilityData in orb.abilities:
				ability.stats.power -= conn.charge_stacks * 0.1
			conn.charge_stacks = 0
		elif conn.from_node == node_index:
			var target_orb: Orb = GraphManager.graph.nodes[conn.to_node].placed_orb
			if target_orb != null:
				for ability: AbilityData in target_orb.abilities:
					ability.stats.power -= conn.charge_stacks * 0.1
			conn.charge_stacks = 0
	_unapply_node_from_orb(node, orb)
	# move to end so it returns there in the orb list
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
	modifier.value     = (1.0 / node.stat_value) if GraphManager.is_inverse(node.stat_name) else node.stat_value
	modifier.apply(orb)

func _unapply_node_from_orb(node: GraphNodeData, orb: Orb) -> void:
	var modifier      := OrbModifier.new()
	modifier.stat_name = node.stat_name
	modifier.mod_type  = OrbModifier.ModType.MULTIPLICATIVE
	modifier.value     = (1.0 / node.stat_value) if GraphManager.is_inverse(node.stat_name) else node.stat_value
	modifier.unapply(orb)

# ── orb list (left bar) ───────────────────────────────────────────────────────
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

	var placed: Array[Orb] = []
	for node: GraphNodeData in GraphManager.graph.nodes:
		if node.placed_orb != null:
			placed.append(node.placed_orb)

	var taken_slots: Dictionary = {}
	var inventory: Node = player.get_node("Inventory")
	for orb: Orb in inventory.orbs:
		if orb.input_action != "":
			taken_slots[orb.input_action] = orb

	for orb: Orb in orb_display_order:
		if placed.has(orb):
			continue
		vbox.add_child(_build_orb_card(orb, taken_slots, inventory))

# ── orb card ──────────────────────────────────────────────────────────────────
func _build_orb_card(orb: Orb, taken_slots: Dictionary, inventory: Node) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ORB_CARD_W, ORB_CARD_H)

	if selected_orb == orb or dragging_orb == orb:
		panel.add_theme_stylebox_override("panel", _make_highlight_style(Color(1.0, 0.85, 0.3, 0.3)))

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
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_label)

	var key_row := HBoxContainer.new()
	key_row.alignment = BoxContainer.ALIGNMENT_CENTER
	key_row.add_theme_constant_override("separation", 3)
	vbox.add_child(key_row)

	for n in range(1, MAX_ORB_SLOTS + 1):
		var action: String = "orb_%d" % n
		key_row.add_child(_build_key_cap(orb, action, n, taken_slots, inventory))

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
					_rebuild_orb_list()
				else:
					pressed_inventory_orb = null
		elif ev is InputEventMouseMotion:
			if pressed_inventory_orb == orb_ref and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				var dist := inventory_press_pos.distance_to(get_viewport().get_mouse_position())
				if dist >= DRAG_THRESHOLD:
					dragging_orb          = orb_ref
					selected_orb          = null
					drag_origin_node      = -1
					drag_pos              = get_viewport().get_mouse_position()
					pressed_inventory_orb = null
					_rebuild_orb_list()
	)

	return panel

# ── key cap ───────────────────────────────────────────────────────────────────
func _build_key_cap(orb: Orb, action: String, slot_num: int,
		taken_slots: Dictionary, inventory: Node) -> Button:
	var btn             := Button.new()
	btn.icon = Util.get_action_icon(
		action,
		orb.input_action == action
	)
	btn.text             = "" if btn.icon != null else str(slot_num)
	btn.expand_icon      = true
	btn.toggle_mode      = true
	btn.button_pressed   = (orb.input_action == action)
	btn.custom_minimum_size = KEY_CAP_SIZE
	btn.icon_alignment   = HORIZONTAL_ALIGNMENT_CENTER

	if taken_slots.has(action) and taken_slots[action] != orb:
		btn.modulate = Color(0.45, 0.45, 0.45)

	var orb_ref:    Orb    = orb
	var action_ref: String = action
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

# ── helpers ───────────────────────────────────────────────────────────────────
func _make_highlight_style(color: Color) -> StyleBoxFlat:
	var style                       := StyleBoxFlat.new()
	style.bg_color                   = color
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	return style
