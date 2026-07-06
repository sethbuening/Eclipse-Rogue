# item_manager.gd
extends Node

var dropped_items:   Array[Node]     = []
var player:          CharacterBody2D = null
var game:            Node2D
var tilemap_manager: Node

var magnet_radius: float = 48.0

@export var dropped_item_scene: PackedScene = preload("res://scenes/DroppedItem.tscn")

# ── pools ─────────────────────────────────────────────────────────────────────
var _relic_pool: Array[RelicData] = []

## Util.tile enum value → ItemData (for ore tile drops)
var _tile_item_map: Dictionary = {}
## StringName id → ItemData
var _item_id_map:   Dictionary = {}

func _ready() -> void:
	_load_relic_pool()
	_load_item_pool()

func _load_relic_pool() -> void:
	var resources: Array[Resource] = Util.load_resources("res://data/relics/")
	for res in resources:
		if res is RelicData:
			_relic_pool.append(res as RelicData)
	_relic_pool.shuffle()
	print("[ItemManager] Loaded %d relics into pool" % _relic_pool.size())

func _load_item_pool() -> void:
	var resources: Array[Resource] = Util.load_resources("res://data/items/")
	for res in resources:
		if res is ItemData:
			var it := res as ItemData
			_item_id_map[it.id] = it
			# ItemData can optionally export a tile_type: StringName
			# matching a Util.tile value so the tilemap knows what to drop.
			if it.get("tile_type") != null and it.tile_type != &"":
				_tile_item_map[it.tile_type] = it
	print("[ItemManager] Loaded %d items" % _item_id_map.size())

func get_item_by_id(id: StringName) -> ItemData:
	return _item_id_map.get(id, null)

func get_item_for_tile(tile_type) -> ItemData:
	return _tile_item_map.get(tile_type, null)

func get_all_items() -> Array:
	return _item_id_map.values()

# ── spawning ──────────────────────────────────────────────────────────────────

func spawn_xp(world_pos: Vector2, count: int = 1) -> void:
	for i in count:
		_spawn(world_pos, DroppedItem.DropType.XP, null)

func spawn_item_drop(world_pos: Vector2, item: ItemData) -> void:
	_spawn(world_pos, DroppedItem.DropType.ITEM, item)

func _spawn(world_pos: Vector2, type: DroppedItem.DropType, item: ItemData) -> void:
	if dropped_item_scene == null:
		return
	var half_tile: float   = tilemap_manager.TILE_SIZE.x / 2.0
	var d: DroppedItem     = dropped_item_scene.instantiate()
	d.drop_type = type
	d.item      = item
	d.vel = Vector2(
		(randf_range(-50.0, 50.0) + randf_range(-50.0, 50.0)) / 2.0,
		(randf_range(-60.0, -10.0) + randf_range(-60.0, -10.0)) / 2.0
	)
	d.z_vel           = (randf_range(40.0, 120.0) + randf_range(40.0, 120.0)) / 2.0
	d.pos             = _safe_spawn_pos(world_pos, half_tile, d.RADIUS)
	add_child(d)
	d.global_position = d.pos
	d.reset_physics_interpolation()
	d.visible         = true
	dropped_items.append(d)

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
	for d: Node in dropped_items.duplicate():
		if not is_instance_valid(d):
			dropped_items.erase(d)
			continue

		if d.collecting == DroppedItem.CollectPhase.ARC:
			d.tick_arc(player.global_position, delta)
			d.z_index = tilemap_manager.get_z_for(d.pos)
			if d.collect_timer >= d.COLLECT_DURATION:
				_finish_collect(d)
			continue

		var dist: float = d.pos.distance_to(player.global_position)
		if dist < magnet_radius:
			d.begin_collect(player.global_position)
			continue

		if tilemap_manager != null:
			var move_dir:  Vector2  = d.vel.normalized() if d.vel.length() > 0.01 else Vector2.ZERO
			var check_pos: Vector2  = d.pos + move_dir * d.RADIUS + d.vel * delta
			var map_pos:   Vector2i = tilemap_manager.world_to_map(check_pos)
			if tilemap_manager.tile_exists(map_pos):
				var tile_center: Vector2 = tilemap_manager.map_to_world(map_pos)
				var diff:        Vector2 = d.pos - tile_center
				var tile_half:   float   = tilemap_manager.TILE_SIZE.x / 2.0
				if abs(diff.x) > abs(diff.y):
					d.vel.x *= -d.BOUNCE
					d.pos.x  = tile_center.x + (tile_half + d.RADIUS) * sign(diff.x)
				else:
					d.vel.y *= -d.BOUNCE
					d.pos.y  = tile_center.y + (tile_half + d.RADIUS) * sign(diff.y)
				if d.z <= 0.0:
					d.vel *= 0.7
			else:
				d.pos += d.vel * delta
		else:
			d.pos += d.vel * delta
		d.z_vel -= d.GRAVITY * delta
		d.z     += d.z_vel * delta
		if d.z < 0.0:
			d.z     = 0.0
			d.z_vel = -d.z_vel * d.BOUNCE
			d.vel  *= 0.8
		d.global_position = d.pos + Vector2(0, -d.z)
		d.z_index         = tilemap_manager.get_z_for(d.pos)

# ── collection ────────────────────────────────────────────────────────────────

func _finish_collect(d: Node) -> void:
	var run_inv: RunInventory = player.get_node("RunInventory")
	match d.drop_type:
		DroppedItem.DropType.XP:
			player.xp += 1
			AudioManagerScene.play_xp_collect()
		DroppedItem.DropType.ITEM:
			if d.item != null and run_inv != null:
				run_inv.add_item(d.item, 1)
				Log("Collected: " + d.item.display_name)
	dropped_items.erase(d)
	d.queue_free()

func Log(msg: Variant) -> void:
	print("[ItemManager] " + str(msg))
