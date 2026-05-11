shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D atlas      : filter_nearest, repeat_disable;
uniform vec2      sprite_size;

uniform sampler2D voronoi_seeds_tex : filter_nearest, repeat_disable;
uniform sampler2D voronoi_tints_tex : filter_nearest, repeat_disable;
uniform int       voronoi_seed_count;
uniform int       voronoi_cols;
uniform int       voronoi_rows;
uniform float     voronoi_seed_spacing;

uniform float voronoi_edge_darkness;
uniform float voronoi_edge_sharpness;
uniform float voronoi_tint_strength;
uniform float voronoi_boundary_neutral;
uniform float voronoi_boundary_amplitude;
uniform float voronoi_boundary_contrast;

const float TOP_FACE_FRAC = 0.6667;
const float SEAM_WIDTH    = 0.021;
const float AO_STRENGTH   = 0.30;

// Directional light direction (top-left = normalize(-1, -1))
const vec2  LIGHT_DIR     = vec2(-0.7071, -0.7071);
const float LIGHT_STR     = 0.30;
const float AMBIENT       = 0.70;

// Crack parameters
const float CRACK_SCALE   = 6.0;   // frequency of noise cracks
const float CRACK_THRESH  = 0.85;  // how much of noise range becomes crack
const float CRACK_DARK    = 0.45;  // how dark the crack gets

varying flat vec4 v_custom;
varying      vec2 v_uv;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_uv     = UV;
}

void voronoi_query(vec2 p, out float f1, out float f2, out int nearest) {
	f1      = 1e9;
	f2      = 1e9;
	nearest = 0;
	int cc = int(p.x / voronoi_seed_spacing);
	int cr = int(p.y / voronoi_seed_spacing);
	for (int dr = -2; dr <= 2; dr++) {
		for (int dc = -2; dc <= 2; dc++) {
			int nc = cc + dc;
			int nr = cr + dr;
			if (nc < 0 || nc >= voronoi_cols || nr < 0 || nr >= voronoi_rows)
				continue;
			int si = nr * voronoi_cols + nc;
			if (si < 0 || si >= voronoi_seed_count)
				continue;
			vec4  sd = texelFetch(voronoi_seeds_tex, ivec2(si, 0), 0);
			vec2  d  = p - sd.rg;
			float d2 = dot(d, d);
			if (d2 < f1) { f2 = f1; f1 = d2; nearest = si; }
			else if (d2 < f2) { f2 = d2; }
		}
	}
	f1 = sqrt(f1);
	f2 = sqrt(f2);
}

// Simple hash-based value noise, pixelated — snaps input to integer coords
// so result is constant per pixel cell
float hash(vec2 p) {
	p = floor(p);
	float h = dot(p, vec2(127.1, 311.7));
	return fract(sin(h) * 43758.5453);
}

// Smooth value noise by bilinear mixing of hashed corners
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// smoothstep
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i + vec2(0.0, 0.0));
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Crack noise: layered, snapped to pixel grid
float crack_noise(vec2 world_px) {
	// snap to pixel grid so cracks are pixel-crisp
	vec2 p = floor(world_px * CRACK_SCALE) / CRACK_SCALE;
	// two octaves for more organic feel
	float n = vnoise(p * CRACK_SCALE) * 0.6
	        + vnoise(p * CRACK_SCALE * 2.1 + vec2(5.7, 3.3)) * 0.4;
	return n;
}

void fragment() {
	// Snap to pixel grid first
	vec2 suv = (floor(v_uv * sprite_size) + 0.5) / sprite_size;

	// Tile centre for per-tile Voronoi (tint, boundary height)
	vec2 tile_centre = vec2(v_custom.b + 0.5, v_custom.a + 0.5);

	// Per-pixel world position for seam lines and cracks
	vec2 pixel_world = vec2(
		v_custom.b + suv.x,
		v_custom.a + suv.y * 1.5
	);

	vec2 atlas_uv_origin = v_custom.rg;
	bool is_ore = (atlas_uv_origin.x > 0.3);

	// ---- Per-tile Voronoi (tint + boundary) --------------------------------
	float tf1; float tf2; int t_nearest;
	voronoi_query(tile_centre, tf1, tf2, t_nearest);

	vec3 tint = vec3(1.0);
	if (!is_ore && t_nearest < voronoi_seed_count) {
		vec3 region_tint = texelFetch(voronoi_tints_tex, ivec2(t_nearest, 0), 0).rgb;
		tint = mix(vec3(1.0), region_tint, voronoi_tint_strength);
	}

	// ---- Per-pixel Voronoi (seam darkness) ---------------------------------
	float pf1; float pf2; int p_nearest;
	voronoi_query(pixel_world, pf1, pf2, p_nearest);

	// seam factor: 1 at seam, 0 at cell centre
	float seam_factor = clamp(1.0 - (pf2 - pf1) / max(pf2, 0.001), 0.0, 1.0);
	float seam_dark   = pow(seam_factor, voronoi_edge_sharpness);

	// ---- Directional light from top-left -----------------------------------
	// Approximate surface normal from Voronoi gradient:
	// sample f1 at small offsets to get gradient direction
	float eps = 0.5;
	float f1_r; float f1_u; float f2_tmp; int n_tmp;
	voronoi_query(pixel_world + vec2(eps, 0.0),  f1_r, f2_tmp, n_tmp);
	voronoi_query(pixel_world + vec2(0.0, eps),  f1_u, f2_tmp, n_tmp);
	vec2 grad      = vec2(f1_r - pf1, f1_u - pf1) / eps;
	// treat grad as XY of surface normal, Z = 1, then normalise
	vec3 normal    = normalize(vec3(grad, 1.0));
	vec3 light3    = normalize(vec3(LIGHT_DIR, 1.0));
	float diffuse  = clamp(dot(normal, light3), 0.0, 1.0);
	float lighting = AMBIENT + diffuse * LIGHT_STR;

	// ---- Noise-based cracks ------------------------------------------------
	float cn        = crack_noise(pixel_world);
	// cracks appear where noise exceeds threshold
	float crack_amt = smoothstep(CRACK_THRESH, 1.0, cn);
	float crack_mul = mix(1.0, CRACK_DARK, crack_amt);

	// ---- Face-split boundary -----------------------------------------------
	float blend = clamp((tf1 / max(tf1 + tf2, 0.001)) * 2.0, 0.0, 1.0);
	blend = pow(blend, voronoi_boundary_contrast);
	float h = 0.0;
	if (t_nearest < voronoi_seed_count) {
		h = texelFetch(voronoi_seeds_tex, ivec2(t_nearest, 0), 0).b;
	}
	float boundary  = voronoi_boundary_neutral + h * voronoi_boundary_amplitude;
	float seam_y_uv = clamp(mix(boundary, voronoi_boundary_neutral, blend), 0.05, 0.95)
	                  * TOP_FACE_FRAC;

	vec2 sprite_uv;
	bool is_top_face;
	if (suv.y < seam_y_uv - SEAM_WIDTH * 0.5) {
		is_top_face = true;
		float t     = suv.y / max(seam_y_uv, 0.001);
		sprite_uv   = vec2(suv.x, t * TOP_FACE_FRAC);
	} else if (suv.y > seam_y_uv + SEAM_WIDTH * 0.5) {
		is_top_face = false;
		float t     = (suv.y - seam_y_uv) / max(1.0 - seam_y_uv, 0.001);
		sprite_uv   = vec2(suv.x, TOP_FACE_FRAC + t * (1.0 - TOP_FACE_FRAC));
	} else {
		is_top_face = false;
		sprite_uv   = vec2(suv.x, TOP_FACE_FRAC);
	}

	vec2 atlas_size = vec2(textureSize(atlas, 0));
	vec2 uv_scale   = sprite_size / atlas_size;
	vec2 final_uv   = atlas_uv_origin + sprite_uv * uv_scale;

	vec4 col = texture(atlas, final_uv);

	// Front face AO
	if (!is_top_face) {
		float ao_t = (suv.y - seam_y_uv) / max(1.0 - seam_y_uv, 0.001);
		col.rgb   *= 1.0 - ao_t * AO_STRENGTH;
	}

	// Apply all shading
	col.rgb *= tint;
	col.rgb *= lighting;
	col.rgb *= mix(1.0, voronoi_edge_darkness, seam_dark);
	col.rgb *= crack_mul;
	col     *= COLOR;

	COLOR = col;
}