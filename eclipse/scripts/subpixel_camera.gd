extends Camera2D

## Smooth top-down camera that follows a target node.

@export var target: Node2D
@export var follow_speed: float = 10.0

func _ready() -> void:
	if target == null:
		target = %Player
	if target:
		global_position = target.global_position

func _physics_process(delta: float) -> void:
	if target == null:
		return
	var t := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(target.global_position, t)
	if global_position.distance_to(target.global_position) < 0.25:
		global_position = target.global_position
