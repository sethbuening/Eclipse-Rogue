extends Node

# ============================================================ autoload: SteamInputManager
# Bridges Steam Input API → Godot's InputMap action system.
#
# Action set names must match the VDF manifest exactly:
#   "InGameControls"  — used during gameplay
#   "MenuControls"    — used in main menu, pause menu, options menu
#
# Digital actions are polled each frame and injected as InputEventAction.
# Analog sticks are decomposed into four directional InputEventAction pushes.
# KB/mouse remapping lives in InputManager; controller remapping redirects
# to the Steam controller configurator overlay.
#
# ⚠ STEAM INPUT TEMPORARILY DISABLED
# Set STEAM_INPUT_ENABLED = true to re-enable once Steam Input integration
# is ready for testing.

const STEAM_INPUT_ENABLED: bool = false

# ----------------------------------------------------------------- action maps

## Steam digital action name → Godot action name
const DIGITAL_ACTION_MAP: Dictionary = {
	# In-game
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
	# Shared (both sets)
	"pause":             "pause",
	# Menu set
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

## Analog threshold below which a direction is considered released.
const ANALOG_DEADZONE: float = 0.25

## Action set names (must match steam_input_manifest.vdf exactly).
const ACTION_SET_INGAME: String = "InGameControls"
const ACTION_SET_MENU:   String = "MenuControls"

# ----------------------------------------------------------------- state
var _enabled:            bool       = false
var _controller:         int        = 0
var _digital_handles:    Dictionary = {}   # steam_action → handle
var _analog_handles:     Dictionary = {}   # steam_action → handle
var _action_set_handles: Dictionary = {}   # set_name → handle
var _current_set:        String     = ""

## Per-digital-action previous pressed state (keyed by steam action name).
var _prev_digital: Dictionary = {}

## Per-analog-axis previous strength (keyed by "<analog_name>:<dir>", dir=L/R/U/D).
var _prev_analog:  Dictionary = {}

# ================================================================= init

func initialize() -> void:
	if not STEAM_INPUT_ENABLED:
		print("[SteamInputManager] Steam Input is temporarily disabled")
		return
	if not SteamManager.steam_enabled:
		return
	Steam.inputInit(true)
	_cache_handles()
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
# Called from SteamManager._process via SteamInputManager.tick().

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

## Switch the active Steam Input action set.
## Call with ACTION_SET_INGAME when gameplay starts and ACTION_SET_MENU
## whenever any menu (main, pause, options) is opened.
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

# ================================================================= polling

func _poll_digital() -> void:
	for steam_action in DIGITAL_ACTION_MAP.keys():
		var data: Dictionary = Steam.getDigitalActionData(
			_controller, _digital_handles[steam_action])
		# bActive is false when this action doesn't belong to the current set;
		# skip it silently instead of toggling the Godot action to released.
		if not data.get("bActive", false):
			continue
		var pressed: bool = data.get("bState", false)
		if pressed == _prev_digital[steam_action]:
			continue
		_prev_digital[steam_action] = pressed
		var godot_action: String = DIGITAL_ACTION_MAP[steam_action]
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

## Inject an analog axis event only when strength has meaningfully changed.
func _push_analog(prev_key: String, godot_action: String, strength: float) -> void:
	var prev: float       = _prev_analog.get(prev_key, 0.0)
	var pressed: bool     = strength > ANALOG_DEADZONE
	var was_pressed: bool = prev     > ANALOG_DEADZONE
	# Skip if both are in the same pressed/released band and strength is close.
	if pressed == was_pressed and absf(strength - prev) < 0.05:
		return
	_prev_analog[prev_key] = strength
	_inject_action(godot_action, pressed, strength)

func _inject_action(godot_action: String, pressed: bool, strength: float) -> void:
	if not InputMap.has_action(godot_action):
		return
	var event     := InputEventAction.new()
	event.action   = godot_action
	event.pressed  = pressed
	event.strength = strength
	Input.parse_input_event(event)

## Clear all tracked previous states so no stale "held" events linger after
## a controller disconnect or action-set switch.
func _reset_prev_states() -> void:
	for key in _prev_digital.keys():
		if _prev_digital[key]:
			# Inject a release event so Godot doesn't think the button is stuck.
			var godot_action: String = DIGITAL_ACTION_MAP.get(key, "")
			if godot_action != "":
				_inject_action(godot_action, false, 0.0)
		_prev_digital[key] = false
	for key in _prev_analog.keys():
		_prev_analog[key] = 0.0
