class_name AbilityData
extends Resource

@export var id:            String       = ""
@export var display_name:  String       = ""
@export var description:   String       = ""
@export var targeting_type: Util.TargetingType = Util.TargetingType.ENEMY_TILE
@export var stats:         AbilityStats = AbilityStats.new()

## Stats listed here are multiplied by orb_potency when accessed via get_stat().
@export var main_stats: Array[String] = []

var _orb_potency: float = 1.0

func get_stat(stat_name: String) -> float:
	return stats.get_stat(stat_name, _orb_potency, main_stats)

## Called every frame by the player for every ability, regardless of type.
## Subclasses fire whenever they find a valid target — no input gating.
## Write context["activated"] = true to trigger the orb shatter.
func tick(context: Dictionary) -> void:
	_orb_potency = context.get("potency", 1.0)

## Applies all stat-driven on-hit effects (knockback, stun, slow, DoT)
## to [target] on behalf of [player]. Call this from any ability after damage.
## [hit_origin] is the world position the hit came from for knockback direction;
## leave as default to use the player's position.
func apply_hit_effects(
		target:     Enemy,
		player:     CharacterBody2D,
		is_crit:    bool    = false,
		hit_origin: Vector2 = Vector2.INF
) -> void:
	var origin: Vector2 = player.global_position if hit_origin == Vector2.INF else hit_origin
	if get_stat("knockback") > 0.0:
		var dir: Vector2 = (target.global_position - origin).normalized()
		target.apply_knockback(dir * get_stat("knockback"))
	if get_stat("stun_duration") > 0.0:
		target.apply_stun(get_stat("stun_duration"))
	if get_stat("slow_amount") > 0.0 and get_stat("slow_duration") > 0.0:
		target.apply_slow(get_stat("slow_amount"), get_stat("slow_duration"))
	if get_stat("dot_damage") > 0.0 and get_stat("dot_duration") > 0.0:
		target.apply_dot(get_stat("dot_damage"), get_stat("dot_duration"))
