shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float white_core : hint_range(0.0, 1.0) = 0.6;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float edge = min(fwidth(across), 0.65);
	float core = 1.0 - smoothstep(0.22, 0.49 + edge * 0.22, across);
	float hot = 1.0 - smoothstep(0.03, 0.19 + edge * 0.17, across);
	float halo = 1.0 - smoothstep(0.08, 1.0, across);
	float alpha = max(core * 0.91, halo * 0.28);
	COLOR = vec4(mix(tint.rgb, vec3(1.0), hot * white_core), tint.a * alpha);
}
