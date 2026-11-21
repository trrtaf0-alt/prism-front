shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float white_core : hint_range(0.0, 1.0) = 0.6;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	float span = UV.y * 2.0 - 1.0;
	float across = abs(span);
	float edge = min(length(vec2(dFdx(span), dFdy(span))), 0.85);
	float core = 1.0 - smoothstep(max(0.04, 0.22 - edge * 0.16), 0.49 + edge * 0.30, across);
	float hot = 1.0 - smoothstep(0.03, 0.19 + edge * 0.17, across);
	float halo = 1.0 - smoothstep(0.08, 1.0, across);
	float alpha = max(core * 0.91, halo * 0.28);
	COLOR = vec4(mix(tint.rgb, vec3(1.0), hot * white_core), tint.a * alpha);
}
