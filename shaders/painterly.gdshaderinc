// Shared "gouache" material look. Everything painterly happens per surface (no screen filter):
//  - a generated brush-stroke texture varies the pigment like layered daubs of paint
//  - the light/shadow boundary follows the strokes, so shading edges look brushed
//  - soft value banding flattens shading into a few painted tones
//  - paint "pools" slightly darker toward silhouette edges

uniform sampler2D brush_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D stroke_tex : repeat_enable, filter_linear_mipmap;
uniform float brush_strength = 0.28;   // how much strokes change the color
uniform float stroke_scale = 0.35;     // strokes per meter
uniform float light_wrap = 0.45;
uniform float edge_pool = 0.18;        // darkening at grazing angles (0 for terrain)

varying float paint_stroke;

// Two soft steps instead of a smooth gradient: reads as "painted" rather than "rendered".
float paint_ramp(float ndl) {
	float w = clamp((ndl + light_wrap) / (1.0 + light_wrap), 0.0, 1.0);
	return smoothstep(0.1, 0.36, w) * 0.62 + smoothstep(0.52, 0.78, w) * 0.38;
}

// Triplanar blending: sample the paint from all three axis planes and blend by how much the
// surface faces each one. (Picking a single plane caused visible seams where it switched.)
vec3 tri_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / max(w.x + w.y + w.z, 1e-4);
}

float tri_sample(sampler2D tex, vec3 p, vec3 w, float scale, vec2 offset) {
	float x = w.x > 0.01 ? texture(tex, p.zy * scale + offset).r : 0.0;
	float y = w.y > 0.01 ? texture(tex, p.xz * scale + offset).r : 0.0;
	float z = w.z > 0.01 ? texture(tex, p.xy * scale + offset).r : 0.0;
	return x * w.x + y * w.y + z * w.z;
}

// Returns the painted albedo; stroke_out goes into paint_stroke for the light pass.
vec3 brush(vec3 col, vec3 wpos, vec3 wn, out float stroke_out) {
	vec3 w = tri_weights(wn);
	float broad = tri_sample(brush_noise, wpos, w, 0.03, vec2(0.0)) - 0.5;   // big uneven washes
	float s1 = tri_sample(stroke_tex, wpos, w, stroke_scale, vec2(0.0));
	float s2 = tri_sample(stroke_tex, wpos, w, stroke_scale * 2.3, vec2(0.41));
	// Blending several planes flattens contrast a little; restore it.
	float stroke = 0.5 + (mix(s1, s2, 0.35) - 0.5) * mix(1.0, 1.5, 1.0 - max(max(w.x, w.y), w.z));
	stroke_out = stroke;
	float v = (stroke - 0.5) + broad * 0.8;
	// Lighter daubs lean warm, darker daubs lean cool, like layered gouache.
	vec3 tint = v > 0.0 ? vec3(1.05, 1.0, 0.92) : vec3(0.93, 0.98, 1.07);
	vec3 c = col * (1.0 + v * brush_strength * 1.6);
	c *= mix(vec3(1.0), tint, clamp(abs(v) * brush_strength * 4.0, 0.0, 1.0));
	// Soft value banding: pull colors toward a few pigment steps.
	float l = max(max(c.r, c.g), c.b) + 1e-4;
	float lq = (floor(l * 7.0) + smoothstep(0.3, 0.7, fract(l * 7.0))) / 7.0;
	return mix(c, c * (lq / l), 0.45);
}

// Darker paint toward the silhouette (call from fragment()).
vec3 pool_edges(vec3 albedo, vec3 n, vec3 view) {
	float f = pow(1.0 - clamp(dot(n, view), 0.0, 1.0), 2.5);
	return albedo * (1.0 - f * edge_pool);
}

void light() {
	// Stroke-jittered terminator and shadow edge: brushed rather than crisp.
	float jitter = (paint_stroke - 0.5) * 0.45;
	float r = paint_ramp(dot(NORMAL, LIGHT) + jitter);
	float shadow = smoothstep(0.25, 0.75, ATTENUATION + jitter * 0.6);
	DIFFUSE_LIGHT += r * shadow * LIGHT_COLOR / PI;
}
