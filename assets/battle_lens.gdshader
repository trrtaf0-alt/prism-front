shader_type canvas_item;
render_mode unshaded;

uniform sampler2D field_image : hint_screen_texture, filter_linear, repeat_disable;
uniform vec2 region_size;
uniform vec2 focus;
uniform vec2 sample_min;
uniform vec2 sample_max;
uniform float radius;
uniform float strength;
uniform float progress;

void fragment() {
	vec2 local = UV * region_size;
	vec2 axis = local - focus;
	float distance = length(axis);
	float r = distance / max(1.0, radius);
	float taper = smoothstep(0.035, 0.21, r) * (1.0 - smoothstep(0.72, 1.0, r));
	float ring = sin((r - (0.15 + progress * 0.88)) * 19.0);
	vec2 warped = clamp(local + axis / max(1.0, distance) * ring * strength * taper, sample_min, sample_max);
	vec2 uv_span = vec2(dFdx(SCREEN_UV.x) / dFdx(UV.x), dFdy(SCREEN_UV.y) / dFdy(UV.y));
	COLOR = textureLod(field_image, SCREEN_UV + (warped - local) / region_size * uv_span, 0.0);
}
