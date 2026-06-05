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
	player.set("bus",       &"SFX")
	var pitch: float = sound_effect.pitch_scale
	if sound_effect.pitch_randomness > 0.0:
		pitch += _rng.randf_range(-sound_effect.pitch_randomness, sound_effect.pitch_randomness)
	player.set("pitch_scale", clampf(pitch, 0.05, 4.0))
