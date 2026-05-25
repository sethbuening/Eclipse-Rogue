extends Node

# ============================================================ autoload: SteamInputManager
# Bridges Steam Input API → Godot's InputMap action system.
#
# When Steam is connected and a controller is detected:
#   • Digital/analog actions are polled each frame and injected as InputEventAction.
#   • The player CAN still remap controls in-game via the OptionsMenu controller tab.
#     In-game remapping works by maintaining a "steam action → Godot action" override
#     table (_action_overrides). When an override exists, polled Steam events are
#     injected under the overridden Godot action name instead of the default.
#   • Overrides are saved to user://steam_input_overrides.cfg and loaded on startup.
#
# When Steam is NOT connected (or STEAM_INPUT_ENABLED = false):
#   • This manager does nothing. Raw joypad InputEvents from Godot's input system
#     are used instead, fully managed by InputManager (raw joypad remapping).
#
# Action set names must match the VDF manifest exactly:
#   "InGameControls"  — gameplay
#   "MenuControls"    — menus

const STEAM_INPUT_ENABLED: bool = true
const OVERRIDE_SAVE_PATH:  String = "user://steam_input_overrides.cfg"

# ----------------------------------------------------------------- action maps

## Steam digital action name → default Godot action name
const DIGITAL_ACTION_MAP: Dictionary = {
	"orb_1":             "orb_1",
	"orb_2":             "orb_2",
	"orb_3":             "orb_3",
	"orb_4":             "orb_4",
	"orb_5":             "orb_5",
	"basic_ability":     "basic_ability",
	"channel_light":     "channel_light",
	"open_graph":        "open_graph",
	"throw_flare":       "throw_flare",
	"interact":          "interact",
	"dev_call_wave":     "dev_call_wave",
	"pause":             "pause",
	"confirm":           "confirm",
	"cancel":            "cancel",
	"ui_navigate_up":    "ui_navigate_up",
	"ui_navigate_down":  "ui_navigate_down",
	"ui_navigate_left":  "ui_navigate_left",
	"ui_navigate_right": "ui_navigate_right",
	"ui_eject":          "ui_eject",
	"ui_switch_panel":   "ui_switch_panel",
	"ui_reassign_input": "ui_reassign_input",
	"ui_scroll_up":      "ui_scroll_up",
	"ui_scroll_down":    "ui_scroll_down",
}

## Steam analog action name → [left, right, up, down] Godot actions
const ANALOG_ACTION_MAP: Dictionary = {
	"Move": ["move_left", "move_right", "move_up", "move_down"],
	"Aim":  ["aim_left",  "aim_right",  "aim_up",  "aim_down"],
}

const ANALOG_DEADZONE: float = 0.25

const ACTION_SET_INGAME: String = "InGameControls"
const ACTION_SET_MENU:   String = "MenuControls"

# ----------------------------------------------------------------- runtime state

var _enabled:            bool       = false
var _controller:         int        = 0
var _digital_handles:    Dictionary = {}
var _analog_handles:     Dictionary = {}
var _action_set_handles: Dictionary = {}
var _current_set:        String     = ""

var _prev_digital: Dictionary = {}
var _prev_analog:  Dictionary = {}

## Runtime overrides: steam_action_name → godot_action_name.
## When a steam action is in this dict, its events fire the overridden Godot action
## instead of the default from DIGITAL_ACTION_MAP.
## This is how in-game controller remapping works alongside Steam Input.
var _action_overrides: Dictionary = {}

# Emitted after _action_overrides changes so the OptionsMenu can refresh icons.
signal steam_bindings_changed

# ================================================================= init

func initialize() -> void:
	if not STEAM_INPUT_ENABLED:
		print("[SteamInputManager] Steam Input disabled in config")
		return
	if not SteamManager.steam_enabled:
		return
	Steam.inputInit(true)
	_cache_handles()
	_load_overrides()
	_enabled = true
	print("[SteamInputManager] initialized")

func _cache_handles() -> void:
	for action in DIGITAL_ACTION_MAP.keys():
		_digital_handles[action] = Steam.getDigitalActionHandle(action)
		_prev_digital[action]    = false
	for action in ANALOG_ACTION_MAP.keys():
		_analog_handles[action]  = Steam.getAnalogActionHandle(action)
		_prev_analog[action + ":L"] = 0.0
		_prev_analog[action + ":R"] = 0.0
		_prev_analog[action + ":U"] = 0.0
		_prev_analog[action + ":D"] = 0.0
	for set_name in [ACTION_SET_INGAME, ACTION_SET_MENU]:
		_action_set_handles[set_name] = Steam.getActionSetHandle(set_name)

# ================================================================= per-frame tick

func tick() -> void:
	if not _enabled:
		return
	var controllers: Array = Steam.getConnectedControllers()
	if controllers.is_empty():
		if _controller != 0:
			_controller = 0
			_reset_prev_states()
		return
	_controller = controllers[0]
	_poll_digital()
	_poll_analog()

# ================================================================= action sets

func set_action_set(set_name: String) -> void:
	if not _enabled or _controller == 0:
		return
	if set_name == _current_set:
		return
	var handle = _action_set_handles.get(set_name, 0)
	if handle == 0:
		push_error("[SteamInputManager] unknown action set: %s" % set_name)
		return
	Steam.activateActionSet(_controller, handle)
	_current_set = set_name
	_reset_prev_states()
	print("[SteamInputManager] action set → %s" % set_name)

func is_controller_connected() -> bool:
	return _enabled and _controller != 0

func get_current_action_set() -> String:
	return _current_set

# ================================================================= in-game remapping
#
# When Steam Input is active the player cannot remap raw joypad events because
# Steam intercepts them before Godot sees them. Instead we keep an override table
# that redirects a Steam action to a different Godot action.
#
# Example: player wants "orb_2" Steam action to fire "orb_3" Godot action.
#   set_steam_action_override("orb_2", "orb_3")
#
# The OptionsMenu controller tab calls these methods instead of InputManager
# when is_controller_connected() is true.

## Map [param steam_action] to fire [param godot_action] instead of its default.
## Pass godot_action = "" to clear the override (revert to default).
func set_steam_action_override(steam_action: String, godot_action: String) -> void:
	if godot_action == "" or godot_action == DIGITAL_ACTION_MAP.get(steam_action, ""):
		_action_overrides.erase(steam_action)
	else:
		_action_overrides[steam_action] = godot_action
	_save_overrides()
	steam_bindings_changed.emit()

## Returns the Godot action currently fired by [param steam_action].
func get_godot_action_for(steam_action: String) -> String:
	return _action_overrides.get(steam_action, DIGITAL_ACTION_MAP.get(steam_action, ""))

## Returns the steam action name that currently fires [param godot_action],
## or "" if none does.
func get_steam_action_for_godot(godot_action: String) -> String:
	# Check overrides first.
	for steam_act in _action_overrides:
		if _action_overrides[steam_act] == godot_action:
			return steam_act
	# Fall back to defaults.
	for steam_act in DIGITAL_ACTION_MAP:
		if DIGITAL_ACTION_MAP[steam_act] == godot_action \
				and not _action_overrides.has(steam_act):
			return steam_act
	return ""

## Reset all Steam action overrides to defaults.
func reset_steam_overrides() -> void:
	_action_overrides.clear()
	_save_overrides()
	steam_bindings_changed.emit()

# ================================================================= override persistence

func _save_overrides() -> void:
	var config := ConfigFile.new()
	for steam_action in _action_overrides:
		config.set_value("overrides", steam_action, _action_overrides[steam_action])
	var err: int = config.save(OVERRIDE_SAVE_PATH)
	if err != OK:
		push_error("[SteamInputManager] failed to save overrides: %d" % err)

func _load_overrides() -> void:
	var config := ConfigFile.new()
	if config.load(OVERRIDE_SAVE_PATH) != OK:
		return
	for steam_action in config.get_section_keys("overrides"):
		var godot_action: String = config.get_value("overrides", steam_action, "")
		if godot_action != "" and InputMap.has_action(godot_action):
			_action_overrides[steam_action] = godot_action
	print("[SteamInputManager] overrides loaded from %s" % OVERRIDE_SAVE_PATH)

# ================================================================= polling

func _poll_digital() -> void:
	for steam_action in DIGITAL_ACTION_MAP.keys():
		var data: Dictionary = Steam.getDigitalActionData(
			_controller, _digital_handles[steam_action])
		if not data.get("bActive", false):
			continue
		var pressed: bool = data.get("bState", false)
		if pressed == _prev_digital[steam_action]:
			continue
		_prev_digital[steam_action] = pressed
		# Resolve override or default Godot action.
		var godot_action: String = _action_overrides.get(
			steam_action, DIGITAL_ACTION_MAP[steam_action])
		_inject_action(godot_action, pressed, 1.0 if pressed else 0.0)

func _poll_analog() -> void:
	for analog_name in ANALOG_ACTION_MAP.keys():
		var data: Dictionary = Steam.getAnalogActionData(
			_controller, _analog_handles[analog_name])
		if not data.get("bActive", false):
			continue
		var x: float = data.get("x", 0.0)
		var y: float = data.get("y", 0.0)
		var dirs: Array = ANALOG_ACTION_MAP[analog_name]
		_push_analog(analog_name + ":L", dirs[0], -x if x < 0.0 else 0.0)
		_push_analog(analog_name + ":R", dirs[1],  x if x > 0.0 else 0.0)
		_push_analog(analog_name + ":U", dirs[2], -y if y < 0.0 else 0.0)
		_push_analog(analog_name + ":D", dirs[3],  y if y > 0.0 else 0.0)

func _push_analog(prev_key: String, godot_action: String, strength: float) -> void:
	var prev: float       = _prev_analog.get(prev_key, 0.0)
	var pressed: bool     = strength > ANALOG_DEADZONE
	var was_pressed: bool = prev     > ANALOG_DEADZONE
	if pressed == was_pressed and absf(strength - prev) < 0.05:
		return
	_prev_analog[prev_key] = strength
	_inject_action(godot_action, pressed, strength)

func _inject_action(godot_action: String, pressed: bool, strength: float) -> void:
	if not InputMap.has_action(godot_action):
		return
	var event      := InputEventAction.new()
	event.action    = godot_action
	event.pressed   = pressed
	event.strength  = strength
	Input.parse_input_event(event)

func _reset_prev_states() -> void:
	for key in _prev_digital.keys():
		if _prev_digital[key]:
			var godot_action: String = _action_overrides.get(
				key, DIGITAL_ACTION_MAP.get(key, ""))
			if godot_action != "":
				_inject_action(godot_action, false, 0.0)
		_prev_digital[key] = false
	for key in _prev_analog.keys():
		_prev_analog[key] = 0.0
