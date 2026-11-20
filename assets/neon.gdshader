shader_type canvas_item;
render_mode unshaded;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	vec3 color = tint.rgb * mask.r;
	color = mix(color, vec3(1.0), smoothstep(0.76, 1.05, mask.r));
	COLOR = vec4(color, mask.a * tint.a);
}
