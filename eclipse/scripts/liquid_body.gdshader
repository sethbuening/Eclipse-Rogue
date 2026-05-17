shader_type canvas_item;
uniform int   frame_count = 4;
uniform float fps         = 8.0;
uniform float fill_ratio  = 1.0;  // 1.0 = full, 0.0 = empty

void fragment() {
    // discard pixels above the fill line
    if (UV.y < 1.0 - fill_ratio) {
        discard;
    }
    int  frame = int(TIME * fps) % frame_count;
    vec2 uv    = UV;
    uv.x       = (uv.x + float(frame)) / float(frame_count);
    COLOR      = texture(TEXTURE, uv);
}