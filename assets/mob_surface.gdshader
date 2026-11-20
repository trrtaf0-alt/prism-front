shader_type canvas_item;
render_mode unshaded;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	float surface = mask.r;
	vec3 armor = mix(vec3(0.035, 0.055, 0.080), tint.rgb * 0.58, smoothstep(0.13, 0.66, surface));
	float emitter = smoothstep(0.63, 0.91, surface);
	vec3 glow = mix(tint.rgb, vec3(1.0), smoothstep(0.82, 1.0, surface) * 0.60);
	COLOR = vec4(mix(armor, glow, emitter), mask.a * tint.a);
}
