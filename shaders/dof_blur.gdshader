// Depth of field as one full-screen pass on a card hung in front of the camera: sharp up to `focus` metres, then
// softening over `range` to `amount` (0..1) of the strongest blur. Only drawn while blur is wanted.
// Where the depth buffer can't be read (some software drivers give all zeros) it falls back to a sharp middle and
// soft edges, since what's being looked at is always in the middle of the screen.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float focus = 1.5;
uniform float range = 1.5;
uniform float amount = 0.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = textureLod(depth_tex, uv, 0.0).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

void fragment() {
	float centre_raw = textureLod(depth_tex, vec2(0.5), 0.0).r + textureLod(depth_tex, vec2(0.45, 0.55), 0.0).r;
	float b;
	if (centre_raw > 0.0) {
		float z = lin_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
		b = smoothstep(focus, focus + range, z) * amount;
	} else {
		vec2 c = (SCREEN_UV - 0.5) * vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
		b = smoothstep(0.22, 0.75, length(c)) * amount;
	}
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float lod = b * 4.0;
	float r = b * 2.5 * exp2(lod);
	vec3 col = textureLod(screen, SCREEN_UV, lod).rgb * 0.25;
	for (int i = 0; i < 12; i++) {
		float a = float(i) * 0.5236 + 0.3;
		float k = (i % 2 == 0) ? 1.0 : 0.55;   // two rings, so no single ghost outline
		col += textureLod(screen, SCREEN_UV + vec2(cos(a), sin(a)) * r * k * px, lod).rgb * 0.0625;
	}
	ALBEDO = col;
	ALPHA = smoothstep(0.0, 0.08, b);
}
