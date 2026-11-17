// Trees and bushes: vertex-colored, flat-shaded, gently swaying in the wind.
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform float sway_strength = 0.022;
uniform float sway_start = 1.5;
uniform float sway_speed = 1.1;
uniform float backlight = 0.3;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float phase = o.x * 0.13 + o.z * 0.17;
	float gust = 0.6 + 0.4 * sin(TIME * 0.35 + o.x * 0.004 + o.z * 0.003);
	float w = max(VERTEX.y - sway_start, 0.0) * sway_strength * gust;
	VERTEX.x += sin(TIME * sway_speed + phase) * w;
	VERTEX.z += cos(TIME * sway_speed * 0.83 + phase * 1.3) * w * 0.7;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	BACKLIGHT = COLOR.rgb * backlight;
}
