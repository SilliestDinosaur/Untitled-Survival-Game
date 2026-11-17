// Screen-edge tint for damage / low health / underwater.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.6, 0.0, 0.0, 1.0);
uniform float intensity = 0.0;
uniform float softness = 0.55;

void fragment() {
	vec2 p = UV - 0.5;
	float v = smoothstep(0.75 - softness, 0.75, length(p) * 1.25);
	COLOR = vec4(tint.rgb, v * intensity * tint.a);
}
