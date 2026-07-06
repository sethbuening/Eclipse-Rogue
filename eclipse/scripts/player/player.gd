extends CharacterBody2D

# ================================================================== exports ==

@export_group("Procedural Animation")
@export var head_offset: Vector2 = Vector2(1, -28)
@export var body_offset: Vector2 = Vector2(1, -15)
@export var bob_amount:  float   = 2.5

@export_group("Orb Orbit")
@export var orb_orbit_center: Vector2 = Vector2(1, -15)
@export var orb_orbit_radius: float   = 24.0
@export var orb_orbit_speed:  float   = 1.25
@export var orb_reform_flash: float   = 0.2



@export var stats: PlayerStats = PlayerStats.new()


# ================================================================ constants ==

const FOCUS_BLOOM_MIN:      float = 0.0
const FOCUS_BLOOM_MAX:      float = 0.75
const FOCUS_GLOW_MIN:       float = 0.3
const FOCUS_GLOW_MAX:       float = 1.25
const FOCUS_DECAY:          float = 4.0

const MINE_PRESS_DELAY:     float = 0.05
const MINE_TICK_INTERVAL:   float = 1.0
const MINE_BOUNCE_AMOUNT:   float = 6.0
const MINE_BOUNCE_FALLOFF:  float = 0.85
const MINE_AOE_RADIUS:      int   = 2
# Bounce always runs for exactly this long; the cooldown is clamped to this
# minimum so the animation always finishes before the next strike.
const MINE_BOUNCE_DURATION: float = 0.3
const MINE_MIN_INTERVAL:    float = MINE_BOUNCE_DURATION


# ================================================================= textures ==

var head_up:    Texture2D = preload("res://art/player/head_up.png")
var head_right: Texture2D = preload("res://art/player/head_right.png")
var head_down:  Texture2D = preload("res://art/player/head_down.png")
var head_left:  Texture2D = preload("res://art/player/head_left.png")
var body_up:    Texture2D = preload("res://art/player/body_up.png")
var body_right: Texture2D = preload("res://art/player/body_right.png")
var body_down:  Texture2D = preload("res://art/player/body_down.png")
var body_left:  Texture2D = preload("res://art/player/body_left.png")


# ===================================================================== state ==

var time:             float = 0.0
var env_t:            float = 0.0
var movement_enabled: bool  = true
var _pause_consumed: bool = false

var _last_move_dir:    Vector2 = Vector2.RIGHT

@onready var _speed_scale: float = get_parent().scale.x

# ── passthrough properties (keep external scripts working unchanged) ───────────
var speed: float:
	get: return stats.speed
	set(v): stats.speed = v

var max_health: int:
	get: return stats.max_health
	set(v): stats.max_health = v

var armor: int:
	get: return stats.armor
	set(v): stats.armor = v

var dodge_chance: float:
	get: return stats.dodge_chance
	set(v): stats.dodge_chance = v

var guaranteed_crits: int:
	get: return stats.guaranteed_crits
	set(v): stats.guaranteed_crits = v

var mine_speed: float:
	get: return stats.mine_speed
	set(v): stats.mine_speed = v

var direction: Vector2i = Vector2i.DOWN:
	set(value):
		if direction == value:
			return
		direction = value
		match value:
			Vector2i.UP:    $head.texture = head_up;    $body.texture = body_up
			Vector2i.RIGHT: $head.texture = head_right; $body.texture = body_right
			Vector2i.DOWN:  $head.texture = head_down;  $body.texture = body_down
			Vector2i.LEFT:  $head.texture = head_left;  $body.texture = body_left


# ================================================================== health ==

@onready var xp_bar           = $"../HUD/xp"
@onready var health_bar       = $"../HUD/health progress"
@onready var _level_up_screen = $"../LevelUpScreen"

var health: int:
	set(value):
		health = clampi(value, 0, max_health)
		if health_bar:
			health_bar.set_health(float(health), float(max_health))
		if health <= 0:
			_on_died()

var xp: int = 0:
	set(value):
		xp = value
		if xp_bar:
			xp_bar.set_xp(xp)


func heal(amount: int) -> void:
	health += amount
	DamageNumbers.spawn_heal(global_position + Vector2(0, -28), amount)


# ================================================================= orb orbit ==

const ORB_READY_DELAY: float = 0.25

class OrbVisual:
	var sprite:        Sprite2D
	var shattered:     bool  = false
	var cooldown_age:  float = 0.0
	var cooldown:      float = 0.0
	var reform_flash:  float = 0.0
	var current_angle: float = 0.0
	var glow:          float = 0.0
	var glow_target:   float = 0.0
	var angle_offset:  float = 0.0
	var reforming:     bool  = false
	var ready_delay:   float = 0.0

var orb_visuals:      Array[OrbVisual] = []
var _orb_visual_map:  Dictionary       = {}
var orbit_time:       float            = 0.0
var orbit_speed_mult: float            = 1.0


# ============================================================ pending activations ==

class PendingActivation:
	var orb_index:     int
	var abilities:     Array[AbilityData]
	var stagger_timer: float = 0.0
	var any_activated: bool  = false

var _pending: Array[PendingActivation] = []

# ================================================================== mining ==

var _mine_press_timer: float    = 0.0
var _mine_target:      Vector2i = Vector2i(-1, -1)
var _mine_timer:       float    = 0.0

# ================================================================ level ups ==

static var _upgrade_pool:    Array                = []
var        acquired_upgrades: Array[LevelUpUpgrade] = []

func _get_upgrade_pool() -> Array:
	if _upgrade_pool.is_empty():
		_upgrade_pool = Util.load_resources("res://data/upgrades/")
	return _upgrade_pool

# ==================================================================== ready ==

func _ready() -> void:
	stats.speed *= _speed_scale
	health = max_health
	add_to_group("player")
	$RunInventory._player_stats = stats
	$RunInventory.relic_added.connect(_on_relic_added)
	var _starting_chain := AbilityLightningChain.new()
	$RunInventory.add_ability(_starting_chain)

	xp_bar.leveled_up.connect(_on_leveled_up)


# ================================================================== process ==

func _process(delta: float) -> void:
	time            += delta
	z_index          = %TilemapManager.get_z_for(global_position)
	movement_enabled = true

	$head.offset = head_offset + Vector2(0, round(bob_amount * sin(time * 2.0)))
	$body.offset = body_offset + Vector2(0, round(bob_amount * sin(time * 2.0 + 0.5)))

	_tick_abilities(delta)
	#_tick_basic_attacks(delta)
	_tick_relics(delta)
	_tick_upgrades(delta)
	_tick_env(delta)
	_tick_mining(delta)
	_tick_dev_input()


func _physics_process(delta: float) -> void:
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector != Vector2.ZERO:
		input_vector = input_vector.normalized()
	if movement_enabled:
		if input_vector != Vector2.ZERO:
			direction = Util.nearest_direction(input_vector)
		_last_move_dir = input_vector
		velocity = input_vector * speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()

	var new_target := Vector2i(-1, -1)
	var tilemap: Node = %TilemapManager
	if input_vector != Vector2.ZERO:
		for i in get_slide_collision_count():
			var col: KinematicCollision2D = get_slide_collision(i)
			var pushing: bool = input_vector.dot(-col.get_normal()) > 0.5
			if not pushing:
				continue
			var hit_world: Vector2 = col.get_position() - col.get_normal() * (tilemap.TILE_SIZE.x * 0.5)
			var candidate: Vector2i = tilemap.world_to_map(hit_world)
			if tilemap.tile_exists(candidate):
				new_target = candidate
				break

	if new_target != _mine_target:
		_mine_target      = new_target
		_mine_press_timer = MINE_PRESS_DELAY


# ================================================================== combat ==

func take_damage(amount: int, armor_penetration: int = 0, is_crit: bool = false, damage_type: Util.DamageType = Util.DamageType.PHYSICAL) -> void:
	if stats.dodge_chance > 0.0 and randf() < stats.dodge_chance:
		DamageNumbers.spawn_dodge(global_position + Vector2(0, -28))
		return
	var after_armor: int = amount - maxi(0, armor - armor_penetration)
	after_armor = maxi(1, after_armor)
	# damage_type is accepted and stored for future elemental resistance logic.
	DamageNumbers.spawn(global_position + Vector2(0, -28), after_armor, is_crit)
	health -= after_armor

func _on_died() -> void:
	Log("Player died.")


# ============================================================ basic attacks ==

'''func _tick_basic_attacks(delta: float) -> void:
	if basic_attacks.is_empty():
		return
	var ctx: Dictionary = {
		"player": self,
		"delta":  delta,
	}
	for attack: AbilityBasicAttack in basic_attacks:
		attack.tick(ctx)'''


# ================================================================ abilities ==

func _tick_abilities(delta: float) -> void:
	var ctx: Dictionary = {
		"player":        self,
		"tilemap":       %TilemapManager,
		"delta":         delta,
		"lock_movement": false,
		"orb_t":         0.0,
		"activated":     false,
		"orb_shattered": false,
		"orb_index":     0,
		"potency":       1.0,
	}
	for ability: AbilityData in $RunInventory.abilities:
		ability.tick(ctx)

	if ctx["lock_movement"]:
		movement_enabled = false


# ── context helpers ───────────────────────────────────────────────────────

func _update_body_glow(t: float) -> void:
	var glow: Color = Color(lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t), lerpf(1.0, 2.0, t))
	%body.self_modulate = glow if t > 0.0 else Color.WHITE
	%head.self_modulate = glow if t > 0.0 else Color.WHITE


# ============================================================= orb management ==

func _on_relic_added(relic: RelicData, _qty: int) -> void:
	relic.on_equip(self)

func _tick_relics(delta: float) -> void:
	for relic: RelicData in $RunInventory.relics:
		relic.tick(delta, self)


# ================================================================== mining ==

func _tick_mining(delta: float) -> void:
	var tilemap: Node = %TilemapManager

	# Tick the inter-strike cooldown.
	_mine_timer -= delta

	if _mine_target == Vector2i(-1, -1):
		_mine_press_timer = 0.0
		return

	if not tilemap.tile_exists(_mine_target):
		_mine_press_timer = 0.0
		_mine_target      = Vector2i(-1, -1)
		return

	_mine_press_timer += delta
	if _mine_press_timer < MINE_PRESS_DELAY:
		return

	if _mine_timer > 0.0:
		return

	# ── fire a mine strike ──────────────────────────────────────────────────
	var max_hp: int      = tilemap.get_tile_max_health(tilemap.tile_types.get(_mine_target, Util.tile.STONE))
	var cur_hp: int      = tilemap.tile_health.get(_mine_target, max_hp)
	var dmg_ratio: float = 1.0 - clampf(float(cur_hp - 6) / float(max_hp), 0.0, 1.0)
	var bounce_px: float = lerpf(MINE_BOUNCE_AMOUNT * 0.5, MINE_BOUNCE_AMOUNT, dmg_ratio)
	var dig_dir:   Vector2 = Vector2(direction)

	var world_pos: Vector2   = tilemap.map_to_world(_mine_target)
	var base_type: Util.tile = tilemap.tile_types.get(_mine_target, Util.tile.STONE)
	ParticleManager.spawn_mining_chunks(world_pos, base_type, dig_dir, 1.0)
	AudioManagerScene.create_2d_audio_at_location(world_pos, SoundEffect.SOUND_EFFECT_TYPE.TILE_MINE)

	# Bounce always runs for MINE_BOUNCE_DURATION; the cooldown is clamped to
	# that minimum so the animation always completes before the next strike.
	var interval: float = maxf(MINE_TICK_INTERVAL / mine_speed, MINE_MIN_INTERVAL)
	tilemap.bounce_tile(_mine_target, bounce_px, 0.0, MINE_BOUNCE_DURATION)
	tilemap.damage_tile(_mine_target, 3, false)

	for dx: int in range(-MINE_AOE_RADIUS, MINE_AOE_RADIUS + 1):
		for dy: int in range(-MINE_AOE_RADIUS, MINE_AOE_RADIUS + 1):
			if dx == 0 and dy == 0:
				continue
			var nb: Vector2i = _mine_target + Vector2i(dx, dy)
			if Vector2i(dx, dy).length() > MINE_AOE_RADIUS:
				continue
			var dist:  int   = absi(dx) + absi(dy)
			var delay: float = float(dist) * 0.06
			tilemap.bounce_tile(nb, bounce_px * MINE_BOUNCE_FALLOFF, delay, MINE_BOUNCE_DURATION)
			tilemap.damage_tile(nb, 2, false)
			if tilemap.tile_exists(nb):
				var nb_world:     Vector2   = tilemap.map_to_world(nb)
				var nb_type:      Util.tile = tilemap.tile_types.get(nb, Util.tile.STONE)
				var nb_intensity: float     = 0.5 / float(dist)
				ParticleManager.spawn_mining_chunks(nb_world, nb_type, dig_dir, nb_intensity)

	%Camera2D.shake(0.2)

	_mine_timer = interval

# =============================================================== environment ==

func _tick_env(delta: float) -> void:
	if env_t > 0.0:
		env_t = maxf(0.0, env_t - delta * FOCUS_DECAY)
		_set_env(env_t)

func _set_env(t: float) -> void:
	var env: Environment = %Environment.environment
	env.glow_bloom       = lerpf(FOCUS_BLOOM_MIN, FOCUS_BLOOM_MAX, t)
	env.glow_intensity   = lerpf(FOCUS_GLOW_MIN,  FOCUS_GLOW_MAX,  t)


# ================================================================ level ups ==

# ================================================================ level ups ==
# (replaces the existing level-up section in player.gd)
#
# How it works:
#   1. On level-up, collect every (orb, ability) pair where the ability
#      still has upgrade levels remaining (ability.can_upgrade()).
#   2. Shuffle the pool and take up to 3 unique pairs.
#   3. For each slot, roll a rarity using UpgradeRarityTable.roll(luck),
#      then build an AbilityLevelUpUpgrade from the pair.
#   4. Pass the three upgrades to LevelUpScreen as before.
#
# The old generic upgrade pool (_upgrade_pool / res://data/upgrades/) is
# kept as a fallback for non-ability upgrades (speed, health, etc.) that
# don't target a specific ability. Those still live in res://data/upgrades/.
# ---------------------------------------------------------------------------

var _pending_level_ups: int = 0

func _on_leveled_up() -> void:
	_pending_level_ups += 1
	xp_bar._display_value = 0.0
	xp_bar.value = 0.0
	xp_bar._target_value = 0.0
	if _pending_level_ups == 1:
		_show_next_upgrade_screen()

func _show_next_upgrade_screen() -> void:
	_pending_level_ups -= 1

	var choices: Array = _build_upgrade_choices()
	_level_up_screen.show_upgrades(self, choices)
	if not _level_up_screen.upgrade_chosen.is_connected(_on_upgrade_chosen):
		_level_up_screen.upgrade_chosen.connect(_on_upgrade_chosen)

## Build exactly 3 upgrade choices for the level-up screen.
##
## ORDERING GUARANTEE
##   Upgrades are strictly sequential: an ability at level N will only ever be
##   offered its level-(N+1) upgrade.  There is no skipping or out-of-order
##   offering.  The fallback that previously allowed unupgradeable abilities to
##   appear has been removed.
##
## ADD-ABILITY CHANCE
##   We count the total empty ability slots across all orbs and total capacity.
##   The fraction (empty / capacity) is the probability that any given choice
##   slot becomes an "add ability" upgrade instead of a "level up" upgrade.
##   Each of the 3 slots is rolled independently.
##
## LABELS
##   Both upgrade types include the orb display_name and 1-based slot index so
##   players can distinguish two orbs sharing the same ability, or one orb that
##   holds the same ability twice in different slots.
func _build_upgrade_choices() -> Array:
	const SLOT_COUNT: int = 3

	var pairs: Array = []
	for ability: AbilityData in $RunInventory.abilities:
		if ability.can_upgrade():
			pairs.append(ability)
	pairs.shuffle()

	var all_abilities: Array[AbilityData] = $RunInventory.abilities
	var add_tiers: Array = []
	if true:  # always offer a new ability slot
		var rarity: int = UpgradeRarityTable.roll(stats.luck)
		add_tiers = UpgradeAddAbility.build($RunInventory, all_abilities, rarity)

	var add_slot: int = randi() % SLOT_COUNT if not add_tiers.is_empty() else -1

	var choices: Array = []
	var used_abilities: Array = []
	var pair_cursor: int = 0

	for slot in range(SLOT_COUNT):
		if slot == add_slot:
			choices.append(add_tiers)
			continue
		while pair_cursor < pairs.size():
			var ability: AbilityData = pairs[pair_cursor]
			pair_cursor += 1
			if ability in used_abilities:
				continue
			var rarity: int = UpgradeRarityTable.roll(stats.luck)
			var tiers: Array = AbilityLevelUpUpgrade.build(ability, rarity)
			if not tiers.is_empty():
				choices.append(tiers)
				used_abilities.append(ability)
				break

	return choices

func _on_upgrade_chosen(upgrade: LevelUpUpgrade) -> void:
	acquired_upgrades.append(upgrade)
	if _pending_level_ups > 0:
		_show_next_upgrade_screen()
	else:
		_level_up_screen.upgrade_chosen.disconnect(_on_upgrade_chosen)





# =============================================================== relic screen ==

## Called by AncientContainer when the player interacts with it.
## Shows 3 relic choice cards (new relic or upgrade existing), then frees the container.
func show_relic_screen(container: Node) -> void:
	var choices: Array = _build_relic_choices()
	if choices.is_empty():
		container.queue_free()
		return
	_level_up_screen.show_upgrades(self, choices)
	var handler: Callable
	handler = func(upgrade: LevelUpUpgrade) -> void:
		acquired_upgrades.append(upgrade)
		if _level_up_screen.upgrade_chosen.is_connected(handler):
			_level_up_screen.upgrade_chosen.disconnect(handler)
		container.queue_free()
	_level_up_screen.upgrade_chosen.connect(handler)

## Build 3 relic upgrade choices.
##
## SLOT LOGIC
##   Each slot is either:
##     • An upgrade to an already-owned relic that can_upgrade() — weighted
##       by how many upgradeable relics are owned.
##     • A new relic from the item pool — offered when the inventory isn't full.
##
## At least one "new relic" slot is always guaranteed if the inventory has room.
## The remaining slots are upgrades (if any owned relics can be upgraded) or
## additional new-relic offers if no upgrades are available.
func _build_relic_choices() -> Array:
	const SLOT_COUNT: int = 3

	var upgradeable: Array[RelicData] = []
	for r: RelicData in $RunInventory.relics:
		if r.upgrade_levels.is_empty():
			DataLoader.apply_relic_data(r)
		if r.can_upgrade():
			upgradeable.append(r)
	upgradeable.shuffle()

	var inventory_full: bool = false
	if stats.relic_max > 0:
		var current_count: int = 0
		for r: RelicData in $RunInventory.relics:
			current_count += $RunInventory.relics[r]
		inventory_full = current_count >= stats.relic_max

	var new_relic_slots: int = 1 if not inventory_full else 0
	if upgradeable.is_empty():
		new_relic_slots = SLOT_COUNT if not inventory_full else 0

	var slot_types: Array = []
	for _i in range(SLOT_COUNT): slot_types.append(false)
	var positions: Array = range(SLOT_COUNT)
	positions.shuffle()
	for i in range(mini(new_relic_slots, SLOT_COUNT)):
		slot_types[positions[i]] = true

	var choices: Array = []
	var upgrade_cursor: int = 0
	var used_relics: Array = []

	for slot in range(SLOT_COUNT):
		var rarity: int = UpgradeRarityTable.roll(stats.luck)
		if slot_types[slot]:
			var tiers: Array = UpgradeAddRelic.build(self, rarity)
			if not tiers.is_empty():
				choices.append(tiers)
				continue

		while upgrade_cursor < upgradeable.size():
			var r: RelicData = upgradeable[upgrade_cursor]
			upgrade_cursor += 1
			if r in used_relics:
				continue
			var tiers: Array = RelicLevelUpUpgrade.build(r, rarity, $RunInventory)
			if not tiers.is_empty():
				choices.append(tiers)
				used_relics.append(r)
				break

	return choices


func _tick_upgrades(delta: float) -> void:
	# Tick each unique upgrade object once — acquired_upgrades may hold multiple
	# entries for the same relic/upgrade (one per level taken), but the object
	# itself should only fire once per frame regardless of how many times it
	# was upgraded. RelicData ticking is handled separately by _tick_relics.
	var seen: Array = []
	for upgrade: LevelUpUpgrade in acquired_upgrades:
		if upgrade in seen:
			continue
		seen.append(upgrade)
		upgrade.tick(delta, self)


# ================================================================= dev tools ==

func _tick_dev_input() -> void:
	if Input.is_action_just_pressed("pause") and not _pause_consumed:
		%PauseMenu.open()
	_pause_consumed = false
	if Input.is_action_just_pressed("dev_mode"):
		if $CollisionShape2D.disabled:
			speed /= 10.0
			$CollisionShape2D.disabled = false
			heal(100)
		else:
			speed *= 10.0
			$CollisionShape2D.disabled = true
			_dev_reset_cooldowns()
	if Input.is_action_just_pressed("dev_call_wave"):
		WaveManager.dev_trigger_swarm()
	if Input.is_action_just_pressed("dev_mode"):
		EnemyManager.debug_force_visible = not EnemyManager.debug_force_visible
	if Input.is_action_just_pressed("zoom_in"):
		%Camera2D.zoom *= 2
	if Input.is_action_just_pressed("zoom_out"):
		%Camera2D.zoom /= 2

func _dev_reset_cooldowns() -> void:
	for ov: OrbVisual in orb_visuals:
		ov.shattered    = false
		ov.cooldown_age = 0.0
		ov.cooldown     = 0.0
		ov.ready_delay  = 0.0
		ov.reform_flash = orb_reform_flash
		ov.reforming    = true
		ov.glow_target  = 0.0

# =================================================================== helpers ==

func Log(msg: Variant) -> void:
	print("[player.gd] " + str(msg))
