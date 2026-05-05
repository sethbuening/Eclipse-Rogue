extends CharacterBody2D

var movement_enabled: bool = true
@onready var speed: float = 100.0 * get_parent().scale.x

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var fps: int = int(1/delta)
	%DebugInfo.text = "fps: " + str(fps)
	if fps < 60:
		Log("Frame drop to fps: " + str(fps))
	
	if Input.is_action_just_pressed("attack_interact"):
		mine_around(global_position)
		Log("ATTACK/INTERACT")
	if Input.is_action_just_pressed("dev_mode"):
		if $CollisionShape2D.disabled:
			speed /= 10
			$CollisionShape2D.disabled = false
		else:
			speed *= 10
			$CollisionShape2D.disabled = true
	if Input.is_action_just_pressed("zoom_in"):
		$"../Camera2D".zoom *= 2
	if Input.is_action_just_pressed("zoom_out"):
		$"../Camera2D".zoom *= 0.5

func _physics_process(_delta):
	var input_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	if input_vector != Vector2.ZERO:
		input_vector = input_vector.normalized()
	
	if movement_enabled:
		velocity = input_vector * speed
	move_and_slide()

func mine_around(world_pos: Vector2, radius: int = 1) -> void:
	var center: Vector2i = %TilemapManager.world_to_map(world_pos)
	var count: int = 0
	for x: int in range(-radius, radius + 1):
		for y: int in range(-radius, radius + 1):
			if %TilemapManager.tile_exists(center + Vector2i(x, y)):
				count += 1
			%TilemapManager.damage_tile(center + Vector2i(x, y), 1)
	Log("Removed %d tiles" % [count])

func Log(msg: Variant) -> void:
	print("[player.gd] " + str(msg))
