// bar_glint.gdshader
// Additive overlay for health / xp bars — applied to a full-size ColorRect
// child that sits on top of the bar fill. The shader clips itself to fill_ratio
// so the streak never overruns empty space.
//
// Uniforms driven from GDScript each frame:
//   glint_phase  – 0→1 during a sweep, 0 at rest
//   fill_ratio   – filled fraction of the bar (0..1)
// Set once at startup:
//   glint_color  – streak tint; alpha = peak opacity
//   streak_width – normalised half-width in UV space
//   skew         – diagonal lean (UV units per UV.y)

shader_type canvas_item;
render_mode blend_add;

uniform float glint_phase  : hint_range(0.0, 1.0) = 0.0;
uniform float fill_ratio   : hint_range(0.0, 1.0) = 1.0;
uniform vec4  glint_color  : source_color          = vec4(1.0, 1.0, 1.0, 0.38);
uniform float streak_width : hint_range(0.01, 0.3) = 0.07;
uniform float skew                                 = 0.18;

void fragment() {
    // Outside the filled region — emit nothing
    if (UV.x > fill_ratio) {
        COLOR = vec4(0.0);
    }
	else {
	    // Centre of the streak sweeps across UV space
	    float centre = mix(-streak_width, 1.0 + streak_width, glint_phase);
	    float x      = UV.x - UV.y * skew;
	    float dist   = abs(x - centre);
	    float streak = 1.0 - smoothstep(0.0, streak_width, dist);

	    // Fade in/out at sweep edges so it never pops
	    float env   = smoothstep(0.0, 0.15, glint_phase) * smoothstep(1.0, 0.85, glint_phase);
	    float alpha = streak * env * glint_color.a;
	    COLOR = vec4(glint_color.rgb * alpha, alpha);
	}
}
