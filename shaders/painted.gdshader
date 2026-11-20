// Generic painted object (rocks, creatures, held items).
shader_type spatial;
render_mode cull_back;
#include "res://shaders/painterly.gdshaderinc"

uniform float rim_amount = 0.15;
uniform vec4 tint_color : source_color = vec4(1.0);
instance uniform float sky_seen : hint_range(0.0, 1.0) = 1.0;   // set on things in caves (see CaveShade)

void fragment() {
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float stroke;
	ALBEDO = pool_edges(brush(COLOR.rgb * tint_color.rgb, wpos, wn, stroke), NORMAL, VIEW);
	paint_stroke = stroke;
	// Things drawn many to a MultiMesh (cave ore, stalagmites) carry their sky in the instance colour's alpha.
	paint_sky = min(sky_seen, COLOR.a);
	AO = paint_sky;
	AO_LIGHT_AFFECT = 0.0;
	ROUGHNESS = 1.0;
	RIM = rim_amount;
	RIM_TINT = 0.6;
}
