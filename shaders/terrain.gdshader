// Ground: vertex colors from the biome map, painted with brush strokes.
shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/painterly.gdshaderinc"

void fragment() {
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float stroke;
	ALBEDO = brush(COLOR.rgb, wpos, wn, stroke);
	paint_stroke = stroke;
	paint_sky = COLOR.a;   // baked per vertex: cave walls see little sky
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.0;
	ROUGHNESS = 1.0;
}
