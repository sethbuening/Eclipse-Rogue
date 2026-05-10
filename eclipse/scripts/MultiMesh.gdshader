shader_type canvas_item;
uniform sampler2D atlas : source_color, filter_nearest;
uniform float tile_size = 32.0;
varying vec2 world_uv;
varying vec4 custom_data;
varying vec4 instance_color;

void vertex() {
    custom_data   = INSTANCE_CUSTOM;
    instance_color = COLOR;
    world_uv      = VERTEX;
}

void fragment() {
    vec2 uv_origin = custom_data.xy;
    vec2 uv_size   = custom_data.zw;
    vec2 local_uv  = (world_uv / tile_size) + 0.5;
    vec2 atlas_uv  = uv_origin + local_uv * uv_size;
    COLOR = texture(atlas, atlas_uv) * instance_color;
}