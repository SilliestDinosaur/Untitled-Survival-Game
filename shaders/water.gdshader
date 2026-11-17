// Ocean: depth-based color, shoreline foam, scrolling ripples.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.2, 0.6, 0.7);
uniform vec3 deep_color : source_color = vec3(0.03, 0.15, 0.3);
uniform vec3 foam_color : source_color = vec3(0.95, 0.97, 1.0);
uniform float depth_scale = 7.0;
uniform float foam_width = 0.9;
uniform sampler2D ripple_a : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D ripple_b : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz;
	vec3 n1 = texture(ripple_a, uv * 0.035 + TIME * vec2(0.010, 0.006)).rgb;
	vec3 n2 = texture(ripple_b, uv * 0.06 - TIME * vec2(0.007, 0.011)).rgb;
	NORMAL_MAP = mix(n1, n2, 0.5);
	NORMAL_MAP_DEPTH = 0.5;

	// How much water is between the surface and the ground behind it.
	float d = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d);
#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float water_depth = max(VERTEX.z - view.z, 0.0);

	float t = clamp(water_depth / depth_scale, 0.0, 1.0);
	vec3 col = mix(shallow_color, deep_color, sqrt(t));

	float foam_noise = texture(ripple_a, uv * 0.2 + TIME * 0.02).r;
	float foam = 1.0 - smoothstep(0.0, foam_width, water_depth + (foam_noise - 0.5) * 0.8);
	foam = smoothstep(0.35, 0.6, foam);

	ALBEDO = mix(col, foam_color, foam);
	ALPHA = clamp(0.5 + t * 0.5 + foam, 0.0, 1.0);
	ROUGHNESS = mix(0.05, 0.6, foam);
	SPECULAR = 0.55;
}
