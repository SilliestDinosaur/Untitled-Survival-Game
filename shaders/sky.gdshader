// Stylized sky: gradient, sun halo, drifting procedural clouds.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.3, 0.55, 0.9);
uniform vec3 horizon_color : source_color = vec3(0.75, 0.85, 0.95);
uniform vec3 ground_color : source_color = vec3(0.3, 0.4, 0.5);
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_speed = 0.004;
uniform sampler2D cloud_noise : repeat_enable, filter_linear;

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(-0.02, 0.5, h));
	col = mix(col, ground_color, smoothstep(0.0, -0.3, h));

	float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
	vec3 sun = LIGHT0_COLOR * LIGHT0_ENERGY;
	col += sun * (pow(sd, 10.0) * 0.12 + pow(sd, 220.0) * 0.5);
	col += sun * smoothstep(0.9994, 0.9997, sd) * 5.0;

	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * 0.16;
		float n = texture(cloud_noise, uv + TIME * cloud_speed).r;
		float n2 = texture(cloud_noise, uv * 2.7 - TIME * cloud_speed * 1.7).r;
		float dens = n * 0.72 + n2 * 0.28;
		float c = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.22, dens);
		c *= smoothstep(0.0, 0.14, h);
		vec3 cc = cloud_color * (0.8 + 0.3 * pow(sd, 4.0));
		cc = mix(cc, horizon_color, 0.3 * (1.0 - smoothstep(0.0, 0.3, h)));
		col = mix(col, cc, c * 0.92);
	}
	COLOR = col;
}
