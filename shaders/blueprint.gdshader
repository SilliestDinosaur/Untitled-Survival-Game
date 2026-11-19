// The see-through blue of a blueprint, above its build line (below it the real piece stands). A bright band
// glows right at the line, where the work is going on.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 color : source_color = vec4(0.45, 0.72, 1.0, 0.38);
uniform vec4 edge_color : source_color = vec4(0.85, 0.95, 1.0, 0.9);
instance uniform float build_cut = -1000.0;

varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	if (local_y < build_cut) {
		discard;
	}
	float band = 1.0 - smoothstep(0.0, 0.06, local_y - build_cut);
	// A faint drafting grid, so it reads as a plan.
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 g = abs(fract(wpos * 2.0) - 0.5);
	float grid = 1.0 - smoothstep(0.0, 0.04, min(min(g.x, g.y), g.z));
	vec4 c = mix(color, edge_color, band);
	ALBEDO = c.rgb + grid * 0.08;
	ALPHA = clamp(c.a + grid * 0.08 + band * 0.3, 0.0, 1.0);
}
