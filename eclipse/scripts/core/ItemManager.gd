# item_manager.gd
extends Node

var dropped_items: Array[Node]     = []
var player:        CharacterBody2D = null
var game:          Node2D
var tilemap_manager: Node

var magnet_radius: float = 64.0

@export var dropped_item_scene: PackedScene = preload("res://scenes/DroppedItem.tscn")

# ── relic/metal pool ──────────────────────────────────────────────────────────
var _relic_pool: Array[RelicData] = []

func _ready() -> void:
	_load_relic_pool()
	_load_metal_pool()

func _load_relic_pool() -> void:
	var resources: Array[Resource] = Util.load_resources("res://data/relics/")
	for res in resources:
		if res is RelicData:
			_relic_pool.append(res as RelicData)
	_relic_pool.shuffle()
	print("[ItemManager] Loaded %d relics into pool" % _relic_pool.size())

var _metal_map: Dictionary = {}  # Util.tile → MetalData

func _load_metal_pool() -> void:
	var resources: Array[Resource] = Util.load_resources("res://data/metals/")
	for res in resources:
		if res is MetalData and res.tile_type != null:
			_metal_map[res.tile_type] = res

# ── spawning ──────────────────────────────────────────────────────────────────

func spawn_xp(world_pos: Vector2) -> void:
	var count: int = randi_range(3, 5)
	for i in count:
		_spawn_item(world_pos, DroppedItem.DropType.XP, null)

func spawn_metal_drop(world_pos: Vector2, metal: MetalData) -> void:
	_spawn_item(world_pos, DroppedItem.DropType.METAL, metal)

func _spawn_item(world_pos: Vector2, type: DroppedItem.DropType, metal: MetalData) -> void:
	if dropped_item_scene == null:
		return
	var half_tile: float = tilemap_manager.TILE_SIZE.x / 2.0
	var item: DroppedItem = dropped_item_scene.instantiate()
	item.drop_type = type
	item.metal     = metal
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

# ── physics ───────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if player == null:
		return
	for item: Node in dropped_items.duplicate():
		if not is_instance_valid(item):
			dropped_items.erase(item)
			continue

		if item.collecting == DroppedItem.CollectPhase.ARC:
			item.tick_arc(player.global_position, delta)
			item.z_index = tilemap_manager.get_z_for(item.pos)
			if item.collect_timer >= item.COLLECT_DURATION:
				_finish_collect(item)
			continue

		var dist: float = item.pos.distance_to(player.global_position)
		if dist < magnet_radius:
			item.begin_collect(player.global_position)
			continue

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
					item.pos.x  = tile_center.x + (tile_half + item.RADIUS) * sign(diff.x)
				else:
					item.vel.y *= -item.BOUNCE
					item.pos.y  = tile_center.y + (tile_half + item.RADIUS) * sign(diff.y)
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

func _finish_collect(item: Node) -> void:
	var inventory: Node = player.get_node("Inventory")
	match item.drop_type:
		DroppedItem.DropType.XP:
			player.xp += 1
		DroppedItem.DropType.METAL:
			if item.metal != null:
				inventory.add_metal(item.metal, 1)
				Log("Collected: " + item.metal.display_name)
	dropped_items.erase(item)
	item.queue_free()

func Log(msg: Variant) -> void:
	print("[ItemManager] " + str(msg))
