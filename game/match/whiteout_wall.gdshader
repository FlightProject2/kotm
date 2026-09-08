shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 tint : source_color = vec4(0.75, 0.86, 0.94, 0.57);

void fragment() {
	float broad = sin(UV.x * 92.0 + UV.y * 17.0 - TIME * 0.45);
	float drift = sin(UV.x * 221.0 - UV.y * 53.0 + TIME * 0.85);
	float gust = broad * 0.5 + drift * 0.25 + 0.25;
	float edge = smoothstep(0.0, 0.16, UV.y) * (1.0 - smoothstep(0.84, 1.0, UV.y));
	ALBEDO = mix(tint.rgb * 0.82, vec3(0.94, 0.97, 1.0), gust * 0.35 + 0.35);
	ALPHA = tint.a * (0.72 + gust * 0.2) * edge;
}
