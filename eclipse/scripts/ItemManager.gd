# item_manager.gd
extends Node

const DROP_COUNTS: Dictionary = {
	Util.tile.GOLD:   [1, 1],
	Util.tile.COPPER: [1, 1],
}

var _metal_map:    Dictionary      = {}   # Util.tile → MetalData
var dropped_items: Array[Node]     = []
var player:        CharacterBody2D = null
var game:          Node2D
var tilemap_manager: Node

const PICKUP_RADIUS: float = 8.0
const MAGNET_RADIUS: float = 64.0
const MAGNET_SPEED:  float = 180.0

@export var dropped_item_scene: PackedScene = preload("res://scenes/DroppedItem.tscn")

# ── ready ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_metal_map()

func _load_metal_map() -> void:
	for res: Resource in Util.load_resources("res://data/metals/"):
		if res is MetalData:
			_metal_map[res.tile_type] = res
			Log("Loaded metal: " + res.display_name)
		else:
			push_warning("ItemManager: skipping non-MetalData resource: " + res.resource_path)
	Log("Metal map built — %d metals loaded" % _metal_map.size())

# ── spawning ──────────────────────────────────────────────────────────────────

func _safe_spawn_pos(world_pos: Vector2, half_tile: float, radius: float) -> Vector2:
	for _attempt in range(10):
		var candidate: Vector2 = world_pos + Vector2(
			randf_range(-half_tile + radius, half_tile - radius),
			randf_range(-half_tile + radius, half_tile - radius)
		)
		var map_pos: Vector2i = tilemap_manager.world_to_map(candidate)
		if tilemap_manager.is_air(map_pos):
			return candidate
	return world_pos + Vector2(0, -half_tile - radius)

func spawn_dropped_item(world_pos: Vector2, type: Util.tile) -> void:
	if dropped_item_scene == null:
		Log("WARNING: dropped_item_scene is null — cannot spawn item")
		return
	if not DROP_COUNTS.has(type):
		return

	var range:     Array = DROP_COUNTS[type]
	var count:     int   = randi_range(range[0], range[1])
	var half_tile: float = tilemap_manager.TILE_SIZE.x / 2.0

	for i in count:
		var item: Sprite2D = dropped_item_scene.instantiate()
		item.item_type     = type
		item.vel = Vector2(
			(randf_range(-50.0, 50.0) + randf_range(-50.0, 50.0)) / 2.0,
			(randf_range(-60.0, -10.0) + randf_range(-60.0, -10.0)) / 2.0
		)
		item.z_vel           = (randf_range(40.0, 120.0) + randf_range(40.0, 120.0)) / 2.0
		item.pos             = _safe_spawn_pos(world_pos, half_tile, item.RADIUS)
		add_child(item)
		item.global_position = item.pos
		item.reset_physics_interpolation()
		item.visible         = true
		dropped_items.append(item)

	Log("Spawned " + str(count) + "x " + Util.tile.keys()[type] + " at " + str(world_pos) + " | total: " + str(dropped_items.size()))

# ── physics ───────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if player == null:
		return

	for item: Node in dropped_items.duplicate():
		if not is_instance_valid(item):
			dropped_items.erase(item)
			continue

		var dist: float = item.pos.distance_to(player.global_position)

		if dist < PICKUP_RADIUS:
			_collect(item)
			continue

		if dist < MAGNET_RADIUS:
			var dir: Vector2 = (player.global_position - item.pos).normalized()
			item.vel         = dir * MAGNET_SPEED

		if tilemap_manager != null:
			var move_dir:  Vector2  = item.vel.normalized() if item.vel.length() > 0.01 else Vector2.ZERO
			var check_pos: Vector2  = item.pos + move_dir * item.RADIUS + item.vel * delta
			var map_pos:   Vector2i = tilemap_manager.world_to_map(check_pos)
			if tilemap_manager.tile_exists(map_pos):
				var tile_center: Vector2 = tilemap_manager.map_to_world(map_pos)
				var diff:        Vector2 = item.pos - tile_center
				var tile_half:   float   = tilemap_manager.TILE_SIZE.x / 2.0
				if abs(diff.x) > abs(diff.y):
					item.vel.x *= -item.BOUNCE
					var sign_x: float = sign(diff.x)
					item.pos.x = tile_center.x + (tile_half + item.RADIUS) * sign_x
				else:
					item.vel.y *= -item.BOUNCE
					var sign_y: float = sign(diff.y)
					item.pos.y = tile_center.y + (tile_half + item.RADIUS) * sign_y
				if item.z <= 0.0:
					item.vel *= 0.7
			else:
				item.pos += item.vel * delta
		else:
			item.pos += item.vel * delta

		item.z_vel -= item.GRAVITY * delta
		item.z     += item.z_vel * delta
		if item.z < 0.0:
			item.z     = 0.0
			item.z_vel = -item.z_vel * item.BOUNCE
			item.vel  *= 0.8

		item.global_position = item.pos + Vector2(0, -item.z)
		item.z_index         = tilemap_manager.get_z_for(item.pos)

# ── collection ────────────────────────────────────────────────────────────────

func _collect(item: Node) -> void:
	var inventory: Node = player.get_node("Inventory")
	if _metal_map.has(item.item_type):
		var metal: MetalData = _metal_map[item.item_type]
		inventory.add_metal(metal, 1)
		Log("Collected metal: " + metal.display_name + " | remaining: " + str(dropped_items.size()))
	else:
		inventory.add(item.item_type, 1)
		Log("Collected " + Util.tile.keys()[item.item_type].to_lower() + " | remaining: " + str(dropped_items.size()))
	dropped_items.erase(item)
	item.queue_free()

func Log(msg: Variant) -> void:
	print("[item_manager.gd] " + str(msg))
