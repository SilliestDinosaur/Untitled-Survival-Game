// Painted water for the sea, rivers and lakes (all share the sea-level plane).
// Clear shallows that show the refracted ground, banded depth colors, sky-tinted fresnel,
// brushy sun glints and foam lines that lap at the shore.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.2, 0.6, 0.7);
uniform vec3 deep_color : source_color = vec3(0.03, 0.15, 0.3);
uniform vec3 foam_color : source_color = vec3(0.95, 0.97, 1.0);
uniform vec3 sky_color : source_color = vec3(0.6, 0.75, 0.9);
uniform float night = 0.0;
uniform float depth_scale = 6.0;
uniform float clarity = 2.2;            // metres of water you can see through near the shore
uniform float foam_width = 1.1;
uniform sampler2D ripple_a : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D ripple_b : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float scene_depth(vec2 suv, vec3 vertex, mat4 inv_proj) {
	float d = texture(depth_tex, suv).r;
	vec3 ndc = vec3(suv * 2.0 - 1.0, d);
	vec4 view = inv_proj * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return max(vertex.z - view.z, 0.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz;
	vec3 n1 = texture(ripple_a, uv * 0.03 + TIME * vec2(0.010, 0.006)).rgb;
	vec3 n2 = texture(ripple_b, uv * 0.055 - TIME * vec2(0.007, 0.011)).rgb;
	vec3 nm = mix(n1, n2, 0.5);
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 0.45;

	// Water thickness behind this pixel, then again at a ripple-offset position for refraction.
	float water_depth = scene_depth(SCREEN_UV, VERTEX, INV_PROJECTION_MATRIX);
	vec2 offset = (nm.xy - 0.5) * 0.05 * clamp(water_depth / 2.0, 0.0, 1.0);
	vec2 ref_uv = SCREEN_UV + offset;
	float ref_depth = scene_depth(ref_uv, VERTEX, INV_PROJECTION_MATRIX);
	if (ref_depth <= 0.0) {
		ref_uv = SCREEN_UV;   // don't refract things in front of the water
		ref_depth = water_depth;
	}
	vec3 ground = textureLod(screen_tex, ref_uv, 0.0).rgb;

	// Banded depth color: painted in a few flat washes rather than a smooth gradient.
	float t = clamp(ref_depth / depth_scale, 0.0, 1.0);
	float wobble = (texture(ripple_a, uv * 0.012).r - 0.5) * 0.18;
	float bands = floor((sqrt(t) + wobble) * 4.0 + 0.5) / 4.0;
	vec3 body = mix(shallow_color, deep_color, clamp(mix(sqrt(t), bands, 0.55), 0.0, 1.0));
	// Clear near the shore: you see the sand and stones through a tinted film. The ground is
	// already lit, so it goes in as emission and the lit water body is faded out over it.
	float see = exp(-ref_depth / clarity) * 0.85;
	vec3 through = ground * mix(vec3(1.0), shallow_color * 1.6, 0.45);

	// Sky reflection at grazing angles.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 col = mix(body, sky_color, fres * 0.55);
	see *= 1.0 - fres;

	// Foam: a ragged band at the waterline plus lines that roll in toward the shore.
	float fn = texture(ripple_a, uv * 0.18 + TIME * 0.02).r;
	float edge = 1.0 - smoothstep(0.0, foam_width, water_depth + (fn - 0.5) * 0.9);
	float roll = sin(water_depth * 3.2 - TIME * 1.4 + fn * 4.0) * 0.5 + 0.5;
	float lines = smoothstep(0.8, 0.95, roll) * (1.0 - smoothstep(0.4, 2.6, water_depth));
	float foam = clamp(smoothstep(0.35, 0.6, edge) + lines * 0.55 * step(0.45, fn), 0.0, 1.0);

	// Brushy glints: hashed cells that light up with the ripples.
	vec2 cell = floor(uv * 1.5);
	float g = step(0.985, hash(cell + floor(TIME * 0.7))) * smoothstep(0.55, 0.75, nm.g) * (1.0 - night);

	col = mix(col, foam_color * mix(1.0, 0.35, night), foam);
	float clear = see * (1.0 - foam);
	ALBEDO = col * (1.0 - clear);
	EMISSION = through * clear + vec3(g) * 0.6;
	ALPHA = 1.0;
	ROUGHNESS = mix(0.08, 0.7, foam);
	SPECULAR = mix(0.5, 0.2, foam);
}
