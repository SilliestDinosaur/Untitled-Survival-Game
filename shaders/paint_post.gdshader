// Full-screen painterly filter (drawn under the HUD):
// a Kuwahara filter flattens detail into brush-like patches, then paper grain
// and soft edge darkening finish the gouache look.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D paper : repeat_enable, filter_linear_mipmap;
uniform int radius : hint_range(0, 4) = 2;
uniform float paper_strength = 0.07;
uniform float saturation = 1.06;
uniform float vignette = 0.22;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 col;
	if (radius <= 0) {
		col = texture(screen_tex, SCREEN_UV).rgb;
	} else {
		// Kuwahara: average of the least "busy" of four overlapping quadrants.
		vec3 m0 = vec3(0.0), m1 = vec3(0.0), m2 = vec3(0.0), m3 = vec3(0.0);
		vec3 s0 = vec3(0.0), s1 = vec3(0.0), s2 = vec3(0.0), s3 = vec3(0.0);
		for (int j = -radius; j <= radius; j++) {
			for (int i = -radius; i <= radius; i++) {
				vec3 c = texture(screen_tex, SCREEN_UV + vec2(float(i), float(j)) * px * 1.5).rgb;
				vec3 c2 = c * c;
				if (i <= 0 && j <= 0) { m0 += c; s0 += c2; }
				if (i >= 0 && j <= 0) { m1 += c; s1 += c2; }
				if (i <= 0 && j >= 0) { m2 += c; s2 += c2; }
				if (i >= 0 && j >= 0) { m3 += c; s3 += c2; }
			}
		}
		float n = float((radius + 1) * (radius + 1));
		m0 /= n; m1 /= n; m2 /= n; m3 /= n;
		float v0 = dot(s0 / n - m0 * m0, vec3(1.0));
		float v1 = dot(s1 / n - m1 * m1, vec3(1.0));
		float v2 = dot(s2 / n - m2 * m2, vec3(1.0));
		float v3 = dot(s3 / n - m3 * m3, vec3(1.0));
		col = m0;
		float best = v0;
		if (v1 < best) { best = v1; col = m1; }
		if (v2 < best) { best = v2; col = m2; }
		if (v3 < best) { best = v3; col = m3; }
	}
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);

	// Paper: fine grain plus larger soft blotches, strongest in the midtones.
	vec2 puv = SCREEN_UV / px / 512.0;
	float grain = texture(paper, puv).r - 0.5;
	float blotch = texture(paper, puv * 0.15 + 0.5).r - 0.5;
	col *= 1.0 + (grain * 0.8 + blotch * 0.6) * paper_strength * (1.0 - abs(luma - 0.5));

	vec2 d = SCREEN_UV - 0.5;
	col *= 1.0 - dot(d, d) * vignette * 1.6;
	COLOR = vec4(col, 1.0);
}
