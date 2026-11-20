// Heat haze: a camera-facing card over something hot that wobbles what's behind it. `strength` 0 = invisible.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;

void vertex() {
	// Face the camera (keeping the card's size).
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0),
		vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}

void fragment() {
	vec2 c = UV - 0.5;
	float mask = smoothstep(0.5, 0.15, length(c * vec2(1.4, 1.0))) * smoothstep(0.0, 0.35, UV.y);   // strongest low down
	float t = TIME * 3.0;
	vec2 wob = vec2(sin(UV.y * 22.0 - t * 2.0) + sin(UV.y * 9.0 - t), cos(UV.x * 17.0 - t * 1.6)) * 0.004 * strength * mask;
	ALBEDO = textureLod(screen, SCREEN_UV + wob, 0.0).rgb;
	ALPHA = mask * step(0.001, strength);
}
