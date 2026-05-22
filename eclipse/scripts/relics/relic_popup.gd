# relic_popup.gd
# Attach this script to a CanvasLayer node in your main scene (or as an autoload).
# Scene tree expected under this CanvasLayer:
#   RelicPopup (CanvasLayer)
#     Panel (PanelContainer)  — anchored bottom-right, e.g. anchor_right=1, anchor_bottom=1
#       VBox (VBoxContainer)
#         NameLabel (Label)
#         DescLabel (Label)
#
# In game.gd _ready(), assign:  RelicPopup.set_instance(%RelicPopup)   [if autoload pattern]
# OR simply place the scene under the HUD and call $RelicPopup.display(relic) from AncientContainer.

class_name RelicPopup
extends CanvasLayer

const DURATION:   float = 4.0
const FADE_START: float = 3.0

var _timer:  float = 0.0
var _active: bool  = false

# Singleton reference so AncientContainer can call RelicPopup.instance.display(relic)
# without needing a scene-tree path.  Set in game.gd: RelicPopup.instance = %RelicPopup
static var instance: RelicPopup = null

@onready var panel:      PanelContainer = $Panel
@onready var icon:       TextureRect    = $Panel/VBox/Icon
@onready var name_label: Label          = $Panel/VBox/NameLabel
@onready var desc_label: Label          = $Panel/VBox/DescLabel

func _ready() -> void:
	instance = self
	panel.hide()
	# Anchor panel to bottom-right corner
	panel.anchor_left   = 1.0
	panel.anchor_top    = 1.0
	panel.anchor_right  = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical   = Control.GROW_DIRECTION_BEGIN

# Call this from AncientContainer: RelicPopup.instance.display(relic)
func display(relic: RelicData) -> void:
	if relic == null:
		return
	name_label.text  = relic.display_name
	desc_label.text  = relic.description
	if icon != null:
		icon.texture = relic.icon
		icon.visible = relic.icon != null
	panel.modulate.a = 1.0
	panel.show()
	_timer  = 0.0
	_active = true

func _process(delta: float) -> void:
	if not _active:
		return
	_timer += delta
	if _timer >= FADE_START:
		panel.modulate.a = 1.0 - (_timer - FADE_START) / (DURATION - FADE_START)
	if _timer >= DURATION:
		_active = false
		panel.hide()
		panel.modulate.a = 1.0
