## Targeting.gd
## Autoload singleton — add as "Targeting" in Project > Autoloads.
##
## All targeting logic lives here.  Abilities never read mouse position or
## joystick axes; they call one of the static helpers below and receive a
## ready-to-use TargetingResult.
##
## Vampire-Survivors style: the player never aims.  Each helper automatically
## picks the best enemy / tile relative to the player's world position.

extends Node

class_name _Targeting   # underscore keeps it off the global class list


# ══════════════════════════════════════════════════════════════ public API ══


## Nearest single enemy within range.
## Returns a TargetingResult with found=true when an enemy exists.
static func nearest_enemy(
		player:  Node2D,
		range:   float
) -> Util.TargetingResult:
	var r := Util.TargetingResult.new()
	var enemy: Node2D = _nearest_enemy_to(player.global_position, range)
	if enemy:
		r.position = enemy.global_position
		r.targets  = [enemy]
		r.found    = true
	return r


## Nearest enemy, falling back to nearest mineable tile when no enemy is in range.
static func nearest_enemy_or_tile(
		player:  Node2D,
		tilemap: Node,
		range:   float
) -> Util.TargetingResult:
	var r := Util.TargetingResult.new()
	var enemy: Node2D = _nearest_enemy_to(player.global_position, range)
	if enemy:
		r.position = enemy.global_position
		r.targets  = [enemy]
		r.found    = true
	else:
		var tile: Vector2 = _nearest_tile(tilemap, player.global_position, range)
		if tile != Vector2.INF:
			r.position = tile
			r.is_tile  = true
			r.found    = true
	return r


## Nearest ConductorPost, falling back to enemy, then mineable tile.
static func nearest_post_enemy_or_tile(
		player:  Node2D,
		tilemap: Node,
		range:   float
) -> Util.TargetingResult:
	var r := Util.TargetingResult.new()
	var target: Node2D = _nearest_enemy_or_post(player.global_position, range)
	if target:
		r.position = target.global_position
		r.targets  = [target]
		r.found    = true
	else:
		var tile: Vector2 = _nearest_tile(tilemap, player.global_position, range)
		if tile != Vector2.INF:
			r.position = tile
			r.is_tile  = true
			r.found    = true
	return r


## Nearest mineable tile only (no enemy targeting).
static func nearest_tile(
		player:  Node2D,
		tilemap: Node,
		range:   float
) -> Util.TargetingResult:
	var r := Util.TargetingResult.new()
	var tile: Vector2 = _nearest_tile(tilemap, player.global_position, range)
	if tile != Vector2.INF:
		r.position = tile
		r.is_tile  = true
		r.found    = true
	return r


## Spawn at the player's own position (conductor-post style placement).
## Picks a clear air-tile location nearest to the player.
static func at_player(
		player:  Node2D,
		_tilemap: Node = null
) -> Util.TargetingResult:
	var r := Util.TargetingResult.new()
	r.position = player.global_position
	r.found    = true
	return r


## Dash direction: movement input direction, falling back to facing direction.
## Returns a normalised Vector2 (not a full TargetingResult) for simplicity.
static func dash_direction(player: Node2D) -> Vector2:
	var move: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if move.length() > 0.2:
		return move.normalized()
	return Vector2(player.direction)


## Collect up to max_count enemies within radius of origin, sorted nearest-first.
static func enemies_in_radius(
		origin: Vector2,
		radius: float,
		max_count: int = 99,
		exclude: Array[Node2D] = []
) -> Array[Node2D]:
	var results: Array[Node2D] = []
	var r2: float = radius * radius
	for enemy: Enemy in EnemyManager.living_enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy in exclude:
			continue
		if origin.distance_squared_to(enemy.global_position) <= r2:
			results.append(enemy)
		if results.size() >= max_count:
			break
	results.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position)
	)
	return results


## First target for a new lightning chain.
## Prefers a ConductorPost over an enemy when the post is closer AND has at
## least one enemy within hop_radius of it (so routing through it is useful).
## Falls back to the nearest enemy directly when no qualifying post exists.
static func nearest_chain_first_target(
		origin:     Vector2,
		range:      float,
		hop_radius: float
) -> Node2D:
	var nearest_enemy: Node2D = _nearest_enemy_to(origin, range)
	var nearest_post:  Node2D = _nearest_conductor_post(origin, range)

	# No post in range — just use the nearest enemy.
	if nearest_post == null:
		return nearest_enemy

	# Post is in range: only prefer it if it's closer than the enemy AND has
	# at least one enemy within hop_radius (otherwise it's a dead-end).
	var post_d2:  float = origin.distance_squared_to(nearest_post.global_position)
	var enemy_d2: float = INF if nearest_enemy == null 			else origin.distance_squared_to(nearest_enemy.global_position)

	if post_d2 < enemy_d2:
		for enemy: Enemy in EnemyManager.living_enemies:
			if not is_instance_valid(enemy):
				continue
			if nearest_post.global_position.distance_squared_to(enemy.global_position) <= hop_radius * hop_radius:
				return nearest_post  # post wins: closer and has a reachable enemy

	# Enemy is closer, or post has no reachable enemies nearby.
	return nearest_enemy


## Nearest enemy or ConductorPost for chain-hop logic (used by LightningChain).
## Excludes already-hit nodes.  Posts are preferred over enemies mid-chain
## because they amplify subsequent hops.
static func nearest_chain_target(
		origin:  Vector2,
		radius:  float,
		exclude: Array[Node2D]
) -> Node:
	var best_d: float  = radius * radius
	var best:   Node = null

	for post: ConductorPost in ConductorPost.all_posts:
		if not is_instance_valid(post) or post in exclude:
			continue
		var d2: float = origin.distance_squared_to(post.global_position)
		if d2 <= best_d:
			best_d = d2
			best   = post

	if best != null:
		return best  # posts beat enemies mid-chain

	for enemy: Enemy in EnemyManager.living_enemies:
		if not is_instance_valid(enemy) or enemy in exclude:
			continue
		var d2: float = origin.distance_squared_to(enemy.global_position)
		if d2 <= best_d:
			best_d = d2
			best   = enemy

	return best


# ══════════════════════════════════════════════════════════ private helpers ══


static func _nearest_enemy_to(origin: Vector2, range: float) -> Node2D:
	var best_d: float  = range * range
	var best:   Node = null
	for enemy: Enemy in EnemyManager.living_enemies:
		if not is_instance_valid(enemy):
			continue
		var d2: float = origin.distance_squared_to(enemy.global_position)
		if d2 < best_d:
			best_d = d2
			best   = enemy
	return best


static func _nearest_conductor_post(origin: Vector2, range: float) -> Node2D:
	var best_d: float  = range * range
	var best:   Node2D = null
	for post: ConductorPost in ConductorPost.all_posts:
		if not is_instance_valid(post):
			continue
		var d2: float = origin.distance_squared_to(post.global_position)
		if d2 < best_d:
			best_d = d2
			best   = post
	return best


static func _nearest_enemy_or_post(origin: Vector2, range: float) -> Node2D:
	# Enemies have priority over conductor posts.
	var enemy: Node2D = _nearest_enemy_to(origin, range)
	if enemy:
		return enemy
	return _nearest_conductor_post(origin, range)


static func _nearest_tile(tilemap: Node, origin: Vector2, range: float) -> Vector2:
	if tilemap == null or not tilemap.has_method("get_nearest_mineable_tile"):
		return Vector2.INF
	# Pass origin as both the "aim" and the "from" so the tile search radiates
	# outward from the player — no cursor involved.
	return tilemap.get_nearest_mineable_tile(origin, origin, range)
