class_name LevelUpUpgrade
extends Resource

@export var display_name: String    = ""
@export var description:  String    = ""
@export var icon:         Texture2D = null
@export var rarity:       int       = 0  # Util.Rarity value; default COMMON

func apply(player: CharacterBody2D) -> void:
	pass

## Called every frame after the upgrade is applied.
## Override in subclasses that need to poll conditions.
func tick(delta: float, player: CharacterBody2D) -> void:
	pass
