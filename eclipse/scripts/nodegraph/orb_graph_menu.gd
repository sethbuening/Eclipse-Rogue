# orb_graph_menu.gd
extends CanvasLayer

# ── references ────────────────────────────────────────────────────────────────
var player: CharacterBody2D

# ── ui state ──────────────────────────────────────────────────────────────────
var selected_orb:     Orb     = null
var dragging_orb:     Orb     = null
var drag_origin_node: int     = -1
var drag_pos:         Vector2 = Vector2.ZERO
var hover_node:       int     = -1
var pressed_inventory_orb: Orb = null
var inventory_press_pos: Vector2 = Vector2.ZERO
const DRAG_THRESHOLD := 8.0

# ── colors ────────────────────────────────────────────────────────────────────
const COLOR_NODE_EMPTY:  Color = Color(0.2, 0.2, 0.3)
const COLOR_NODE_FILLED: Color = Color(0.4, 0.6, 0.9)
const COLOR_NODE_HOVER:  Color = Color(0.6, 0.8, 1.0)
const COLOR_CONNECTION:  Dictionary = {
	GraphConnectionData.ConnectionType.CHARGES:   Color(0.3, 0.8, 0.3),
	GraphConnectionData.ConnectionType.OVERHEATS: Color(1.0, 0.4, 0.2),
	GraphConnectionData.ConnectionType.RESONATOR: Color(0.8, 0.3, 0.8),
	GraphConnectionData.ConnectionType.DRAINS:    Color(0.2, 0.5, 0.9),
	GraphConnectionData.ConnectionType.SILENCE:   Color(0.7, 0.7, 0.9),
}

# ── graph sizing ──────────────────────────────────────────────────────────────
const NODE_RADIUS: float      = 88.0
const NODE_OUTLINE: float     = 3.0
const CONNECTION_WIDTH: float = 5.0

const CONNECTION_FONT_SIZE: int = 18
const NODE_FONT_SIZE: int       = 16
const ORB_FONT_SIZE: int        = 14

const ORB_ICON_SIZE: Vector2 = Vector2(40, 40)
const DRAG_ICON_SIZE: Vector2 = Vector2(52, 52)

const ARROW_SIZE: float = 14.0

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
			# repel from every other node
			for j in range(i + 1, count):
				var diff:  Vector2 = nodes[i].position - nodes[j].position
				var dist:  float   = maxf(diff.length(), 1.0)
				var force: Vector2 = diff.normalized() * 30000.0 / (dist * dist)
				forces[i] += force
				forces[j] -= force

			# gentle center pull
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
	var graph_mouse: Vector2 = canvas_mouse - graph_canvas.size / 2.0

	if event is InputEventMouseMotion:
		hover_node = GraphManager.graph.get_node_at(graph_mouse, NODE_RADIUS)

		if dragging_orb != null:
			drag_pos = get_viewport().get_mouse_position()

		graph_canvas.queue_redraw()

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		# ───────────────── LEFT CLICK ─────────────────
		if mb.button_index == MOUSE_BUTTON_LEFT:

			# ── pressed ────────────────────────────────
			if mb.pressed:
				var clicked := GraphManager.graph.get_node_at(graph_mouse, NODE_RADIUS)

				# start dragging orb from node
				if clicked != -1:
					var node: GraphNodeData = GraphManager.graph.nodes[clicked]

					if dragging_orb == null and node.placed_orb != null:
						dragging_orb = node.placed_orb
						drag_origin_node = clicked
						drag_pos = get_viewport().get_mouse_position()

						_remove_orb(clicked)
						selected_orb = null
						_rebuild_orb_list()

			# ── released ───────────────────────────────
			else:
				var clicked := GraphManager.graph.get_node_at(graph_mouse, NODE_RADIUS)

				# finish drag
				if dragging_orb != null:
					if clicked != -1:
						_place_orb(clicked, dragging_orb)
					elif drag_origin_node != -1:
						# return to original node
						_place_orb(drag_origin_node, dragging_orb)

					dragging_orb = null
					drag_origin_node = -1

				# place selected orb
				elif selected_orb != null:
					if clicked != -1:
						_place_orb(clicked, selected_orb)
						selected_orb = null

				# pick up orb from node without dragging
				elif clicked != -1:
					var node: GraphNodeData = GraphManager.graph.nodes[clicked]

					if node.placed_orb != null:
						selected_orb = node.placed_orb
						_remove_orb(clicked)

				else:
					selected_orb = null

				_rebuild_orb_list()

		# ───────────────── RIGHT CLICK ────────────────
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:

			var clicked := GraphManager.graph.get_node_at(graph_mouse, NODE_RADIUS)

			# remove orb from node
			if clicked != -1:
				_remove_orb(clicked)

			# cancel drag
			if dragging_orb != null:
				if drag_origin_node != -1:
					_place_orb(drag_origin_node, dragging_orb)

				dragging_orb = null
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
		var a:     Vector2 = nodes[conn.from_node].position + origin
		var b:     Vector2 = nodes[conn.to_node].position   + origin
		var color: Color   = COLOR_CONNECTION.get(conn.connection_type, Color.WHITE)
		graph_canvas.draw_line(a, b, color, CONNECTION_WIDTH)

		if not conn.bidirectional:
			var mid:  Vector2 = (a + b) / 2.0
			var dir:  Vector2 = (b - a).normalized()
			var perp: Vector2 = Vector2(-dir.y, dir.x) * (ARROW_SIZE * 0.5)
			graph_canvas.draw_colored_polygon(
				PackedVector2Array([
					mid + dir * ARROW_SIZE,
					mid - dir * ARROW_SIZE + perp,
					mid - dir * ARROW_SIZE - perp
				]),
				color
			)

		var mid:   Vector2 = (a + b) / 2.0
		var label: String  = GraphConnectionData.ConnectionType.keys()[conn.connection_type]
		graph_canvas.draw_string(
			ThemeDB.fallback_font,
			mid + Vector2(4, -4),
			label.to_lower(),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1, CONNECTION_FONT_SIZE, color
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
		graph_canvas.draw_arc(
			center,
			NODE_RADIUS,
			0,
			TAU,
			48,
			Color.WHITE,
			NODE_OUTLINE
		)

		var type_label: String = GraphNodeData.NodeType.keys()[node.node_type].to_lower()
		graph_canvas.draw_string(
			ThemeDB.fallback_font,
			center + Vector2(-NODE_RADIUS + 4, -4),
			type_label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1, NODE_FONT_SIZE, Color.WHITE
		)

		if node.placed_orb != null:
			if node.placed_orb.sprite_texture != null:
				var icon_size: Vector2 = ORB_ICON_SIZE
				graph_canvas.draw_texture_rect(
					node.placed_orb.sprite_texture,
					Rect2(center - icon_size / 2.0 + Vector2(0, 8), icon_size),
					false
				)
			graph_canvas.draw_string(
				ThemeDB.fallback_font,
				center + Vector2(-NODE_RADIUS + 4, 10),
				node.placed_orb.display_name,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1, ORB_FONT_SIZE, Color(1, 1, 0.6)
			)

		if selected_orb != null and i == hover_node:
			graph_canvas.draw_arc(
				center,
				NODE_RADIUS + 6,
				0,
				TAU,
				48,
				Color(1.0, 0.85, 0.3),
				4.0
			)

	# ── floating drag icon ────────────────────────────────────────────────────
	if dragging_orb != null:
		var local_drag: Vector2 = graph_canvas.get_local_mouse_position()
		var icon_size: Vector2 = DRAG_ICON_SIZE
		if dragging_orb.sprite_texture != null:
			graph_canvas.draw_texture_rect(
				dragging_orb.sprite_texture,
				Rect2(local_drag - icon_size / 2.0, icon_size),
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
	node.placed_orb  = orb
	orb.node_index   = node_index
	_apply_node_to_orb(node, orb)
	_rebuild_orb_list()

func _remove_orb(node_index: int) -> void:
	var node: GraphNodeData = GraphManager.graph.nodes[node_index]
	if node.placed_orb == null:
		return
	_unapply_node_from_orb(node, node.placed_orb)
	node.placed_orb.node_index = -1
	node.placed_orb            = null
	_rebuild_orb_list()

func _apply_node_to_orb(node: GraphNodeData, orb: Orb) -> void:
	match node.node_type:
		GraphNodeData.NodeType.AOE:
			for ability: AbilityData in orb.abilities:
				ability.stats.aoe_radius   *= 2.0
				ability.stats.mining_radius *= 2.0
		GraphNodeData.NodeType.STAT:
			var modifier       := OrbModifier.new()
			modifier.stat_name  = node.stat_name
			modifier.value      = node.stat_value
			modifier.mod_type   = OrbModifier.ModType.ADDITIVE
			modifier.apply(orb)
		GraphNodeData.NodeType.ECHO:
			pass
		GraphNodeData.NodeType.DECAYING:
			for ability: AbilityData in orb.abilities:
				ability.stats.cooldown = 0.0
		GraphNodeData.NodeType.STAT_CONVERTER:
			pass

func _unapply_node_from_orb(node: GraphNodeData, orb: Orb) -> void:
	match node.node_type:
		GraphNodeData.NodeType.AOE:
			for ability: AbilityData in orb.abilities:
				ability.stats.aoe_radius   /= 2.0
				ability.stats.mining_radius /= 2.0
		GraphNodeData.NodeType.STAT:
			var modifier       := OrbModifier.new()
			modifier.stat_name  = node.stat_name
			modifier.value      = node.stat_value
			modifier.mod_type   = OrbModifier.ModType.ADDITIVE
			modifier.unapply(orb)
		GraphNodeData.NodeType.DECAYING:
			pass  # cooldown changes are permanent by design
		_:
			pass

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

	# build a map of which slot is already taken
	var taken_slots: Dictionary = {}  # "orb_1" -> Orb
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

		# slot picker — a row of buttons 1-7
		var slot_vbox := VBoxContainer.new()
		var slot_label := Label.new()
		slot_label.text = "slot"
		slot_label.add_theme_font_size_override("font_size", 9)
		slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_vbox.add_child(slot_label)

		var slot_row := HBoxContainer.new()
		for n in range(1, 8):
			var action: String  = "orb_%d" % n
			var btn            := Button.new()
			btn.text            = str(n)
			btn.toggle_mode     = true
			btn.button_pressed  = (orb.input_action == action)
			btn.custom_minimum_size = Vector2(22, 22)
			btn.add_theme_font_size_override("font_size", 11)

			# grey out if taken by a different orb
			if taken_slots.has(action) and taken_slots[action] != orb:
				btn.modulate = Color(0.5, 0.5, 0.5)

			var orb_ref:    Orb    = orb
			var action_ref: String = action
			btn.toggled.connect(func(pressed: bool) -> void:
				if pressed:
					# unassign whoever had this slot before
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
			panel.add_theme_stylebox_override("panel",
				_make_highlight_style(Color(1.0, 0.85, 0.3, 0.3))
			)

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
				if pressed_inventory_orb == orb_ref \
				and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
					var dist := inventory_press_pos.distance_to(
						get_viewport().get_mouse_position()
					)
					if dist >= DRAG_THRESHOLD:
						dragging_orb      = orb_ref
						selected_orb      = null
						drag_origin_node  = -1
						drag_pos          = get_viewport().get_mouse_position()
						pressed_inventory_orb = null
						_rebuild_orb_list()
		)

		orb_list.add_child(panel)

func _make_highlight_style(color: Color) -> StyleBoxFlat:
	var style                        := StyleBoxFlat.new()
	style.bg_color                    = color
	style.corner_radius_top_left      = 4
	style.corner_radius_top_right     = 4
	style.corner_radius_bottom_left   = 4
	style.corner_radius_bottom_right  = 4
	return style
