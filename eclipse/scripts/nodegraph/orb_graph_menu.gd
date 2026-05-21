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

# ── colors ────────────────────────────────────────────────────────────────────
const COLOR_NODE_EMPTY:  Color = Color(0.2, 0.2, 0.3)
const COLOR_NODE_FILLED: Color = Color(0.4, 0.6, 0.9)
const COLOR_NODE_HOVER:  Color = Color(0.6, 0.8, 1.0)
const COLOR_CONNECTION:  Color = Color(0.3, 0.8, 0.3)

# ── graph sizing ──────────────────────────────────────────────────────────────
const NODE_RADIUS:        float = 88.0
const NODE_OUTLINE:       float = 3.0
const CONNECTION_WIDTH:   float = 5.0
const CONNECTION_FONT_SIZE: int = 18
const NODE_FONT_SIZE:       int = 16
const ORB_FONT_SIZE:        int = 14
const ORB_ICON_SIZE:    Vector2 = Vector2(40, 40)
const DRAG_ICON_SIZE:   Vector2 = Vector2(52, 52)
const ARROW_SIZE:         float = 14.0

@onready var graph_canvas: Control = %GraphCanvas
@onready var orb_list:     Control = %OrbList

# ── ready ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	graph_canvas.draw.connect(_draw_graph)
	%OrbList.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	%OrbList.anchor_left   = 0.85
	%OrbList.anchor_right  = 1.0
	%OrbList.anchor_top    = 0.0
	%OrbList.anchor_bottom = 1.0
	%OrbList.offset_left   = 0.0
	%OrbList.offset_right  = 0.0
	%OrbList.offset_top    = 0.0
	%OrbList.offset_bottom = 0.0

# ── open / close ──────────────────────────────────────────────────────────────
func open() -> void:
	_layout_nodes()
	_rebuild_orb_list()
	show()
	get_tree().paused = true

func close() -> void:
	hide()
	get_tree().paused = false

# ── layout ────────────────────────────────────────────────────────────────────
func _layout_nodes() -> void:
	var nodes: Array[GraphNodeData] = GraphManager.graph.nodes
	var count: int                  = nodes.size()
	if count == 0:
		return

	for i in range(count):
		var angle:        float = (float(i) / float(count)) * TAU
		nodes[i].position       = Vector2(cos(angle), sin(angle)) * 540.0

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
	if Input.is_action_just_pressed("open_graph"):
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
				var clicked := GraphManager.graph.get_node_at(graph_mouse, NODE_RADIUS)
				if dragging_orb != null:
					if clicked != -1:
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
	if not visible:
		return
	graph_canvas.queue_redraw()

# ── drawing ───────────────────────────────────────────────────────────────────
func _draw_graph() -> void:
	var nodes:       Array[GraphNodeData]       = GraphManager.graph.nodes
	var connections: Array[GraphConnectionData] = GraphManager.graph.connections
	var origin:      Vector2                    = graph_canvas.size / 2.0

	# ── connections ───────────────────────────────────────────────────────────
	for conn: GraphConnectionData in connections:
		var a: Vector2 = nodes[conn.from_node].position + origin
		var b: Vector2 = nodes[conn.to_node].position   + origin
		graph_canvas.draw_line(a, b, COLOR_CONNECTION, CONNECTION_WIDTH)

		var mid: Vector2 = (a + b) / 2.0
		var dir: Vector2 = (b - a).normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x) * (ARROW_SIZE * 0.5)
		graph_canvas.draw_colored_polygon(
			PackedVector2Array([
				mid + dir * ARROW_SIZE,
				mid - dir * ARROW_SIZE + perp,
				mid - dir * ARROW_SIZE - perp
			]),
			COLOR_CONNECTION
		)

		var charge_label: String = "charges (%d)" % conn.charge_stacks
		graph_canvas.draw_string(
			ThemeDB.fallback_font,
			mid + Vector2(4, -4),
			charge_label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1, CONNECTION_FONT_SIZE, COLOR_CONNECTION
		)

	# ── nodes ─────────────────────────────────────────────────────────────────
	for i in range(nodes.size()):
		var node:   GraphNodeData = nodes[i]
		var center: Vector2       = node.position + origin
		var color:  Color

		if i == hover_node:
			color = COLOR_NODE_HOVER
		elif node.placed_orb != null:
			color = COLOR_NODE_FILLED
		else:
			color = COLOR_NODE_EMPTY

		graph_canvas.draw_circle(center, NODE_RADIUS, color)
		graph_canvas.draw_arc(center, NODE_RADIUS, 0, TAU, 48, Color.WHITE, NODE_OUTLINE)

		var stat_label: String = node.stat_name.replace("_", " ")
		var value_label: String = "%s%.0f%%" % ["-" if node.stat_name == "cooldown" else "+", (node.stat_value - 1.0) * 100.0]
		graph_canvas.draw_string(
			ThemeDB.fallback_font,
			center + Vector2(-NODE_RADIUS + 8, -10),
			stat_label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1, NODE_FONT_SIZE, Color.WHITE
		)
		graph_canvas.draw_string(
			ThemeDB.fallback_font,
			center + Vector2(-NODE_RADIUS + 8, 12),
			value_label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1, NODE_FONT_SIZE, Color(0.8, 1.0, 0.6)
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
				HORIZONTAL_ALIGNMENT_LEFT,
				-1, ORB_FONT_SIZE, Color(1, 1, 0.6)
			)

		if selected_orb != null and i == hover_node:
			graph_canvas.draw_arc(center, NODE_RADIUS + 6, 0, TAU, 48, Color(1.0, 0.85, 0.3), 4.0)

	# ── floating drag icon ────────────────────────────────────────────────────
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
			HORIZONTAL_ALIGNMENT_LEFT,
			-1, NODE_FONT_SIZE, Color.WHITE
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
	node.placed_orb.node_index = -1
	node.placed_orb            = null
	player._recalculate_orb_offsets()
	_rebuild_orb_list()

func _apply_node_to_orb(node: GraphNodeData, orb: Orb) -> void:
	var modifier       := OrbModifier.new()
	modifier.stat_name  = node.stat_name
	modifier.mod_type   = OrbModifier.ModType.MULTIPLICATIVE
	modifier.value      = (1.0 / node.stat_value) if node.stat_name == "cooldown" else node.stat_value
	modifier.apply(orb)
 
func _unapply_node_from_orb(node: GraphNodeData, orb: Orb) -> void:
	var modifier       := OrbModifier.new()
	modifier.stat_name  = node.stat_name
	modifier.mod_type   = OrbModifier.ModType.MULTIPLICATIVE
	modifier.value      = (1.0 / node.stat_value) if node.stat_name == "cooldown" else node.stat_value
	modifier.unapply(orb)

# ── orb list ──────────────────────────────────────────────────────────────────
func _rebuild_orb_list() -> void:
	for child in orb_list.get_children():
		child.queue_free()

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

	for orb: Orb in inventory.orbs:
		if placed.has(orb):
			continue

		var panel  := PanelContainer.new()
		var hbox   := HBoxContainer.new()
		var vbox   := VBoxContainer.new()
		var tex    := TextureRect.new()
		var label  := Label.new()

		tex.texture             = orb.sprite_texture
		tex.custom_minimum_size = Vector2(48, 48)
		tex.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		label.text                 = orb.display_name
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 10)

		vbox.add_child(tex)
		vbox.add_child(label)
		hbox.add_child(vbox)

		var slot_vbox  := VBoxContainer.new()
		var slot_label := Label.new()
		slot_label.text = "slot"
		slot_label.add_theme_font_size_override("font_size", 9)
		slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_vbox.add_child(slot_label)

		var slot_row := HBoxContainer.new()
		for n in range(1, 8):
			var action: String = "orb_%d" % n
			var btn           := Button.new()
			btn.text           = str(n)
			btn.toggle_mode    = true
			btn.button_pressed = (orb.input_action == action)
			btn.custom_minimum_size = Vector2(22, 22)
			btn.add_theme_font_size_override("font_size", 11)

			if taken_slots.has(action) and taken_slots[action] != orb:
				btn.modulate = Color(0.5, 0.5, 0.5)

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
			slot_row.add_child(btn)

		slot_vbox.add_child(slot_row)
		hbox.add_child(slot_vbox)
		panel.add_child(hbox)

		if selected_orb == orb or dragging_orb == orb:
			panel.add_theme_stylebox_override("panel", _make_highlight_style(Color(1.0, 0.85, 0.3, 0.3)))

		panel.mouse_filter = Control.MOUSE_FILTER_PASS
		hbox.mouse_filter  = Control.MOUSE_FILTER_PASS
		vbox.mouse_filter  = Control.MOUSE_FILTER_PASS
		tex.mouse_filter   = Control.MOUSE_FILTER_PASS
		label.mouse_filter = Control.MOUSE_FILTER_PASS

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

		orb_list.add_child(panel)

func _make_highlight_style(color: Color) -> StyleBoxFlat:
	var style                       := StyleBoxFlat.new()
	style.bg_color                   = color
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	return style
