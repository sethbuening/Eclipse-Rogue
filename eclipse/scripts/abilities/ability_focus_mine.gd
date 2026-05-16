class_name AbilityFocusMine
extends AbilityData

var charge:         float          = 0.0
var charging:       bool           = false
var exploded:       bool           = false
var targeted_tiles: Array[Vector2i] = []

const CHARGE_TIME: float = 1.5

func activate(context: Dictionary) -> void:
	var player:  Node  = context.get("player")
	var tilemap: Node  = context.get("tilemap")
	var delta:   float = context.get("delta", 0.0)
	var pressed: bool  = context.get("pressed", false)
	if player == null or tilemap == null:
		return
	if context.get("orb_shattered", false):
		return
	if pressed:
		if not exploded:
			if not charging:
				targeted_tiles = _get_focus_tiles(player, tilemap)
			if targeted_tiles.size() != 0:
				context["lock_movement"] = true
				charging                  = true
				charge                   += delta
				var t: float              = charge / CHARGE_TIME
				for tile: Vector2i in targeted_tiles:
					tilemap.set_tile_color(tile, Color(1.0 + t, 1.0 + t, 1.0 + t))
				context["orb_t"] = t
				if charge >= CHARGE_TIME:
					_explode(player, tilemap, context)
					charge                   = 0.0
					charging                 = false
					exploded                 = true
					context["lock_movement"] = false
					context["orb_t"]         = 0.0
					context["shatter"]       = true
	else:
		_clear_tiles(tilemap)
		charge   = 0.0
		charging = false

func reset_exploded() -> void:
	exploded = false

func _explode(player: Node, tilemap: Node, context: Dictionary) -> void:
	var power: int = int(stats.mining_power * context.get("orb_power", 1.0))
	for tile: Vector2i in targeted_tiles:
		player.light -= stats.light_cost
		tilemap.damage_tile(tile, power)
		ParticleManager.spawn_focus_spark(tilemap.map_to_world(tile))
	targeted_tiles.clear()

func _clear_tiles(tilemap: Node) -> void:
	for tile: Vector2i in targeted_tiles:
		tilemap.set_tile_color(tile, Color.WHITE)
	targeted_tiles.clear()

func _get_focus_tiles(player: Node, tilemap: Node) -> Array[Vector2i]:
	var start: Vector2i = tilemap.world_to_map(player.global_position) + player.direction
	var limit: int      = stats.mining_radius * 4 - 1
	if tilemap.is_air(start):
		return []
	var visited: Dictionary      = { start: true }
	var queue:   Array[Vector2i] = [start]
	var result:  Array[Vector2i] = []
	while queue.size() > 0 and result.size() < limit:
		var current: Vector2i = queue.pop_front()
		result.append(current)
		for neighbor: Vector2i in [
			current + Vector2i( 0, -1),
			current + Vector2i( 0,  1),
			current + Vector2i(-1,  0),
			current + Vector2i( 1,  0),
		]:
			if not visited.has(neighbor) and tilemap.tile_exists(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	return result
