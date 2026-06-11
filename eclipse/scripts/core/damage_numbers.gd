extends Node

# ── DamageNumbers autoload ────────────────────────────────────────────────────
# Add this as an autoload named "DamageNumbers" in Project > Project Settings >
# Autoload.  It self-initialises a CanvasLayer so numbers always render on top.
#
# Usage:
#   DamageNumbers.spawn(world_position, amount)               # normal damage
#   DamageNumbers.spawn(world_position, amount, true)         # crit
#   DamageNumbers.spawn_heal(world_position, amount)          # healing

const RISE_SPEED:  float = 48.0   # pixels per second upward
const DRIFT_RANGE: float = 20.0   # max horizontal drift (±)
const LIFETIME:    float = 0.90   # seconds before fully faded
const FADE_START:  float = 0.45   # seconds before fade begins
const FONT_SIZE_N: int   = 16     # normal damage
const FONT_SIZE_C: int   = 22     # crit damage
const FONT_SIZE_H: int   = 16     # healing

var _canvas: CanvasLayer

func _ready() -> void:
	_canvas                      = CanvasLayer.new()
	_canvas.layer                = 128
	_canvas.name                 = "DamageNumbersCanvas"
	# follow_viewport_enabled makes the CanvasLayer inherit the camera transform,
	# so Control positions map 1:1 to world coordinates — no manual conversion needed.
	_canvas.follow_viewport_enabled = true
	add_child(_canvas)

# ── public API ────────────────────────────────────────────────────────────────

func spawn(world_pos: Vector2, amount: int, is_crit: bool = false) -> void:
	var label := _make_label()
	label.text = str(amount) + ("!" if is_crit else "")
	label.add_theme_font_size_override("font_size", FONT_SIZE_C if is_crit else FONT_SIZE_N)
	label.add_theme_color_override("font_color",         Color("ff4444") if not is_crit else Color("ff8800"))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	label.add_theme_constant_override("outline_size", 3)
	_launch(label, world_pos)

func spawn_heal(world_pos: Vector2, amount: int) -> void:
	var label := _make_label()
	label.text = "+" + str(amount)
	label.add_theme_font_size_override("font_size", FONT_SIZE_H)
	label.add_theme_color_override("font_color",         Color("44dd66"))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	label.add_theme_constant_override("outline_size", 3)
	_launch(label, world_pos)

func spawn_dodge(world_pos: Vector2) -> void:
	var label := _make_label()
	label.custom_minimum_size = Vector2(80, 24)
	label.text = "DODGED"
	label.add_theme_font_size_override("font_size", FONT_SIZE_C)
	label.add_theme_color_override("font_color",         Color("88ccff"))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	label.add_theme_constant_override("outline_size", 3)
	_launch(label, world_pos)

# ── internals ─────────────────────────────────────────────────────────────────

func _make_label() -> Label:
	var label                      := Label.new()
	label.horizontal_alignment      = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment        = VERTICAL_ALIGNMENT_CENTER
	# Give the label a fixed size so text-anchor="center" actually centers over
	# the spawn point rather than hanging to the right of it.
	label.custom_minimum_size       = Vector2(60, 24)
	label.mouse_filter              = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(label)
	return label

func _launch(label: Label, world_pos: Vector2) -> void:
	# With follow_viewport_enabled the CanvasLayer is already in world space,
	# so we set position directly — offset left by half the label width to center it,
	# and up a few pixels so it starts above the sprite origin.
	var start := world_pos + Vector2(
		-label.custom_minimum_size.x * 0.5 + randf_range(-DRIFT_RANGE * 0.5, DRIFT_RANGE * 0.5),
		-label.custom_minimum_size.y - 8.0
	)
	label.position = start

	var drift := randf_range(-DRIFT_RANGE, DRIFT_RANGE)
	var tween  := create_tween()
	tween.set_parallel(true)

	tween.tween_property(label, "position",
		start + Vector2(drift, -RISE_SPEED * LIFETIME),
		LIFETIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var hold := LIFETIME - FADE_START
	tween.tween_interval(hold)
	tween.tween_property(label, "modulate:a", 0.0, FADE_START)

	tween.chain().tween_callback(label.queue_free)
