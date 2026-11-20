// Glowing living things in the dark (moss, glow-worm beads): their vertex colour, bright enough to bloom, unlit,
// with a slow breathing pulse that drifts across them.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform float strength = 2.2;

void fragment() {
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float pulse = 0.8 + 0.2 * sin(TIME * 1.1 + wpos.x * 0.7 + wpos.z * 0.5);
	ALBEDO = COLOR.rgb * strength * pulse;
}
