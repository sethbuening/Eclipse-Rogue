shader_type canvas_item;
uniform sampler2D atlas : source_color, filter_nearest;
uniform sampler2D distance_field : filter_nearest;
uniform vec2 sprite_size = vec2(32.0, 48.0);
uniform vec2 map_size = vec2(288.0, 288.0);
uniform vec2 map_world_origin = vec2(0.0, 0.0);
uniform float tile_world_size = 32.0;
uniform float max_depth = 4.0;
uniform float darkness_power = 2;
varying vec2 world_uv;
varying vec2 world_pos;
varying vec4 custom_data;
varying vec4 instance_color;

void vertex() {
    custom_data    = INSTANCE_CUSTOM;
    instance_color = COLOR;
    world_uv       = VERTEX;
    world_pos      = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    vec2 uv_origin  = custom_data.xy;
    vec2 uv_size    = custom_data.zw;
    vec2 local_uv   = (world_uv / sprite_size) + 0.5;
    vec2 atlas_uv   = uv_origin + local_uv * uv_size;
    vec4 tile_color = texture(atlas, atlas_uv) * vec4(instance_color.rgb, 1.0);
    if (darkness_power > 0.0) {
        vec2 texel      = 1.0 / map_size;
        vec2 tile_coord = (world_pos - map_world_origin + vec2(0.0, 16.0)) / tile_world_size;
        vec2 df_uv      = (floor(tile_coord) + 0.5) * texel;
        float darkness  = pow(texture(distance_field, df_uv).r, darkness_power);
        tile_color.rgb *= 1.0 - darkness;
    }
    COLOR = tile_color;
}