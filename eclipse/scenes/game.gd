# game.gd
extends Node2D

const DEBUG_MSG_DURATION: float = 3.0
var debug_messages: Array[Dictionary] = []

func _ready() -> void:
	ParticleManager.tilemap_manager = %TilemapManager
	EnemyManager.tilemap_manager    = %TilemapManager
	EnemyManager.player             = %Player
	WaveManager.wave_started.connect(_on_wave_started)
	WaveManager.wave_cleared.connect(_on_wave_cleared)
	%DebugLabel.add_theme_font_size_override(
		"normal_font_size",
		DisplayServer.window_get_size().y / 50
	)

func _process(delta: float) -> void:
	_process_debug_messages(delta)
	var player: CharacterBody2D = %Player
	if player == null:
		return
	var fps: int         = int(1.0 / delta)
	var env: Environment = %Environment.environment
	%DebugLabel.parse_bbcode(_build_debug_text(fps, env, player))

func push_debug(msg: String) -> void:
	debug_messages.append({ "text": msg, "age": 0.0 })

func _process_debug_messages(delta: float) -> void:
	for m: Dictionary in debug_messages:
		m.age += delta
	debug_messages = debug_messages.filter(func(m: Dictionary): return m.age < DEBUG_MSG_DURATION)

func _build_debug_text(fps: int, env: Environment, player: CharacterBody2D) -> String:
	var lines: Array[String] = [
		"fps: "     + str(fps),
		"focus: "   + str(snappedf(player.focus_charge / player.FOCUS_CHARGE_TIME * 100, 1)) + "%",
		"bloom: "   + str(snappedf(env.glow_bloom, 0.01)),
		"glow: "    + str(snappedf(env.glow_intensity, 0.01)),
		"wave: "    + str(WaveManager.wave_number),
		"enemies: " + str(EnemyManager.living_enemies.size()) + " / " + str(WaveManager.enemies_alive),
	]

	if debug_messages.size() > 0:
		lines.append("")
		for m: Dictionary in debug_messages:
			var flash: float  = m.age * 8.0
			var r: float      = 1.0
			var g: float      = 0.5 + 0.5 * sin(flash)
			var b: float      = 0.5 + 0.5 * sin(flash + PI)
			var hex: String   = Color(r, g, b).to_html(false)
			lines.append("[color=#" + hex + "]>> " + m.text + "[/color]")

	return "\n".join(lines)

func _on_wave_started(wave: int, modifier: Util.Modifier) -> void:
	push_debug("WAVE " + str(wave) + " — " + Util.Modifier.keys()[modifier])

func _on_wave_cleared(wave: int) -> void:
	push_debug("wave " + str(wave) + " cleared")
