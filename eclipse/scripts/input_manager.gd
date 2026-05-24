extends Node

# ============================================================ autoload: InputManager
# Handles keyboard/mouse rebinding and persistence.
#
# Controller input is handled entirely by Steam Input when available.
# Joypad events are only stored/remapped here when Steam Input is inactive.
#
# Save file layout (ConfigFile):
#   [bindings]   action_name = Array[InputEvent]   ← keyboard/mouse only
#   [controller] action_name = Array[InputEvent]   ← raw joypad only
#
# The two sections are kept separate so keyboard and controller mappings
# are independently saved and loaded without interfering with each other.
# Both are written to the same file (user://input_bindings.cfg) on every save.

const SAVE_PATH: String = "user://input_bindings.cfg"

# All actions the player can rebind in the options menu.
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

# ----------------------------------------------------------------- state
var _listening_action:    String     = ""
var _listening_old_event: InputEvent = null

func _ready() -> void:
	load_bindings()

# ================================================================= public API

## Returns keyboard/mouse-only events for [param action].
func get_keyboard_events(action: String) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey or event is InputEventMouseButton:
			result.append(event)
	return result

## Returns the default keyboard/mouse events for [param action] from
## ProjectSettings, regardless of any user remapping.
func get_default_keyboard_events(action: String) -> Array[InputEvent]:
	var prop: String = "input/" + action
	if not ProjectSettings.has_setting(prop):
		return []
	var result: Array[InputEvent] = []
	for event in ProjectSettings.get_setting(prop).events:
		if event is InputEventKey or event is InputEventMouseButton:
			result.append(event)
	return result

## Returns joypad-only events for [param action].
func get_controller_events(action: String) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			result.append(event)
	return result

## Returns the default joypad events for [param action] from ProjectSettings.
func get_default_controller_events(action: String) -> Array[InputEvent]:
	var prop: String = "input/" + action
	if not ProjectSettings.has_setting(prop):
		return []
	var result: Array[InputEvent] = []
	for event in ProjectSettings.get_setting(prop).events:
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			result.append(event)
	return result

## Begin capturing the next valid key/button press for [param action].
## Pass [param old_event] = null to add a new slot; otherwise it replaces that event.
func start_listening(action: String, old_event: InputEvent = null) -> void:
	if not REMAPPABLE_ACTIONS.has(action):
		push_warning("[InputManager] action not remappable: %s" % action)
		return
	_listening_action    = action
	_listening_old_event = old_event

func stop_listening() -> void:
	_listening_action    = ""
	_listening_old_event = null

func is_listening() -> bool:
	return _listening_action != ""

## Directly remap [param action], replacing [param old_event] with [param new_event].
## Pass old_event = null to add without removing anything.
func remap_action(action: String, old_event: InputEvent, new_event: InputEvent) -> void:
	if not REMAPPABLE_ACTIONS.has(action):
		return
	# Prevent duplicates: remove the new_event from any other action first.
	_clear_event_from_others(action, new_event)
	if old_event != null:
		InputMap.action_erase_event(action, old_event)
	InputMap.action_add_event(action, new_event)
	save_bindings()
	bindings_changed.emit()

## Reset one action to the project-default bindings.
func reset_action(action: String) -> void:
	var prop: String = "input/" + action
	if not ProjectSettings.has_setting(prop):
		return
	InputMap.action_erase_events(action)
	for event in ProjectSettings.get_setting(prop).events:
		# Only restore KB/mouse defaults here; joypad defaults live in Steam.
		if event is InputEventKey or event is InputEventMouseButton:
			InputMap.action_add_event(action, event)
	save_bindings()
	bindings_changed.emit()

## Reset all remappable actions to project defaults (KB/mouse only).
func reset_all() -> void:
	# Reload the full defaults, then strip joypad events back out so we
	# don't accidentally overwrite Steam Input's controller bindings.
	InputMap.load_from_project_settings()
	for action in REMAPPABLE_ACTIONS:
		for event in InputMap.action_get_events(action).duplicate():
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				InputMap.action_erase_event(action, event)
	save_bindings()
	bindings_changed.emit()

# ================================================================= input hook

func _input(event: InputEvent) -> void:
	if not is_listening():
		return

	# Ignore non-actionable events (mouse movement, key/button releases).
	if event is InputEventMouseMotion:
		return
	if event is InputEventKey and not event.pressed:
		return
	if event is InputEventMouseButton and not event.pressed:
		return
	if event is InputEventJoypadMotion and absf(event.axis_value) < 0.5:
		return

	# Escape → cancel listening without applying a binding.
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		stop_listening()
		listen_cancelled.emit()
		get_viewport().set_input_as_handled()
		return

	# Joypad events while Steam Input is active → redirect to Steam overlay.
	if (event is InputEventJoypadButton or event is InputEventJoypadMotion) \
			and SteamInputManager.is_controller_connected():
		push_warning("[InputManager] controller connected — redirecting to Steam overlay")
		OS.shell_open("steam://controllerconfig/%d" % SteamManager.APP_ID)
		stop_listening()
		get_viewport().set_input_as_handled()
		return

	# Apply the new binding. This also emits bindings_changed, which causes
	# the options menu to rebuild the list and hide the listening overlay.
	remap_action(_listening_action, _listening_old_event, event)
	stop_listening()
	get_viewport().set_input_as_handled()

# ================================================================= persistence
#
# HOW SAVING WORKS
# ────────────────
# Bindings are stored in a single ConfigFile at user://input_bindings.cfg.
# The file has two sections:
#
#   [bindings]   — keyboard / mouse events (one key per action)
#   [controller] — raw joypad events (only used when Steam Input is off)
#
# On every call to remap_action() or reset_all(), both sections are
# rewritten in full so the file always reflects the complete current state.
#
# On startup, load_bindings() reads the file. If it doesn't exist the
# project defaults from ProjectSettings remain active (no changes needed).
# Keyboard and controller events are loaded independently: loading keyboard
# bindings never touches joypad events and vice versa, so a player can
# remap their keyboard without disturbing their controller layout.
#
# Per-user persistence: the "user://" path resolves to a user-specific
# directory (e.g. %APPDATA%\Godot\app_userdata\<game>\ on Windows), so
# each OS user account gets its own bindings file automatically.
# If you add Steam Cloud Sync, pointing it at user://input_bindings.cfg
# will sync bindings across machines for the same Steam account.

func save_bindings() -> void:
	var config := ConfigFile.new()

	for action in REMAPPABLE_ACTIONS:
		var kb_events: Array  = []
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

		# Load keyboard/mouse bindings.
		if config.has_section_key("bindings", action):
			for event in InputMap.action_get_events(action).duplicate():
				if event is InputEventKey or event is InputEventMouseButton:
					InputMap.action_erase_event(action, event)
			var saved = config.get_value("bindings", action)
			if saved is Array:
				for event in saved:
					if event is InputEventKey or event is InputEventMouseButton:
						InputMap.action_add_event(action, event)

		# Load controller bindings (only applied when Steam Input is inactive).
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

## Remove [param new_event] from all actions except [param skip_action] to
## prevent the same key being bound to two different actions simultaneously.
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
