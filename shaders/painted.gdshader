// Generic painted object (rocks, creatures, held items).
shader_type spatial;
render_mode cull_back;
#include "res://shaders/painterly.gdshaderinc"

uniform float rim_amount = 0.15;

void fragment() {
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float stroke;
	ALBEDO = pool_edges(brush(COLOR.rgb, wpos, wn, stroke), NORMAL, VIEW);
	paint_stroke = stroke;
	ROUGHNESS = 1.0;
	RIM = rim_amount;
	RIM_TINT = 0.6;
}
