extends Control

@export var bar_height: float = 48.0
@export var bar_width:  float = 10

@onready var liquid_body: TextureRect = $liquid_parent/body
@onready var swirl:       TextureRect = $liquid_parent/swirl
@onready var glass_frame: TextureRect = $glass_frame

var _light: float = 100.0

func _ready() -> void:
	size.y             = bar_height
	size.x             = bar_width
	liquid_body.size.y = bar_height
	liquid_body.size.x = bar_width
	swirl.size.x       = bar_width
	liquid_body.position.y = 0.0
	_update_bar()

func set_light(value: float) -> void:
	print("health: %f" % [value])
	_light = clampf(value, 0.0, 100.0)
	_update_bar()

func _update_bar() -> void:
	var fill_ratio: float = _light / 100.0

	var mat := liquid_body.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("fill_ratio", fill_ratio)

	# use liquid_body's actual size, not bar_height
	swirl.position.y = (1.0 - fill_ratio) * liquid_body.size.y - swirl.size.y / 2.0
	swirl.visible    = _light > 3.0
