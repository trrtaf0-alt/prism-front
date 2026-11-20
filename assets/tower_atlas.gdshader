shader_type canvas_item;
render_mode unshaded;

uniform float frame_side = 128.0;
uniform float emission : hint_range(0.0, 1.0) = 0.0;

// The batch stores the atlas frame in its instance color's red channel.
varying flat vec2 atlas_offset;
varying flat float opacity;
varying flat float excitation;

void vertex() {
	float frame = floor(COLOR.r * 127.0 + 0.5);
	atlas_offset = vec2(mod(frame, 8.0), floor(frame / 8.0));
	opacity = COLOR.a;
	excitation = COLOR.g;
}

void fragment() {
	vec2 pixel = atlas_offset * frame_side + vec2(0.5) + UV * (frame_side - 1.0);
	vec4 paint = texture(TEXTURE, pixel * TEXTURE_PIXEL_SIZE);
	if (emission > 0.0) {
		float peak = max(max(paint.r, paint.g), paint.b);
		float valley = min(min(paint.r, paint.g), paint.b);
		float accents = smoothstep(0.49, 0.88, peak) * smoothstep(0.13, 0.40, peak - valley);
		float bright = max(accents, smoothstep(0.77, 0.98, valley) * 0.38);
		float power = emission * excitation * bright;
		paint.rgb = mix(min(vec3(1.0), paint.rgb * (1.0 + power * 0.50)), vec3(1.0), power * 0.16);
	}
	COLOR = vec4(paint.rgb, paint.a * opacity);
}
