# xp_bar.gd
# Attach directly to the ProgressBar node in HUD named "xp bar".
extends ProgressBar

## XP required to fill the bar and level up.
@export var xp_per_level: int = 100

func _ready() -> void:
	min_value       = 0
	max_value       = xp_per_level
	value           = 0
	show_percentage = false

	# Anchor to bottom of screen, full width
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	custom_minimum_size = Vector2(0, 12)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.15, 0.8)
	add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.7, 1.0, 1.0)
	add_theme_stylebox_override("fill", fill)

func set_xp(current: int) -> void:
	value = current % xp_per_level
