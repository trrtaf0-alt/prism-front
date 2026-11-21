shader_type canvas_item;
render_mode unshaded, blend_add;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	float radius = length(UV * 2.0 - 1.0);
	float dist = abs(radius - 0.984);
	// Use the local screen derivative to keep large rings from gaining stroke weight.
	float pixel = max(length(vec2(dFdx(radius), dFdy(radius))), 0.00015);
	float core_width = min(0.0026, pixel * 0.78);
	float halo_width = min(0.013, pixel * 2.7);
	float aa = pixel * 0.48;
	float core = 1.0 - smoothstep(max(0.0, core_width - aa), core_width + aa, dist);
	float halo = 1.0 - smoothstep(core_width, halo_width + aa, dist);
	COLOR = vec4(mix(tint.rgb, vec3(1.0), core * 0.23), tint.a * max(core * 0.95, halo * 0.32));
}
