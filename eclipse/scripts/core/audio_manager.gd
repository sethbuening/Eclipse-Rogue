extends Node2D
## Audio manager node. Intended to be globally loaded as a 2D Scene.
## Handles [method create_2d_audio_at_location] and [method create_audio]
## for the playback and concurrency-culling of simultaneous sound effects.
##
## To use: create a Node2D scene with this script, add it as an autoload,
## set [member sounds_folder] to your folder of SoundEffect .tres files,
## and call either method from anywhere in your project.
## Resources are scanned and loaded automatically at runtime — no editor tool needed.

# ── config ────────────────────────────────────────────────────────────────────
## Folder containing all SoundEffect .tres files. Scanned automatically on _ready.
@export var sounds_folder: String = "res://data/sounds/"

# ── private ───────────────────────────────────────────────────────────────────
var _sound_effect_dict: Dictionary = {}  # SOUND_EFFECT_TYPE (int) → SoundEffect
var _rng: RandomNumberGenerator    = RandomNumberGenerator.new()

# ── xp collect pitch stack ────────────────────────────────────────────────────
## Pitch of the very first collect in a chain.
const XP_PITCH_BASE:    float = 0.9
## How much pitch rises per consecutive collect.
## 0.06 ≈ one semitone, so 12 collects ≈ one octave.
const XP_PITCH_STEP:    float = 0.06
## Hard ceiling — prevents the sound going ultrasonic on huge XP bursts.
const XP_PITCH_MAX:     float = 2.0
## Seconds without a collect before pitch resets to base.
const XP_RESET_AFTER:   float = 0.35

var _xp_pitch_current:  float = XP_PITCH_BASE
var _xp_reset_timer:    float = 0.0

# ── lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_rng.randomize()
	_load_sound_effects()

func _load_sound_effects() -> void:
	var resources: Array[Resource] = Util.load_resources(sounds_folder)
	for resource: Resource in resources:
		if not resource is SoundEffect:
			continue
		var sound_effect := resource as SoundEffect
		if sound_effect.type == SoundEffect.SOUND_EFFECT_TYPE.NONE:
			push_warning("AudioManager: '%s' has type NONE — skipping." % resource.resource_path)
			continue
		_sound_effect_dict[sound_effect.type] = sound_effect
	print("[AudioManager] loaded %d sound effect(s)." % _sound_effect_dict.size())

# ── public API ────────────────────────────────────────────────────────────────

## Play a positional (2D spatial) sound at [param location].
## Use for in-world events so the listener hears distance and panning.
func create_2d_audio_at_location(location: Vector2, type: SoundEffect.SOUND_EFFECT_TYPE) -> void:
	var sound_effect: SoundEffect = _get_sound_effect(type)
	if sound_effect == null or not sound_effect.has_open_limit():
		return
	sound_effect.change_audio_count(1)
	var player := AudioStreamPlayer2D.new()
	add_child(player)
	player.global_position = location
	_configure_player(player, sound_effect)
	player.finished.connect(sound_effect.on_audio_finished)
	player.finished.connect(player.queue_free)
	player.play()

## Play a non-positional (global) sound — UI events, music stings, etc.
func create_audio(type: SoundEffect.SOUND_EFFECT_TYPE) -> void:
	var sound_effect: SoundEffect = _get_sound_effect(type)
	if sound_effect == null or not sound_effect.has_open_limit():
		return
	sound_effect.change_audio_count(1)
	var player := AudioStreamPlayer.new()
	add_child(player)
	_configure_player(player, sound_effect)
	player.finished.connect(sound_effect.on_audio_finished)
	player.finished.connect(player.queue_free)
	player.play()

## Play the XP collect sound with pitch stacking.
## Each call within XP_RESET_AFTER seconds raises the pitch by XP_PITCH_STEP.
## After XP_RESET_AFTER seconds with no collect the pitch silently resets.
## Set pitch_randomness to 0.0 on the XP_COLLECT SoundEffect resource —
## pitch is driven entirely by the stack counter here.
func play_xp_collect() -> void:
	var sound_effect: SoundEffect = _get_sound_effect(SoundEffect.SOUND_EFFECT_TYPE.XP_COLLECT)
	if sound_effect == null:
		return
	# Skip the has_open_limit check — XP sounds are short and dense collection
	# moments are exactly when feedback matters most.  Cap via XP_PITCH_MAX instead.
	sound_effect.change_audio_count(1)
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.stream    = sound_effect.sound_effect
	player.volume_db = sound_effect.volume
	player.bus       = &"SFX"
	player.pitch_scale = _xp_pitch_current
	player.finished.connect(sound_effect.on_audio_finished)
	player.finished.connect(player.queue_free)
	player.play()
	# Advance pitch for next collect and restart the silence window.
	_xp_pitch_current = minf(_xp_pitch_current + XP_PITCH_STEP, XP_PITCH_MAX)
	_xp_reset_timer   = XP_RESET_AFTER

# ── lifecycle ─────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _xp_reset_timer <= 0.0:
		return
	_xp_reset_timer -= delta
	if _xp_reset_timer <= 0.0:
		_xp_reset_timer   = 0.0
		_xp_pitch_current = XP_PITCH_BASE

# ── private helpers ───────────────────────────────────────────────────────────
func _get_sound_effect(type: SoundEffect.SOUND_EFFECT_TYPE) -> SoundEffect:
	if not _sound_effect_dict.has(type):
		push_error("AudioManager: no SoundEffect registered for type '%s' (int %d). " % \
				[SoundEffect.SOUND_EFFECT_TYPE.keys()[type], type] + \
				"Check that a .tres with this type exists in '%s'." % sounds_folder)
		return null
	return _sound_effect_dict[type] as SoundEffect

## Applies stream, volume, pitch, and bus routing to [param player].
## Accepts both AudioStreamPlayer and AudioStreamPlayer2D via Node.set().
func _configure_player(player: Node, sound_effect: SoundEffect) -> void:
	player.set("stream",    sound_effect.sound_effect)
	player.set("volume_db", sound_effect.volume)
	player.set("bus",       &"SFX-ui")
	var pitch: float = sound_effect.pitch_scale
	if sound_effect.pitch_randomness > 0.0:
		pitch += _rng.randf_range(-sound_effect.pitch_randomness, sound_effect.pitch_randomness)
	player.set("pitch_scale", clampf(pitch, 0.05, 4.0))
