shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float rim = smoothstep(0.22, 0.68, length(p));
	float ice = sin(UV.x * 78.0 + UV.y * 36.0) * sin(UV.y * 61.0 - UV.x * 24.0);
	float alpha = strength * (0.09 + rim * (0.35 + ice * 0.04));
	COLOR = vec4(0.8, 0.91, 0.98, alpha);
}
