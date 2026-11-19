// Grass tufts and flowers: double-sided, lit like the ground, swaying more than trees.
shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/painterly.gdshaderinc"

uniform float sway_strength = 0.28;
uniform float sway_speed = 1.8;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float phase = o.x * 0.37 + o.z * 0.29;
	float gust = 0.55 + 0.45 * sin(TIME * 0.5 + o.x * 0.02 + o.z * 0.015);
	float w = max(VERTEX.y, 0.0);
	w = w * w * sway_strength * gust;
	VERTEX.x += sin(TIME * sway_speed + phase) * w;
	VERTEX.z += cos(TIME * sway_speed * 0.77 + phase) * w * 0.6;
}

void fragment() {
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float stroke;
	ALBEDO = brush(COLOR.rgb, wpos, vec3(0.0, 1.0, 0.0), stroke);
	paint_stroke = stroke;
	paint_sky = 1.0;   // never in caves
	ROUGHNESS = 1.0;
	BACKLIGHT = COLOR.rgb * 0.3;
}
