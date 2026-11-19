// A building piece part-way built: the painted look (as painted.gdshader) up to the build line, nothing above it.
// Only pieces being built use it (the discard costs a little), so finished pieces don't pay for it.
shader_type spatial;
render_mode cull_back;
#include "res://shaders/painterly.gdshaderinc"

uniform float rim_amount = 0.15;
uniform vec4 tint_color : source_color = vec4(1.0);
instance uniform float sky_seen : hint_range(0.0, 1.0) = 1.0;
instance uniform float build_cut = 1000.0;   // the build line, in the piece's own height

varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	if (local_y > build_cut) {
		discard;
	}
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float stroke;
	ALBEDO = pool_edges(brush(COLOR.rgb * tint_color.rgb, wpos, wn, stroke), NORMAL, VIEW);
	paint_stroke = stroke;
	paint_sky = sky_seen;
	AO = sky_seen;
	AO_LIGHT_AFFECT = 0.0;
	ROUGHNESS = 1.0;
	RIM = rim_amount;
	RIM_TINT = 0.6;
}
