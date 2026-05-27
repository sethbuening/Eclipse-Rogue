shader_type canvas_item;
uniform int   frame_count = 4;
uniform float fps         = 8.0;
uniform float fill_ratio  = 1.0;  // 1.0 = full, 0.0 = empty

void fragment() {
    if (UV.y < 1.0 - fill_ratio) {
        discard;
    }
    int  frame = int(TIME * fps) % frame_count;
    // remap UV.y so the texture always shows from its own bottom,
    // rather than showing a bottom-slice of a full-height sample
    vec2 uv = UV;
    uv.y    = 1.0 - (1.0 - UV.y) / max(fill_ratio, 0.001);
    uv.x    = (uv.x + float(frame)) / float(frame_count);
    COLOR   = texture(TEXTURE, uv);
}