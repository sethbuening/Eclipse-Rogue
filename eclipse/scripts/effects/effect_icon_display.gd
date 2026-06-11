# effect_icon_display.gd
# ---------------------------------------------------------------------------
# Draws effect icons above an enemy's head.
# If an effect has no icon texture, a solid colored square is drawn instead
# so effects are always visible even without art assigned.
# ---------------------------------------------------------------------------
class_name EffectIconDisplay
extends Node2D

const ICON_SIZE: float = 8.0
const ICON_GAP:  float = 2.0
const ICON_Y:    float = -28.0

# Each entry: { "tex": Texture2D|null, "color": Color }
var _entries: Array = []

func set_effects(effect_dict: Dictionary) -> void:
	_entries.clear()
	for id in effect_dict:
		var effect: EffectData = effect_dict[id] as EffectData
		if effect == null:
			continue
		_entries.append({ "tex": effect.icon, "color": effect.icon_color })
	queue_redraw()

func _draw() -> void:
	if _entries.is_empty():
		return

	var count: int    = _entries.size()
	var total_w: float = float(count) * ICON_SIZE + float(count - 1) * ICON_GAP
	var start_x: float = -total_w * 0.5

	for i in range(count):
		var entry     = _entries[i]
		var color: Color     = entry["color"]
		var tex:   Texture2D = entry["tex"]
		var rect: Rect2 = Rect2(
			start_x + float(i) * (ICON_SIZE + ICON_GAP),
			ICON_Y - ICON_SIZE * 0.5,
			ICON_SIZE,
			ICON_SIZE
		)

		if tex != null:
			draw_texture_rect(tex, rect, false, color)
		else:
			# Fallback: filled square in the effect's color with a dark border
			draw_rect(rect, color)
			draw_rect(rect, Color(0, 0, 0, 0.6), false, 1.0)
