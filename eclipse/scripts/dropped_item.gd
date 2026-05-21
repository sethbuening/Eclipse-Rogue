# dropped_item.gd
extends Sprite2D

var item_type: Util.tile

var pos:   Vector2 = Vector2.ZERO  # simulation position, set by ItemManager after spawn
var vel:   Vector2 = Vector2.ZERO
var z:     float   = 0.0
var z_vel: float   = 0.0
const GRAVITY: float = 300.0
const BOUNCE:  float = 0.3
const RADIUS: float = 4.0  # half the sprite size in pixels

@export var item_sprites: Dictionary = {
	Util.tile.GOLD:      preload("res://art/items/gold_item.png"),
	Util.tile.COPPER:    preload("res://art/items/copper_item.png"),
	Util.tile.LIGHT_ORB: null,   # drawn procedurally below
}

func _ready() -> void:
	if item_type == Util.tile.LIGHT_ORB:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.set_pixel(0, 0, Color.WHITE)
		texture  = ImageTexture.create_from_image(img)
		scale    = Vector2(3.0, 3.0)
		modulate = Color(1.163, 1.627, 1.881, 1.0)
	elif item_sprites.has(item_type):
		texture = item_sprites[item_type]
