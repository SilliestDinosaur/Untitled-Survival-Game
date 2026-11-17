// Shared "gouache" look: soft wrapped light in two gentle bands, no shiny highlights,
// and world-space brush-stroke variation in the paint color.

uniform sampler2D brush_noise : repeat_enable, filter_linear_mipmap;
uniform float brush_strength = 0.28;
uniform float light_wrap = 0.45;

// Two soft steps instead of a smooth gradient: reads as "painted" rather than "rendered".
float paint_ramp(float ndl) {
	float w = clamp((ndl + light_wrap) / (1.0 + light_wrap), 0.0, 1.0);
	return smoothstep(0.08, 0.38, w) * 0.6 + smoothstep(0.5, 0.82, w) * 0.4;
}

// Varies color like uneven brush strokes. Projects onto the dominant axis plane.
vec3 brush(vec3 col, vec3 wpos, vec3 wn) {
	vec3 an = abs(wn);
	vec2 uv = an.y > max(an.x, an.z) ? wpos.xz : (an.x > an.z ? wpos.zy : wpos.xy);
	float broad = texture(brush_noise, uv * 0.045).r;
	float stroke = texture(brush_noise, uv * vec2(0.42, 0.09) + vec2(0.31, 0.77)).r;
	float v = mix(broad, stroke, 0.45) - 0.5;
	// Lighter strokes lean warm, darker strokes lean cool, like layered paint.
	vec3 tint = v > 0.0 ? vec3(1.04, 1.0, 0.94) : vec3(0.94, 0.98, 1.06);
	return col * (1.0 + v * brush_strength * 2.0) * mix(vec3(1.0), tint, abs(v) * 2.0 * brush_strength * 2.5);
}

void light() {
	float r = paint_ramp(dot(NORMAL, LIGHT)) * ATTENUATION;
	DIFFUSE_LIGHT += r * LIGHT_COLOR / PI;
}
