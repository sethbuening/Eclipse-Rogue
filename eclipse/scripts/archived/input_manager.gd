extends Node

# ============================================================ autoload: InputManager
# Handles keyboard/mouse AND raw joypad rebinding + persistence.
#
# Steam Input takes over controller *polling* when active, but this manager
# always owns the raw joypad InputMap events so the controller tab in the
# options menu can show and remap them regardless of Steam state.
#
# Listening modes
# ───────────────
#   KEYBOARD  — captures InputEventKey / InputEventMouseButton
#   CONTROLLER — captures InputEventJoypadButton / InputEventJoypadMotion
#
# The two modes are completely independent so there is no cross-contamination.
#
# Save file layout  (user://input_bindings.cfg)
#   [bindings]   action_name = Array[InputEvent]   ← keyboard / mouse
#   [controller] action_name = Array[InputEvent]   ← raw joypad
#
# Both sections are always written together on every save so the file is
# always a complete snapshot of the current InputMap state.

const SAVE_PATH: String = "user://input_bindings.cfg"

# All actions the player can remap in the options menu.
const REMAPPABLE_ACTIONS: Array[String] = [
	"move_left", "move_right", "move_up", "move_down",
	"orb_1", "orb_2", "orb_3", "orb_4", "orb_5",
	"basic_ability", "channel_light", "open_graph",
	"pause", "throw_flare", "interact",
	"confirm", "cancel",
	"ui_navigate_up", "ui_navigate_down",
	"ui_navigate_left", "ui_navigate_right",
	"ui_eject", "ui_switch_panel", "ui_scroll_up", "ui_scroll_down",
]

# Emitted after any binding changes so the options UI can refresh.
signal bindings_changed

# Emitted when listening is cancelled (Escape pressed).
signal listen_cancelled

# ----------------------------------------------------------------- listen state

enum ListenMode { NONE, KEYBOARD, CONTROLLER }

var _listen_mode:      ListenMode = ListenMode.NONE
var _listening_action: String     = ""
var _listening_old_event: InputEvent = null

# ================================================================= lifecycle

func _ready() -> void:
	load_bindings()

# ================================================================= public API — query

## Returns keyboard/mouse-only events for [param action].
func get_keyboard_events(action: String) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey or event is InputEventMouseButton:
			result.append(event)
	return result

## Returns the project-default keyboard/mouse events for [param action].
func get_default_keyboard_events(action: String) -> Array[InputEvent]:
	return _get_default_events(action, true)

## Returns joypad-only events for [param action].
func get_controller_events(action: String) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			result.append(event)
	return result

## Returns the project-default joypad events for [param action].
func get_default_controller_events(action: String) -> Array[InputEvent]:
	return _get_default_events(action, false)

func _get_default_events(action: String, want_kb: bool) -> Array[InputEvent]:
	var prop: String = "input/" + action
	if not ProjectSettings.has_setting(prop):
		return []
	var result: Array[InputEvent] = []
	for event in ProjectSettings.get_setting(prop).events:
		var is_kb: bool = event is InputEventKey or event is InputEventMouseButton
		if is_kb == want_kb:
			result.append(event)
	return result

# ================================================================= public API — listen

## Begin capturing the next keyboard/mouse press for [param action].
## [param old_event] = null → add a new slot; otherwise replaces that event.
func start_listening_keyboard(action: String, old_event: InputEvent = null) -> void:
	if not REMAPPABLE_ACTIONS.has(action):
		push_warning("[InputManager] action not remappable: %s" % action)
		return
	_listen_mode         = ListenMode.KEYBOARD
	_listening_action    = action
	_listening_old_event = old_event

## Begin capturing the next joypad press/axis for [param action].
func start_listening_controller(action: String, old_event: InputEvent = null) -> void:
	if not REMAPPABLE_ACTIONS.has(action):
		push_warning("[InputManager] action not remappable: %s" % action)
		return
	_listen_mode         = ListenMode.CONTROLLER
	_listening_action    = action
	_listening_old_event = old_event

func stop_listening() -> void:
	_listen_mode         = ListenMode.NONE
	_listening_action    = ""
	_listening_old_event = null

func is_listening() -> bool:
	return _listen_mode != ListenMode.NONE

# ================================================================= public API — remap

## Directly remap [param action], replacing [param old_event] with [param new_event].
## Pass old_event = null to add without removing anything.
func remap_action(action: String, old_event: InputEvent, new_event: InputEvent) -> void:
	if not REMAPPABLE_ACTIONS.has(action):
		return
	_clear_event_from_others(action, new_event)
	if old_event != null:
		InputMap.action_erase_event(action, old_event)
	InputMap.action_add_event(action, new_event)
	save_bindings()
	bindings_changed.emit()

## Reset one action to the project-default bindings (both KB and joypad).
func reset_action(action: String) -> void:
	var prop: String = "input/" + action
	if not ProjectSettings.has_setting(prop):
		return
	InputMap.action_erase_events(action)
	for event in ProjectSettings.get_setting(prop).events:
		InputMap.action_add_event(action, event)
	save_bindings()
	bindings_changed.emit()

## Reset ALL remappable actions to project defaults (KB + joypad).
func reset_all() -> void:
	InputMap.load_from_project_settings()
	save_bindings()
	bindings_changed.emit()

# ================================================================= input hook

func _input(event: InputEvent) -> void:
	if not is_listening():
		return

	# Always ignore mouse motion.
	if event is InputEventMouseMotion:
		return

	# Ignore release events.
	if event is InputEventKey         and not event.pressed:
		return
	if event is InputEventMouseButton and not event.pressed:
		return
	if event is InputEventJoypadMotion and absf(event.axis_value) < 0.5:
		return
	if event is InputEventJoypadButton and not event.pressed:
		return

	# Escape cancels regardless of mode.
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		stop_listening()
		listen_cancelled.emit()
		get_viewport().set_input_as_handled()
		return

	# Route to the correct listen mode — ignore mismatched event types.
	var is_kb_event:  bool = event is InputEventKey or event is InputEventMouseButton
	var is_joy_event: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion

	match _listen_mode:
		ListenMode.KEYBOARD:
			if not is_kb_event:
				return   # Ignore joypad while capturing keyboard
		ListenMode.CONTROLLER:
			if not is_joy_event:
				return   # Ignore keyboard while capturing controller

	# Apply the binding.
	remap_action(_listening_action, _listening_old_event, event)
	stop_listening()
	get_viewport().set_input_as_handled()

# ================================================================= persistence

func save_bindings() -> void:
	var config := ConfigFile.new()
	for action in REMAPPABLE_ACTIONS:
		var kb_events:  Array = []
		var ctl_events: Array = []
		for event in InputMap.action_get_events(action):
			if event is InputEventKey or event is InputEventMouseButton:
				kb_events.append(event)
			elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
				ctl_events.append(event)
		config.set_value("bindings",   action, kb_events)
		config.set_value("controller", action, ctl_events)

	var err: int = config.save(SAVE_PATH)
	if err != OK:
		push_error("[InputManager] failed to save bindings: %d" % err)
	else:
		print("[InputManager] bindings saved to %s" % SAVE_PATH)

func load_bindings() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		print("[InputManager] no saved bindings, using project defaults")
		return

	for action in REMAPPABLE_ACTIONS:
		if not InputMap.has_action(action):
			push_warning("[InputManager] action not in InputMap: %s (skipping)" % action)
			continue

		# Keyboard/mouse.
		if config.has_section_key("bindings", action):
			for event in InputMap.action_get_events(action).duplicate():
				if event is InputEventKey or event is InputEventMouseButton:
					InputMap.action_erase_event(action, event)
			var saved = config.get_value("bindings", action)
			if saved is Array:
				for event in saved:
					if event is InputEventKey or event is InputEventMouseButton:
						InputMap.action_add_event(action, event)

		# Raw joypad.
		if config.has_section_key("controller", action):
			for event in InputMap.action_get_events(action).duplicate():
				if event is InputEventJoypadButton or event is InputEventJoypadMotion:
					InputMap.action_erase_event(action, event)
			var saved = config.get_value("controller", action)
			if saved is Array:
				for event in saved:
					if event is InputEventJoypadButton or event is InputEventJoypadMotion:
						InputMap.action_add_event(action, event)

	print("[InputManager] bindings loaded from %s" % SAVE_PATH)

# ================================================================= helpers

## Remove [param new_event] from all actions except [param skip_action].
func _clear_event_from_others(skip_action: String, new_event: InputEvent) -> void:
	for action in REMAPPABLE_ACTIONS:
		if action == skip_action:
			continue
		for existing in InputMap.action_get_events(action).duplicate():
			if _events_match(existing, new_event):
				InputMap.action_erase_event(action, existing)

## Compare two events by physical key/button, ignoring modifiers.
func _events_match(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return a.keycode == b.keycode and a.physical_keycode == b.physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return a.button_index == b.button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		return a.axis == b.axis and sign(a.axis_value) == sign(b.axis_value)
	return false
