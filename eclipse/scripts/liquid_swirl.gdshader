shader_type canvas_item;
uniform int   frame_count  = 4;
uniform float fps          = 6.0;

void fragment() {
    int   frame  = int(TIME * fps) % frame_count;
    vec2  uv     = UV;
    uv.x         = (uv.x + float(frame)) / float(frame_count);
    COLOR         = texture(TEXTURE, uv);
}