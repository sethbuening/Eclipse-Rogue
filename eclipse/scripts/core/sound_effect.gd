class_name SoundEffect
extends Resource

# ── sound type enum ───────────────────────────────────────────────────────────
## Add one entry per distinct sound effect in your game.
## Use descriptive names — you'll be reading these everywhere.
enum SOUND_EFFECT_TYPE {
	NONE,
	# ── player ────────────────────────────────────────────────────────────────
	PLAYER_HIT,
	PLAYER_DEATH,
	PLAYER_DASH,
	# ── enemies ───────────────────────────────────────────────────────────────
	ENEMY_HIT,
	ENEMY_DEATH,
	# ── mining ────────────────────────────────────────────────────────────────
	TILE_MINE,
	ORE_COLLECT,
	# ── abilities ─────────────────────────────────────────────────────────────
	ABILITY_FIRE,
	ABILITY_CRIT,
	# ── ui ────────────────────────────────────────────────────────────────────
	UI_SELECT,
	UI_CONFIRM,
	# ── collection ────────────────────────────────────────────────────────────
	XP_COLLECT,
	# ── waves ─────────────────────────────────────────────────────────────────
	HORDE_HORN,
	ENCOUNTER_ALERT,
	# ── forging ───────────────────────────────────────────────────────────────
	FORGE_START,
	FORGE_END,
}

# ── identity ──────────────────────────────────────────────────────────────────
@export_group("Identity")
## Which sound this resource represents. Must be unique across all SoundEffects
## registered with the AudioManager.
@export var type: SOUND_EFFECT_TYPE = SOUND_EFFECT_TYPE.NONE

# ── audio ─────────────────────────────────────────────────────────────────────
@export_group("Audio")
## The audio file to play.
@export var sound_effect: AudioStream

## Base volume in decibels.
@export_range(-80.0, 6.0, 0.5) var volume: float = 0.0

## Base pitch multiplier.
@export_range(0.1, 4.0, 0.05) var pitch_scale: float = 1.0

## Max random pitch offset added/subtracted each play (0 = no randomness).
@export_range(0.0, 1.0, 0.01) var pitch_randomness: float = 0.0

# ── concurrency ───────────────────────────────────────────────────────────────
@export_group("Concurrency")
## Max simultaneous instances. Calls beyond this are suppressed.
@export_range(1, 32, 1) var limit: int = 4

# ── runtime state ─────────────────────────────────────────────────────────────
var _audio_count: int = 0

# ── helpers ───────────────────────────────────────────────────────────────────
## Returns true if another instance can be spawned right now.
func has_open_limit() -> bool:
	return _audio_count < limit

## Adjusts the active instance count. Pass 1 when starting, -1 when finished.
func change_audio_count(amount: int) -> void:
	_audio_count = maxi(0, _audio_count + amount)

## Connected to each AudioStreamPlayer's [signal AudioStreamPlayer.finished]
## so the concurrency slot is freed automatically when playback ends.
func on_audio_finished() -> void:
	change_audio_count(-1)
