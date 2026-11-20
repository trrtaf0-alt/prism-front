shader_type canvas_item;
render_mode unshaded;

uniform float frame_side = 128.0;

// The batch stores the atlas frame in its instance color's red channel.
varying flat vec2 atlas_offset;
varying flat float opacity;

void vertex() {
	float frame = floor(COLOR.r * 127.0 + 0.5);
	atlas_offset = vec2(mod(frame, 8.0), floor(frame / 8.0));
	opacity = COLOR.a;
}

void fragment() {
	vec2 pixel = atlas_offset * frame_side + vec2(0.5) + UV * (frame_side - 1.0);
	vec4 paint = texture(TEXTURE, pixel * TEXTURE_PIXEL_SIZE);
	COLOR = vec4(paint.rgb, paint.a * opacity);
}
