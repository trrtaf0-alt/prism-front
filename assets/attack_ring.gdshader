shader_type canvas_item;
render_mode unshaded, blend_add;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	float radius = length(UV * 2.0 - 1.0);
	float dist = abs(radius - 0.984);
	float texel = max(0.00015, fwidth(radius) * 0.82);
	float core = 1.0 - smoothstep(max(0.0, 0.0026 - texel * 0.55), 0.0026 + texel * 0.55, dist);
	float halo = 1.0 - smoothstep(0.0015, 0.013, dist);
	COLOR = vec4(mix(tint.rgb, vec3(1.0), core * 0.23), tint.a * max(core * 0.95, halo * 0.49));
}
