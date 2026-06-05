shader_type canvas_item;

uniform vec4  color   : source_color = vec4(0.05, 0.05, 0.15, 0.7);
uniform float falloff : hint_range(0.5, 8.0) = 1.8;

void fragment() {
	// UV is 0→1 across the rect; remap to -1→1 so centre = (0,0)
	vec2 uv = UV * 2.0 - 1.0;

	// Per-axis fade: 1 at centre, 0 at edges
	float fx = 1.0 - abs(uv.x);
	float fy = 1.0 - abs(uv.y);

	// Multiply axes and apply power curve
	float alpha = pow(fx * fy, falloff);

	COLOR = vec4(color.rgb, color.a * alpha);
}
