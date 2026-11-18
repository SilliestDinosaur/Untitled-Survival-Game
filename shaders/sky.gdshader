// Stylized painted sky: gradient, sun and moon, drifting clouds, and stars at night.
// Colors are driven by the day/night cycle (atmosphere.gd).
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.3, 0.55, 0.9);
uniform vec3 horizon_color : source_color = vec3(0.75, 0.85, 0.95);
uniform vec3 ground_color : source_color = vec3(0.3, 0.4, 0.5);
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform vec3 sun_glow : source_color = vec3(1.0, 0.6, 0.35);   // warm halo near the horizon
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_speed = 0.004;
uniform float night = 0.0;          // 0 day .. 1 full night
uniform float sunset = 0.0;         // 0 .. 1 golden hour strength
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform sampler2D cloud_noise : repeat_enable, filter_linear;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(-0.02, 0.5, h));
	col = mix(col, ground_color, smoothstep(0.0, -0.3, h));

	// Sunset glow hugs the horizon on the sun's side.
	float toward_sun = max(dot(normalize(vec3(d.x, 0.0, d.z)), normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + 1e-4)), 0.0);
	col = mix(col, sun_glow, sunset * pow(toward_sun, 3.0) * (1.0 - smoothstep(0.0, 0.35, abs(h))) * 0.8);

	float sd = max(dot(d, sun_dir), 0.0);
	vec3 sun = mix(vec3(1.0, 0.95, 0.85), sun_glow, sunset) * (1.0 - night);
	col += sun * (pow(sd, 10.0) * 0.15 + pow(sd, 220.0) * 0.5);
	col += sun * smoothstep(0.9994, 0.9997, sd) * 5.0;

	// Stars: hashed cells on the sky dome, twinkling, only at night and above the horizon. They're added after the
	// clouds, dimmed by how much cloud is in front of them, so none shine through a cloud.
	vec3 stars = vec3(0.0);
	float cover = 0.0;
	if (night > 0.01 && h > 0.0) {
		// Each star is a small round point somewhere inside its cell, of its own size and brightness. (A glow as big
		// as the cell was clipped by the cell's edges into a white square, and read as snow.)
		vec3 cell = floor(d * 160.0);
		float star = step(0.99, hash(cell));
		vec3 jitter = vec3(hash(cell + 1.7), hash(cell + 5.3), hash(cell + 9.1));
		vec3 center = (cell + 0.25 + 0.5 * jitter) / 160.0;
		float dist = length(d - normalize(center));
		float size = mix(0.0008, 0.0022, hash(cell + 2.2));
		float bright = mix(0.45, 1.5, hash(cell + 7.7));
		float tw = 0.6 + 0.4 * sin(TIME * (1.5 + hash(cell + 3.1) * 3.0) + hash(cell) * 30.0);
		stars = vec3(0.9, 0.92, 1.0) * star * smoothstep(size, size * 0.2, dist) * bright * tw * night * smoothstep(0.0, 0.25, h) * 1.4;
	}
	// Moon: a soft disc with a halo.
	float md = max(dot(d, moon_dir), 0.0);
	col += vec3(0.85, 0.9, 1.0) * (smoothstep(0.9992, 0.9995, md) * 1.6 + pow(md, 60.0) * 0.12) * night;

	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * 0.16;
		// Warp the lookup so cloud edges look brushed rather than noisy.
		uv += (texture(cloud_noise, uv * 0.6 + 0.3).r - 0.5) * 0.12;
		vec2 drift = vec2(TIME * cloud_speed);
		float dens = texture(cloud_noise, uv + drift).r * 0.72 + texture(cloud_noise, uv * 2.7 - drift * 1.7).r * 0.28;
		float c = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.16, dens);
		c *= smoothstep(0.0, 0.14, h);
		// Two-tone painted shading: compare density a little toward the light.
		vec3 light_dir = night > 0.5 ? moon_dir : sun_dir;
		vec2 to_light = normalize(light_dir.xz + vec2(0.0001)) * 0.035;
		float dens_l = texture(cloud_noise, uv + drift + to_light).r * 0.72 + texture(cloud_noise, (uv + to_light) * 2.7 - drift * 1.7).r * 0.28;
		float lit = smoothstep(-0.02, 0.03, dens - dens_l + 0.01);
		vec3 shade = mix(top_color, horizon_color, 0.55) * 0.92;
		vec3 night_cloud = mix(top_color, vec3(0.45, 0.5, 0.65), 0.35);
		vec3 lit_col = mix(mix(cloud_color, sun_glow * 1.1, sunset * 0.6), night_cloud, night);
		vec3 cc = mix(shade, lit_col * (1.0 + 0.25 * pow(sd, 4.0) * (1.0 - night)), 0.35 + 0.65 * lit);
		cc = mix(cc, horizon_color, 0.3 * (1.0 - smoothstep(0.0, 0.3, h)));
		col = mix(col, cc, c * mix(0.95, 0.9, night));
		cover = c;
	}
	col += stars * (1.0 - smoothstep(0.0, 0.6, cover));
	COLOR = col;
}
