# dropped_item.gd
class_name DroppedItem
extends Sprite2D

enum DropType { LIGHT_ORB, METAL }

var drop_type: DropType = DropType.LIGHT_ORB
var metal:     MetalData = null   # only used when drop_type == METAL

var pos:   Vector2 = Vector2.ZERO
var vel:   Vector2 = Vector2.ZERO
var z:     float   = 0.0
var z_vel: float   = 0.0
const GRAVITY: float = 300.0
const BOUNCE:  float = 0.3
const RADIUS:  float = 4.0

func _ready() -> void:
	match drop_type:
		DropType.LIGHT_ORB:
			var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
			img.set_pixel(0, 0, Color.WHITE)
			texture  = ImageTexture.create_from_image(img)
			scale    = Vector2(3.0, 3.0)
			modulate = Color(1.163, 1.627, 1.881, 1.0)
		DropType.METAL:
			if metal != null and metal.sprite_texture != null:
				texture = metal.sprite_texture
