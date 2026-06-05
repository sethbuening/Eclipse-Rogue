extends Node

enum tile {
	AIR,
	STONE,
	ROCK,
	GOLD,
	IRON,
	COPPER,
	TIN,
	CRYSTAL
}

enum dir {
	UP,
	RIGHT,
	LEFT,
	DOWN
}

# ── rarity ───────────────────────────────────────────────────────────────────
enum Rarity {
	COMMON,      # Dull stone — plain, no glow
	UNCOMMON,    # Ore-veined — iron/copper tones
	RARE,        # Crystal-cut — bright mineral hue
	EPIC,        # Deep-void — pulsing void energy
	LEGENDARY    # Molten core — cracked open, light spilling out
}

## Returns the display name for a rarity value.
static func rarity_name(r: int) -> String:
	match r:
		Rarity.COMMON:    return "Common"
		Rarity.UNCOMMON:  return "Uncommon"
		Rarity.RARE:      return "Rare"
		Rarity.EPIC:      return "Epic"
		Rarity.LEGENDARY: return "Legendary"
	return "Unknown"

## Returns the accent color associated with a rarity.
## Use for icon borders, glow tints, and card highlights.
static func rarity_color(r: int) -> Color:
	match r:
		Rarity.COMMON:    return Color(0.60, 0.58, 0.55, 1.0)  # dull stone grey
		Rarity.UNCOMMON:  return Color(0.35, 0.75, 0.40, 1.0)  # ore green
		Rarity.RARE:      return Color(0.30, 0.55, 1.00, 1.0)  # mineral blue
		Rarity.EPIC:      return Color(0.65, 0.25, 0.90, 1.0)  # void purple
		Rarity.LEGENDARY: return Color(1.00, 0.65, 0.10, 1.0)  # molten amber
	return Color.WHITE

# ── wave modifiers ────────────────────────────────────────────────────────────
enum Modifier {
	NONE,
	FAST,
	ALERTED,
	CLUSTERED,
	TRICKLE
}

# ── targeting helper functions ────────────────────────────────────────────────

enum TargetingType {
	CURSOR,            # Spawn as close to cursor as possible (conductor post)
	ENEMY,        # Enemies only, no fallback
	ENEMY_TILE,   # Enemies first, fall back to nearest mineable tile
	POST_ENEMY_TILE, # conductor posts first, then enemies, then tiles
	TILE,         # Mineable tiles only
	NONE,              # Passive / no targeting needed
}

class TargetingResult:
	var position: Vector2  = Vector2.ZERO
	var targets:  Array    = []          # Node2D enemies/posts, may be empty
	var found:    bool     = false
	var is_tile:  bool     = false       # true when result is a tile, not a unit


## Resolve a world-space target for one ability press.
## Returns null if nothing was found (caller should start/continue grace timer).
static func resolve_target(
		type:        int,        # TargetingType value
		player:      Node2D,
		tilemap:     Node,
		aim:         Vector2,    # already range-clamped aim position
		range:       float
) -> TargetingResult:
	var r := TargetingResult.new()

	match type:
		TargetingType.CURSOR:
			r.position = aim
			r.found    = true

		TargetingType.ENEMY:
			var enemy: Node2D = _nearest_enemy(player.global_position, aim, range)
			if enemy:
				r.position = enemy.global_position
				r.targets  = [enemy]
				r.found    = true

		TargetingType.ENEMY_TILE:
			var enemy: Node2D = _nearest_enemy(player.global_position, aim, range)
			if enemy:
				r.position = enemy.global_position
				r.targets  = [enemy]
				r.found    = true
			else:
				var tile: Vector2 = _nearest_tile(tilemap, aim, player.global_position, range)
				if tile != Vector2.INF:
					r.position = tile
					r.is_tile  = true
					r.found    = true

		TargetingType.TILE:
			var tile: Vector2 = _nearest_tile(tilemap, aim, player.global_position, range)
			if tile != Vector2.INF:
				r.position = tile
				r.is_tile  = true
				r.found    = true
		
		TargetingType.POST_ENEMY_TILE:
			var target: Node2D = _nearest_enemy_or_post(player.global_position, aim, range)
			if target:
				r.position = target.global_position
				r.targets  = [target]
				r.found    = true
			else:
				var tile: Vector2 = _nearest_tile(tilemap, aim, player.global_position, range)
				if tile != Vector2.INF:
					r.position = tile
					r.is_tile  = true
					r.found    = true

		TargetingType.NONE:
			r.found = true   # passives always "succeed"

	return r


static func _nearest_enemy(origin: Vector2, aim: Vector2, range: float) -> Node2D:
	var best_d: float  = INF
	var best:   Node = null
	for enemy in EnemyManager.living_enemies:
		if not is_instance_valid(enemy):
			continue
		if range > 0.0 and origin.distance_squared_to(enemy.global_position) > range * range:
			continue
		var d: float = enemy.global_position.distance_to(aim)
		if d < best_d:
			best_d = d
			best   = enemy
	return best

static func _nearest_conductor_post(origin: Vector2, aim: Vector2, range: float) -> Node2D:
	var best_d:   float = INF
	var best:     Node2D = null
	for post: ConductorPost in ConductorPost.all_posts:
		if not is_instance_valid(post):
			continue
		if origin.distance_squared_to(post.global_position) > range * range:
			continue
		var d: float = post.global_position.distance_to(aim)
		if d < best_d:
			best_d = d
			best   = post
	return best

static func _nearest_enemy_or_post(origin: Vector2, aim: Vector2, range: float) -> Node2D:
	# Enemies take priority over posts, but posts are valid targets too.
	var post: ConductorPost = _nearest_conductor_post(origin, aim, range)
	if post:
		return post
	var enemy: Node2D = _nearest_enemy(origin, aim, range)
	if enemy:
		return enemy
	return null

static func _nearest_tile(tilemap: Node, aim: Vector2, origin: Vector2, range: float) -> Vector2:
	if tilemap == null or not tilemap.has_method("get_nearest_mineable_tile"):
		return Vector2.INF
	return tilemap.get_nearest_mineable_tile(aim, origin, range)

# ── input device tracking ─────────────────────────────────────────────────────
enum InputDevice { KEYBOARD_MOUSE, CONTROLLER }
var last_input_device: InputDevice = InputDevice.KEYBOARD_MOUSE
const _MOUSE_MOVE_DEADZONE: float = 8  # pixels
const _JOYSTICK_MOVE_DEADZONE: float = 0.2
signal input_device_changed

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	input_device_changed.connect(_sync_cursor)
	_sync_cursor()

func _input(event: InputEvent) -> void:
	var device: InputDevice
	if event is InputEventKey or event is InputEventMouseButton:
		device = InputDevice.KEYBOARD_MOUSE
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() < _MOUSE_MOVE_DEADZONE:
			return
		device = InputDevice.KEYBOARD_MOUSE
	elif event is InputEventJoypadButton:
		device = InputDevice.CONTROLLER
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) < _JOYSTICK_MOVE_DEADZONE:
			return
		device = InputDevice.CONTROLLER
	else:
		return
	if device != last_input_device:
		last_input_device = device
		input_device_changed.emit()

func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if not connected and last_input_device == InputDevice.CONTROLLER:
		last_input_device = InputDevice.KEYBOARD_MOUSE
		input_device_changed.emit()

func _sync_cursor() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN \
		if last_input_device == InputDevice.CONTROLLER \
		else Input.MOUSE_MODE_VISIBLE

# ── misc ──────────────────────────────────────────────────────────────────────
func nearest_direction(v: Vector2) -> Vector2i:
	if abs(v.x) >= abs(v.y):
		return Vector2i.RIGHT if v.x >= 0 else Vector2i.LEFT
	else:
		return Vector2i.DOWN if v.y >= 0 else Vector2i.UP

func load_resources(path: String) -> Array[Resource]:
	var results: Array[Resource] = []
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		push_error("Util.load_resources: could not open path: " + path)
		return results
	dir.list_dir_begin()
	var filename: String = dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".tres"):
			var res: Resource = load(path + filename)
			if res != null:
				results.append(res)
			else:
				push_warning("Util.load_resources: failed to load: " + filename)
		filename = dir.get_next()
	dir.list_dir_end()
	return results

# ── debug draw ────────────────────────────────────────────────────────────────
static func draw_debug_circle(parent: Node2D, radius: float, color: Color = Color(1, 0, 0, 0.4), duration: float = 0.5) -> void:
	var circle := _DebugCircle.new()
	circle.radius   = radius
	circle.color    = color
	circle.duration = duration
	parent.get_tree().get_root().add_child(circle)
	circle.global_position = parent.global_position

class _DebugCircle extends Node2D:
	var radius:   float = 32.0
	var color:    Color = Color(1, 0, 0, 0.4)
	var duration: float = 0.5
	var _age:     float = 0.0

	func _process(delta: float) -> void:
		_age += delta
		modulate.a = 1.0 - (_age / duration)
		if _age >= duration:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		draw_arc(Vector2.ZERO, radius, 0, TAU, 48, color, 2.0)

# ── key icons ─────────────────────────────────────────────────────────────────
const _MOUSE_OFFSET:      int = 0x00010000
const _JOY_BUTTON_OFFSET: int = 0x00020000
const _JOY_AXIS_OFFSET:   int = 0x00030000
const _PRESSED:           int = 0x10000000
const _JOY_DPAD_ALL: int = 0x00040000
const _JOY_STICK_L: int = 0x00050000
const _JOY_STICK_R: int = 0x00060000

const _KB: String = "res://art/input_key_images/Keyboard & Mouse/Default/"
const _XB: String = "res://art/input_key_images/Xbox Series/Default/"

const INPUT_ICONS: Dictionary = {
	# ── keyboard ──────────────────────────────────────────────────────────────
	KEY_0:         preload(_KB + "keyboard_0.png"),
	KEY_1:         preload(_KB + "keyboard_1.png"),
	KEY_2:         preload(_KB + "keyboard_2.png"),
	KEY_3:         preload(_KB + "keyboard_3.png"),
	KEY_4:         preload(_KB + "keyboard_4.png"),
	KEY_5:         preload(_KB + "keyboard_5.png"),
	KEY_6:         preload(_KB + "keyboard_6.png"),
	KEY_7:         preload(_KB + "keyboard_7.png"),
	KEY_8:         preload(_KB + "keyboard_8.png"),
	KEY_9:         preload(_KB + "keyboard_9.png"),

	KEY_A: preload(_KB + "keyboard_a.png"),
	KEY_B: preload(_KB + "keyboard_b.png"),
	KEY_C: preload(_KB + "keyboard_c.png"),
	KEY_D: preload(_KB + "keyboard_d.png"),
	KEY_E: preload(_KB + "keyboard_e.png"),
	KEY_F: preload(_KB + "keyboard_f.png"),
	KEY_G: preload(_KB + "keyboard_g.png"),
	KEY_H: preload(_KB + "keyboard_h.png"),
	KEY_I: preload(_KB + "keyboard_i.png"),
	KEY_J: preload(_KB + "keyboard_j.png"),
	KEY_K: preload(_KB + "keyboard_k.png"),
	KEY_L: preload(_KB + "keyboard_l.png"),
	KEY_M: preload(_KB + "keyboard_m.png"),
	KEY_N: preload(_KB + "keyboard_n.png"),
	KEY_O: preload(_KB + "keyboard_o.png"),
	KEY_P: preload(_KB + "keyboard_p.png"),
	KEY_Q: preload(_KB + "keyboard_q.png"),
	KEY_R: preload(_KB + "keyboard_r.png"),
	KEY_S: preload(_KB + "keyboard_s.png"),
	KEY_T: preload(_KB + "keyboard_t.png"),
	KEY_U: preload(_KB + "keyboard_u.png"),
	KEY_V: preload(_KB + "keyboard_v.png"),
	KEY_W: preload(_KB + "keyboard_w.png"),
	KEY_X: preload(_KB + "keyboard_x.png"),
	KEY_Y: preload(_KB + "keyboard_y.png"),
	KEY_Z: preload(_KB + "keyboard_z.png"),

	KEY_F1:  preload(_KB + "keyboard_f1.png"),
	KEY_F2:  preload(_KB + "keyboard_f2.png"),
	KEY_F3:  preload(_KB + "keyboard_f3.png"),
	KEY_F4:  preload(_KB + "keyboard_f4.png"),
	KEY_F5:  preload(_KB + "keyboard_f5.png"),
	KEY_F6:  preload(_KB + "keyboard_f6.png"),
	KEY_F7:  preload(_KB + "keyboard_f7.png"),
	KEY_F8:  preload(_KB + "keyboard_f8.png"),
	KEY_F9:  preload(_KB + "keyboard_f9.png"),
	KEY_F10: preload(_KB + "keyboard_f10.png"),
	KEY_F11: preload(_KB + "keyboard_f11.png"),
	KEY_F12: preload(_KB + "keyboard_f12.png"),

	KEY_SPACE:     preload(_KB + "keyboard_space.png"),
	KEY_ENTER:     preload(_KB + "keyboard_enter.png"),
	KEY_ESCAPE:    preload(_KB + "keyboard_escape.png"),
	KEY_BACKSPACE: preload(_KB + "keyboard_backspace.png"),
	KEY_TAB:       preload(_KB + "keyboard_tab.png"),
	KEY_SHIFT:     preload(_KB + "keyboard_shift.png"),
	KEY_CTRL:      preload(_KB + "keyboard_ctrl.png"),
	KEY_ALT:       preload(_KB + "keyboard_alt.png"),

	KEY_LEFT:  preload(_KB + "keyboard_arrow_left.png"),
	KEY_RIGHT: preload(_KB + "keyboard_arrow_right.png"),
	KEY_UP:    preload(_KB + "keyboard_arrow_up.png"),
	KEY_DOWN:  preload(_KB + "keyboard_arrow_down.png"),

	# ── keyboard pressed ──────────────────────────────────────────────────────
	KEY_0 | _PRESSED: preload(_KB + "keyboard_0_outline.png"),
	KEY_1 | _PRESSED: preload(_KB + "keyboard_1_outline.png"),
	KEY_2 | _PRESSED: preload(_KB + "keyboard_2_outline.png"),
	KEY_3 | _PRESSED: preload(_KB + "keyboard_3_outline.png"),
	KEY_4 | _PRESSED: preload(_KB + "keyboard_4_outline.png"),
	KEY_5 | _PRESSED: preload(_KB + "keyboard_5_outline.png"),
	KEY_6 | _PRESSED: preload(_KB + "keyboard_6_outline.png"),
	KEY_7 | _PRESSED: preload(_KB + "keyboard_7_outline.png"),
	KEY_8 | _PRESSED: preload(_KB + "keyboard_8_outline.png"),
	KEY_9 | _PRESSED: preload(_KB + "keyboard_9_outline.png"),

	KEY_A | _PRESSED: preload(_KB + "keyboard_a_outline.png"),
	KEY_B | _PRESSED: preload(_KB + "keyboard_b_outline.png"),
	KEY_C | _PRESSED: preload(_KB + "keyboard_c_outline.png"),
	KEY_D | _PRESSED: preload(_KB + "keyboard_d_outline.png"),
	KEY_E | _PRESSED: preload(_KB + "keyboard_e_outline.png"),
	KEY_F | _PRESSED: preload(_KB + "keyboard_f_outline.png"),
	KEY_G | _PRESSED: preload(_KB + "keyboard_g_outline.png"),
	KEY_H | _PRESSED: preload(_KB + "keyboard_h_outline.png"),
	KEY_I | _PRESSED: preload(_KB + "keyboard_i_outline.png"),
	KEY_J | _PRESSED: preload(_KB + "keyboard_j_outline.png"),
	KEY_K | _PRESSED: preload(_KB + "keyboard_k_outline.png"),
	KEY_L | _PRESSED: preload(_KB + "keyboard_l_outline.png"),
	KEY_M | _PRESSED: preload(_KB + "keyboard_m_outline.png"),
	KEY_N | _PRESSED: preload(_KB + "keyboard_n_outline.png"),
	KEY_O | _PRESSED: preload(_KB + "keyboard_o_outline.png"),
	KEY_P | _PRESSED: preload(_KB + "keyboard_p_outline.png"),
	KEY_Q | _PRESSED: preload(_KB + "keyboard_q_outline.png"),
	KEY_R | _PRESSED: preload(_KB + "keyboard_r_outline.png"),
	KEY_S | _PRESSED: preload(_KB + "keyboard_s_outline.png"),
	KEY_T | _PRESSED: preload(_KB + "keyboard_t_outline.png"),
	KEY_U | _PRESSED: preload(_KB + "keyboard_u_outline.png"),
	KEY_V | _PRESSED: preload(_KB + "keyboard_v_outline.png"),
	KEY_W | _PRESSED: preload(_KB + "keyboard_w_outline.png"),
	KEY_X | _PRESSED: preload(_KB + "keyboard_x_outline.png"),
	KEY_Y | _PRESSED: preload(_KB + "keyboard_y_outline.png"),
	KEY_Z | _PRESSED: preload(_KB + "keyboard_z_outline.png"),

	KEY_F1  | _PRESSED: preload(_KB + "keyboard_f1_outline.png"),
	KEY_F2  | _PRESSED: preload(_KB + "keyboard_f2_outline.png"),
	KEY_F3  | _PRESSED: preload(_KB + "keyboard_f3_outline.png"),
	KEY_F4  | _PRESSED: preload(_KB + "keyboard_f4_outline.png"),
	KEY_F5  | _PRESSED: preload(_KB + "keyboard_f5_outline.png"),
	KEY_F6  | _PRESSED: preload(_KB + "keyboard_f6_outline.png"),
	KEY_F7  | _PRESSED: preload(_KB + "keyboard_f7_outline.png"),
	KEY_F8  | _PRESSED: preload(_KB + "keyboard_f8_outline.png"),
	KEY_F9  | _PRESSED: preload(_KB + "keyboard_f9_outline.png"),
	KEY_F10 | _PRESSED: preload(_KB + "keyboard_f10_outline.png"),
	KEY_F11 | _PRESSED: preload(_KB + "keyboard_f11_outline.png"),
	KEY_F12 | _PRESSED: preload(_KB + "keyboard_f12_outline.png"),

	KEY_SPACE     | _PRESSED: preload(_KB + "keyboard_space_outline.png"),
	KEY_ENTER     | _PRESSED: preload(_KB + "keyboard_enter_outline.png"),
	KEY_ESCAPE    | _PRESSED: preload(_KB + "keyboard_escape_outline.png"),
	KEY_BACKSPACE | _PRESSED: preload(_KB + "keyboard_backspace_outline.png"),
	KEY_TAB       | _PRESSED: preload(_KB + "keyboard_tab_outline.png"),
	KEY_SHIFT     | _PRESSED: preload(_KB + "keyboard_shift_outline.png"),
	KEY_CTRL      | _PRESSED: preload(_KB + "keyboard_ctrl_outline.png"),
	KEY_ALT       | _PRESSED: preload(_KB + "keyboard_alt_outline.png"),

	KEY_LEFT  | _PRESSED: preload(_KB + "keyboard_arrow_left_outline.png"),
	KEY_RIGHT | _PRESSED: preload(_KB + "keyboard_arrow_right_outline.png"),
	KEY_UP    | _PRESSED: preload(_KB + "keyboard_arrow_up_outline.png"),
	KEY_DOWN  | _PRESSED: preload(_KB + "keyboard_arrow_down_outline.png"),

	# ── mouse ─────────────────────────────────────────────────────────────────
	_MOUSE_OFFSET | MOUSE_BUTTON_LEFT:
		preload(_KB + "mouse_left.png"),
	_MOUSE_OFFSET | MOUSE_BUTTON_RIGHT:
		preload(_KB + "mouse_right.png"),
	_MOUSE_OFFSET | MOUSE_BUTTON_WHEEL_UP:
		preload(_KB + "mouse_scroll_up.png"),
	_MOUSE_OFFSET | MOUSE_BUTTON_WHEEL_DOWN:
		preload(_KB + "mouse_scroll_down.png"),

	# ── mouse pressed ─────────────────────────────────────────────────────────
	(_MOUSE_OFFSET | MOUSE_BUTTON_LEFT) | _PRESSED:
		preload(_KB + "mouse_left_outline.png"),
	(_MOUSE_OFFSET | MOUSE_BUTTON_RIGHT) | _PRESSED:
		preload(_KB + "mouse_right_outline.png"),
	(_MOUSE_OFFSET | MOUSE_BUTTON_WHEEL_UP) | _PRESSED:
		preload(_KB + "mouse_scroll_up_outline.png"),
	(_MOUSE_OFFSET | MOUSE_BUTTON_WHEEL_DOWN) | _PRESSED:
		preload(_KB + "mouse_scroll_down_outline.png"),

	# ── controller buttons ────────────────────────────────────────────────────
	_JOY_BUTTON_OFFSET | JOY_BUTTON_A:
		preload(_XB + "xbox_button_color_a.png"),
	_JOY_BUTTON_OFFSET | JOY_BUTTON_B:
		preload(_XB + "xbox_button_color_b.png"),
	_JOY_BUTTON_OFFSET | JOY_BUTTON_X:
		preload(_XB + "xbox_button_color_x.png"),
	_JOY_BUTTON_OFFSET | JOY_BUTTON_Y:
		preload(_XB + "xbox_button_color_y.png"),

	_JOY_BUTTON_OFFSET | JOY_BUTTON_LEFT_SHOULDER:
		preload(_XB + "xbox_lb.png"),
	_JOY_BUTTON_OFFSET | JOY_BUTTON_RIGHT_SHOULDER:
		preload(_XB + "xbox_rb.png"),

	_JOY_BUTTON_OFFSET | JOY_BUTTON_LEFT_STICK:
		preload(_XB + "xbox_stick_side_l.png"),
	_JOY_BUTTON_OFFSET | JOY_BUTTON_RIGHT_STICK:
		preload(_XB + "xbox_stick_side_r.png"),

	_JOY_BUTTON_OFFSET | JOY_BUTTON_BACK:
		preload(_XB + "xbox_button_view.png"),
	_JOY_BUTTON_OFFSET | JOY_BUTTON_START:
		preload(_XB + "xbox_button_menu.png"),

	_JOY_BUTTON_OFFSET | JOY_BUTTON_DPAD_UP:
		preload(_XB + "xbox_dpad_up.png"),
	_JOY_BUTTON_OFFSET | JOY_BUTTON_DPAD_DOWN:
		preload(_XB + "xbox_dpad_down.png"),
	_JOY_BUTTON_OFFSET | JOY_BUTTON_DPAD_LEFT:
		preload(_XB + "xbox_dpad_left.png"),
	_JOY_BUTTON_OFFSET | JOY_BUTTON_DPAD_RIGHT:
		preload(_XB + "xbox_dpad_right.png"),
	
	_JOY_DPAD_ALL: preload(_XB + "xbox_dpad_all.png"),
	_JOY_STICK_L: preload(_XB + "xbox_stick_l.png"),
	_JOY_STICK_R: preload(_XB + "xbox_stick_r.png"),
	
	# ── controller buttons pressed ────────────────────────────────────────────
	(_JOY_BUTTON_OFFSET | JOY_BUTTON_A) | _PRESSED:
		preload(_XB + "xbox_button_color_a_outline.png"),
	(_JOY_BUTTON_OFFSET | JOY_BUTTON_B) | _PRESSED:
		preload(_XB + "xbox_button_color_b_outline.png"),
	(_JOY_BUTTON_OFFSET | JOY_BUTTON_X) | _PRESSED:
		preload(_XB + "xbox_button_color_x_outline.png"),
	(_JOY_BUTTON_OFFSET | JOY_BUTTON_Y) | _PRESSED:
		preload(_XB + "xbox_button_color_y_outline.png"),

	(_JOY_BUTTON_OFFSET | JOY_BUTTON_LEFT_SHOULDER) | _PRESSED:
		preload(_XB + "xbox_lb_outline.png"),
	(_JOY_BUTTON_OFFSET | JOY_BUTTON_RIGHT_SHOULDER) | _PRESSED:
		preload(_XB + "xbox_rb_outline.png"),

	# WARNING: There are no outline sprites for these two inputs
	(_JOY_BUTTON_OFFSET | JOY_BUTTON_LEFT_STICK) | _PRESSED:
		preload(_XB + "xbox_stick_side_l.png"),
	(_JOY_BUTTON_OFFSET | JOY_BUTTON_RIGHT_STICK) | _PRESSED:
		preload(_XB + "xbox_stick_side_r.png"),

	(_JOY_BUTTON_OFFSET | JOY_BUTTON_BACK) | _PRESSED:
		preload(_XB + "xbox_button_view_outline.png"),
	(_JOY_BUTTON_OFFSET | JOY_BUTTON_START) | _PRESSED:
		preload(_XB + "xbox_button_menu_outline.png"),

	(_JOY_BUTTON_OFFSET | JOY_BUTTON_DPAD_UP) | _PRESSED:
		preload(_XB + "xbox_dpad_up_outline.png"),
	(_JOY_BUTTON_OFFSET | JOY_BUTTON_DPAD_DOWN) | _PRESSED:
		preload(_XB + "xbox_dpad_down_outline.png"),
	(_JOY_BUTTON_OFFSET | JOY_BUTTON_DPAD_LEFT) | _PRESSED:
		preload(_XB + "xbox_dpad_left_outline.png"),
	(_JOY_BUTTON_OFFSET | JOY_BUTTON_DPAD_RIGHT) | _PRESSED:
		preload(_XB + "xbox_dpad_right_outline.png"),

	# ── controller axes ───────────────────────────────────────────────────────
	_JOY_AXIS_OFFSET | JOY_AXIS_TRIGGER_LEFT:
		preload(_XB + "xbox_lt.png"),
	_JOY_AXIS_OFFSET | JOY_AXIS_TRIGGER_RIGHT:
		preload(_XB + "xbox_rt.png"),

	# ── controller axes pressed ───────────────────────────────────────────────
	(_JOY_AXIS_OFFSET | JOY_AXIS_TRIGGER_LEFT) | _PRESSED:
		preload(_XB + "xbox_lt_outline.png"),
	(_JOY_AXIS_OFFSET | JOY_AXIS_TRIGGER_RIGHT) | _PRESSED:
		preload(_XB + "xbox_rt_outline.png"),
}

static func get_event_icon(event: InputEvent, outline: bool) -> Texture2D:
	var key: int
	if event is InputEventKey:
		key = event.keycode if event.keycode != 0 else event.physical_keycode
	elif event is InputEventMouseButton:
		key = _MOUSE_OFFSET | event.button_index
	elif event is InputEventJoypadButton:
		key = _JOY_BUTTON_OFFSET | event.button_index
	elif event is InputEventJoypadMotion:
		key = _JOY_AXIS_OFFSET | event.axis
	else:
		return null
	if outline:
		key |= _PRESSED
	return INPUT_ICONS.get(key, null)

func get_action_icon(action: String, outline: bool = false) -> Texture2D:
	var want_controller := last_input_device == InputDevice.CONTROLLER

	for event in InputMap.action_get_events(action):
		var is_controller := event is InputEventJoypadButton or event is InputEventJoypadMotion
		if is_controller != want_controller:
			continue
		var icon: Texture2D = get_event_icon(event, outline)
		if icon != null:
			return icon
		else:
			print("get_action_icon: no icon found for event: ", event)

	return null
