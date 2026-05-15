# ability_light_shield.gd
class_name AbilityLightShield
extends AbilityData

func activate(context: Dictionary) -> void:
	var player: Node = context.get("player")
	if player == null:
		return
	var incoming: float = context.get("damage", 0.0)
	var absorbed: float = minf(incoming, stats.damage_absorb)
	context["damage"]   = incoming - absorbed
	if stats.shield_amount > 0.0:
		context["shield_granted"] = context.get("shield_granted", 0.0) + stats.shield_amount
