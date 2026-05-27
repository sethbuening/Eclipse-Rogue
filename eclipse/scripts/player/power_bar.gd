extends Control

@export var bar_height: float = 48.0
@export var bar_width:  float = 10.0
@export var lerp_speed: float = 6.0

@onready var liquid_body: TextureRect = $liquid_parent/body
@onready var swirl:       TextureRect = $liquid_parent/swirl
@onready var glass_frame: TextureRect = $glass_frame

var _light:         float = 100.0
var _display_light: float = 100.0

func _ready() -> void:
	liquid_body.material = liquid_body.material.duplicate()
	size.y                 = bar_height
	size.x                 = bar_width
	liquid_body.size.y     = bar_height
	liquid_body.size.x     = bar_width
	swirl.size.x           = bar_width
	liquid_body.position.y = 0.0
	_display_light         = _light
	_update_bar(_display_light / 100.0)

func set_light(value: float) -> void:
	_light = clampf(value, 0.0, 100.0)

func _process(delta: float) -> void:
	if absf(_display_light - _light) < 0.1:
		_display_light = _light
	else:
		_display_light = lerpf(_display_light, _light, minf(lerp_speed * delta, 1.0))
	_update_bar(_display_light / 100.0)

func _update_bar(fill_ratio: float) -> void:
	var mat := liquid_body.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("fill_ratio", fill_ratio)
	swirl.position.y = (1.0 - fill_ratio) * liquid_body.size.y - swirl.size.y / 2.0
	swirl.visible    = _light > 3.0
