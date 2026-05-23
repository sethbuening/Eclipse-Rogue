class_name AbilityFocusMine
extends AbilityData

var charge:         float           = 0.0
var charging:       bool            = false
var exploded:       bool            = false
var targeted_tiles: Array[Vector2i] = []

const CHARGE_TIME:       float = 0.75
const GUARANTEED_CRITS:  int   = 3

func _init() -> void:
	main_stats = ["mining_power", "mining_radius"]

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
				# Use target_pos from context (aim position) when available so the
				# focus mine respects the mouse / joystick cursor rather than
				# always hitting the tile immediately in front of the player.
				var aim: Vector2 = context.get("target_pos", Vector2.ZERO)
				targeted_tiles = _get_focus_tiles(player, tilemap, aim)
			var has_tiles: bool = targeted_tiles.size() != 0
			charging             = true
			charge              += delta
			var t: float         = charge / CHARGE_TIME
			if has_tiles:
				context["lock_movement"] = true
				for tile: Vector2i in targeted_tiles:
					tilemap.set_tile_color(tile, Color(1.0 + t, 1.0 + t, 1.0 + t))
			context["orb_t"] = t
			if charge >= CHARGE_TIME:
				if has_tiles:
					_explode(player, tilemap)
				else:
					_grant_crits(player)
				charge                   = 0.0
				charging                 = false
				exploded                 = true
				context["lock_movement"] = false
				context["orb_t"]         = 0.0
				context["activated"]     = true
	else:
		_clear_tiles(tilemap)
		charge   = 0.0
		charging = false

func reset_exploded() -> void:
	exploded = false

func _grant_crits(player: Node) -> void:
	player.guaranteed_crits += GUARANTEED_CRITS
	stats.apply_to_player(player)

func _explode(player: Node, tilemap: Node) -> void:
	var power: int = int(get_stat("mining_power"))
	var removed: Array[Vector2i] = []
	for tile: Vector2i in targeted_tiles:
		ParticleManager.spawn_focus_spark(tilemap.map_to_world(tile))
		var died: bool = tilemap.tile_health.get(tile, 1) <= power
		if died:
			removed.append(tile)
		tilemap.damage_tile_silent(tile, power)
	tilemap.flush_removed_tiles(removed)
	targeted_tiles.clear()
	stats.apply_to_player(player)

func _clear_tiles(tilemap: Node) -> void:
	for tile: Vector2i in targeted_tiles:
		tilemap.set_tile_color(tile, Color.WHITE)
	targeted_tiles.clear()

## Find mineable tiles near the aim position.  We search for the tile within
## the ability's range that is closest to the aim cursor (mouse / joystick),
## then flood-fill outward from there up to mining_radius tiles.
func _get_focus_tiles(player: Node, tilemap: Node, aim: Vector2) -> Array[Vector2i]:
	# Ability cast range — how far from the player the focus mine can start.
	var cast_range: float = get_stat("range") if stats and stats.range > 0.0 else 0.0

	var start: Vector2i
	if aim != Vector2.ZERO and cast_range > 0.0:
		# Find the existing mineable tile within cast_range that is closest to
		# the aim cursor.  This respects range and always lands on a real tile.
		start = _find_nearest_tile_to_aim(player, tilemap, aim, cast_range)
	elif aim != Vector2.ZERO:
		start = tilemap.world_to_map(aim)
	else:
		start = tilemap.world_to_map(player.global_position) + player.direction
	var limit: int = int(get_stat("mining_radius"))
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

## Returns the map-coordinate of the existing mineable tile that is within
## cast_range of the player and closest to the world-space aim position.
## Falls back to the tile in front of the player if none found.
func _find_nearest_tile_to_aim(player: Node, tilemap: Node, aim: Vector2, cast_range: float) -> Vector2i:
	# Use the tilemap helper if available — it already does this efficiently.
	if tilemap.has_method("get_nearest_mineable_tile"):
		var world_pos: Vector2 = tilemap.get_nearest_mineable_tile(aim, player.global_position, cast_range)
		if world_pos != Vector2.INF:
			return tilemap.world_to_map(world_pos)

	# Fallback: iterate tiles in a square around the player cast range.
	var map_center:   Vector2i = tilemap.world_to_map(player.global_position)
	var tile_size:    float    = 16.0
	var radius_tiles: int      = int(ceil(cast_range / tile_size))
	var best_d:       float    = INF
	var best:         Vector2i = tilemap.world_to_map(player.global_position) + player.direction
	for dx in range(-radius_tiles, radius_tiles + 1):
		for dy in range(-radius_tiles, radius_tiles + 1):
			var map_pos:   Vector2i = map_center + Vector2i(dx, dy)
			if not tilemap.tile_exists(map_pos):
				continue
			var world_pos: Vector2 = tilemap.map_to_world(map_pos)
			if player.global_position.distance_to(world_pos) > cast_range:
				continue
			var d: float = world_pos.distance_to(aim)
			if d < best_d:
				best_d = d
				best   = map_pos
	return best
