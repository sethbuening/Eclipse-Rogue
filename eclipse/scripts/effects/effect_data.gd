# effect_data.gd
# ---------------------------------------------------------------------------
# Base resource for all effects.  Subclass this — one script per
# effect type — exactly as abilities extend AbilityData and relics extend
# RelicData.
#
# Each subclass lives in  scripts/enemies/effects/<name>.gd
# and is instantiated by EffectManager (or directly by abilities).
#
# Lifecycle (called by Enemy._tick_effects / apply_effects):
#   apply(enemy)             — called once when the effect is first applied
#                              (or re-applied to refresh/stack).
#   tick(delta, enemy)       — called every AI tick while active.
#   on_remove(enemy)         — called once when the effect expires or is
#                              forcibly removed.
#
# The icon (Texture2D) is shown above the enemy's head as a small sprite
# while the effect is active.  Leave it null for invisible/internal effects.
# ---------------------------------------------------------------------------
class_name EffectData
extends Resource

# ── identity ──────────────────────────────────────────────────────────────────

## Unique string key — used as the dictionary key in Enemy._effects.
## Must be unique across all effect types.
@export var id:           String    = ""
## Human-readable name shown in tooltips / debug.
@export var display_name: String    = ""
## Short description for UI.
@export_multiline var description: String = ""
## Icon shown above the enemy's head while this effect is active.
## A null icon means no visual indicator is shown.
@export var icon:         Texture2D = null
## Tint applied to the icon sprite (use for colour-coding families).
@export var icon_color:   Color     = Color.WHITE

# ── runtime state (set by Enemy when it applies the effect) ──────────────────

## Remaining duration in seconds.  The Enemy owns this value; it is set
## on apply() and decremented each tick.  Effects without a time limit
## (e.g. knockback) should override tick() and remove themselves manually.
var duration: float = 0.0

# ── API ───────────────────────────────────────────────────────────────────────

## Called by Enemy.apply_effects() each time the effect is applied or refreshed.
## [enemy] is the enemy the effect is being applied to.
## [new_duration] is the requested duration after resistance is factored in.
## Return true to allow the apply, false to silently reject it (e.g. already
## at a stronger application).
func apply(enemy: Enemy, new_duration: float) -> bool:
	duration = new_duration
	return true

## Called every AI tick (same cadence as Enemy.tick_ai) while the effect is
## active.  The base implementation just counts down the timer; call super()
## if you override and want the default expiry behaviour to keep working.
func tick(delta: float, enemy: Enemy) -> void:
	duration -= delta

## Called once when the effect expires naturally (duration <= 0) or is
## forcibly removed via Enemy.remove_effects().  Use to undo any persistent
## stat changes made in apply().
func on_remove(enemy: Enemy) -> void:
	pass

## Returns true when the effect has naturally expired.
## Enemy._tick_effects() checks this and calls on_remove + erases the entry.
func is_expired() -> bool:
	return duration <= 0.0
