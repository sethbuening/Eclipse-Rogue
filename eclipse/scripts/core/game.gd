# game.gd
extends Node2D

const DEBUG_MSG_DURATION: float = 3.0
var debug_messages: Array[Dictionary] = []

const FPS_DROP_THRESHOLD: int = 40
var _prev_fps: int = 0
var _frame_times: Array[float] = []

func _ready() -> void:
	ParticleManager.tilemap_manager = %TilemapManager
	EnemyManager.tilemap    = %TilemapManager
	EnemyManager.player             = %Player
	ItemManager.player              = %Player
	ItemManager.game                = self
	ItemManager.tilemap_manager     = %TilemapManager
	WaveManager.encounter_started.connect(_on_encounter_started)
	WaveManager.horde_started.connect(_on_horde_started)
	WaveManager.forging_wave_started.connect(_on_forging_wave_started)
	WaveManager.forging_wave_ended.connect(_on_forging_wave_ended)
	%TilemapManager.camera = %Camera2D
	%GraphManager.generate()
	%OrbGraphMenu.player            = %Player
	%DebugLabel.add_theme_font_size_override(
		"normal_font_size",
		DisplayServer.window_get_size().y / 50
	)
	#NavManager.build(%TilemapManager)
	FlowField.initialize(%TilemapManager)
	$Forge.init(%Player)

func _process(delta: float) -> void:
	FlowField.set_target(%Player.global_position)

	_process_debug_messages(delta)
	var player: CharacterBody2D = %Player
	if player == null:
		return
	var fps: int         = int(1.0 / delta)
	var env: Environment = %Environment.environment

	if _prev_fps >= FPS_DROP_THRESHOLD and fps < FPS_DROP_THRESHOLD:
		_report_drop(fps)
	_prev_fps = fps

	%DebugLabel.parse_bbcode(_build_debug_text(fps, env, player))

func _report_drop(fps: int) -> void:
	var shockwaves_active: int = 0
	var shockwaves_mining: int = 0
	for s in GoldShockwave._pool:
		if s._active:
			shockwaves_active += 1
		if s._mining:
			shockwaves_mining += 1
	push_debug("DROP %d fps | shockwaves active=%d mining=%d | enemies=%d" % [
		fps,
		shockwaves_active,
		shockwaves_mining,
		EnemyManager.living_enemies.size(),
	], true)

func push_debug(msg: String, flash: bool = false) -> void:
	debug_messages.append({ "text": msg, "age": 0.0, "flash": flash })

func _process_debug_messages(delta: float) -> void:
	for m: Dictionary in debug_messages:
		m.age += delta
	debug_messages = debug_messages.filter(func(m: Dictionary): return m.age < DEBUG_MSG_DURATION)

func _build_debug_text(fps: int, env: Environment, player: CharacterBody2D) -> String:
	var lines: Array[String] = [
		"fps: "     + str(fps),
		"bloom: "   + str(snappedf(env.glow_bloom, 0.01)),
		"glow: "    + str(snappedf(env.glow_intensity, 0.01)),
		"enemies: " + str(WaveManager._enemies_alive) + " / " + str(EnemyManager.living_enemies.size()),
	]

	# ── ore collection counts ─────────────────────────────────────────────────
	var inventory: Node = %Player.get_node("Inventory")
	for relic: RelicData in inventory.relics:
		lines.append(relic.display_name + " x" + str(inventory.get_relic_quantity(relic)))
	for metal: MetalData in inventory.metals:
		lines.append(metal.display_name + " collected: " + str(inventory.get_metal_quantity(metal)))

	if debug_messages.size() > 0:
		lines.append("")
		for m: Dictionary in debug_messages:
			if m.flash:
				var f:   float  = m.age * 8.0
				var r:   float  = 1.0
				var g:   float  = 0.5 + 0.5 * sin(f)
				var b:   float  = 0.5 + 0.5 * sin(f + PI)
				var hex: String = Color(r, g, b).to_html(false)
				lines.append("[color=#" + hex + "]>> " + m.text + "[/color]")
			else:
				lines.append(">> " + m.text)

	return "\n".join(lines)

func _on_encounter_started(type: WaveManager.Encounter) -> void:
	push_debug("ENCOUNTER — " + WaveManager.Encounter.keys()[type], true)

func _on_horde_started() -> void:
	push_debug("HORDE incoming!", true)

func _on_forging_wave_started() -> void:
	push_debug("Forging wave — enemies alerted", false)

func _on_forging_wave_ended() -> void:
	push_debug("Forging wave ended", false)
