// A soft shaft of daylight falling in through a cave mouth: glowing air, brightest where it comes in, fading along
// its length and out to its edges, a little shimmer as dust drifts through it. Drawn on crossed quads (UV.y runs
// along the shaft from the mouth, UV.x across it).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.93, 0.78);
uniform float strength = 0.38;
uniform float day = 1.0;   // set by the game: no shafts at night
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float edge = smoothstep(0.0, 0.7, across);
	float along = smoothstep(0.0, 0.12, UV.y) * pow(1.0 - UV.y, 1.6);
	// Soft streaks running down the shaft, slowly drifting.
	float streak = 0.75 + 0.25 * sin(UV.x * 23.0 + TIME * 0.35) * sin(UV.x * 9.0 - TIME * 0.2 + UV.y * 3.0);
	// Fades out where it passes into the rock or the floor (no hard line along the wall).
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	behind.xyz /= behind.w;
	float soft = smoothstep(0.0, 0.9, VERTEX.z - behind.z);
	// And as you come right up to it (it's air, not a sheet).
	float near = smoothstep(0.6, 2.5, -VERTEX.z);
	// Each quad fades as it turns edge-on (no bright line where you see one side-on).
	float facing = smoothstep(0.15, 0.6, abs(dot(NORMAL, VIEW)));
	ALBEDO = tint * strength * day * edge * along * streak * soft * near * facing;
}
