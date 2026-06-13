# ancient_container.gd
# Spawned beneath a 2×2 relic rock cluster. When the player mines all 4 tiles
# the container becomes interactable. Interacting opens the relic choice screen
# (3 cards: mix of new relics and upgrades to owned relics) instead of
# immediately collecting a fixed relic.
class_name AncientContainer
extends Node2D

@export var relic: RelicData = null  # kept for TilemapManager compatibility; used as pool hint

const INTERACT_RADIUS: float = 64.0

var _interactable:  bool              = false
var _player:        CharacterBody2D   = null
var _prompt_box:    HBoxContainer     = null
var _prompt_icon:   TextureRect       = null
var _prompt_label:  Label             = null
const PROMPT_OFFSET: Vector2 = Vector2(-65, -55)

func _ready() -> void:
	process_priority = -1
	_player = get_tree().get_first_node_in_group("player")
	_build_prompt()
	Util.input_device_changed.connect(_update_prompt_icon)

func _build_prompt() -> void:
	_prompt_box           = HBoxContainer.new()
	_prompt_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt_box.add_theme_constant_override("separation", 6)
	_prompt_box.visible   = false
	add_child(_prompt_box)

	_prompt_icon                      = TextureRect.new()
	_prompt_icon.custom_minimum_size  = Vector2(24, 24)
	_prompt_icon.expand_mode          = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_prompt_icon.stretch_mode         = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_prompt_box.add_child(_prompt_icon)

	_prompt_label      = Label.new()
	_prompt_label.text = "Choose Relic"
	_prompt_box.add_child(_prompt_label)

	_prompt_box.position    = PROMPT_OFFSET
	_prompt_box.z_as_relative = false
	_prompt_box.z_index     = 4096

	_update_prompt_icon()

func _update_prompt_icon() -> void:
	if _prompt_icon == null:
		return
	_prompt_icon.texture = Util.get_action_icon("interact")

func _process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
		return
	if not _interactable:
		return
	var dist:   float = global_position.distance_to(_player.global_position)
	var nearby: bool  = dist <= INTERACT_RADIUS
	_prompt_box.visible = nearby
	if nearby and Input.is_action_just_pressed("interact"):
		_collect()

func _collect() -> void:
	if _player == null:
		return
	_prompt_box.visible = false
	_interactable       = false
	# Ask the player to open the relic choice screen; free self when done.
	_player.show_relic_screen(self)

func set_interactable(enabled: bool) -> void:
	_interactable = enabled
	if _prompt_box != null:
		_prompt_box.visible = false
