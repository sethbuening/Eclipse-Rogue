// bar_aura.gdshader
// Feathered glow drawn on a ColorRect behind the XP/health bar.
// UV (0,0) = top-left of the rect, (1,1) = bottom-right.
// The rect should be larger than the bar on all sides (overhang controlled
// in GDScript). The shader remaps UV so (0.5, 0.5) = bar centre, then
// applies separate falloffs on X and Y so the glow bleeds further sideways
// than vertically.
//
// Uniforms:
//   aura_color   – base color (driven from GDScript to match bar fill color)
//   alpha        – peak centre alpha (driven each frame)
//   falloff_x    – how sharply the glow fades horizontally (higher = faster)
//   falloff_y    – how sharply the glow fades vertically   (higher = faster)

shader_type canvas_item;
render_mode blend_add;

uniform vec4  aura_color : source_color = vec4(0.0, 0.4, 1.0, 1.0);
uniform float alpha      : hint_range(0.0, 1.0) = 0.15;
uniform float falloff_x  : hint_range(0.5, 20.0) = 2.5;
uniform float falloff_y  : hint_range(0.5, 20.0) = 6.0;

void fragment() {
	// Remap UV so centre = (0, 0), edges = ±1
	vec2 uv = UV * 2.0 - 1.0;

	// Separate power falloffs — Y falls off harder (shorter reach vertically)
	float gx = 1.0 - pow(abs(uv.x), falloff_x);
	float gy = 1.0 - pow(abs(uv.y), falloff_y);
	float glow = clamp(gx, 0.0, 1.0) * clamp(gy, 0.0, 1.0);

	float a = glow * alpha;
	COLOR = vec4(aura_color.rgb * a, a);
}
