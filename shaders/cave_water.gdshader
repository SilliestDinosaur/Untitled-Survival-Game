// Still water underground (lakes and pools): an inky mirror. It shows back what's above it (glowing fungus, crystals,
// torches, the walls they light) through a short screen-space march, you see the bed through it only near the shore,
// rings spread out where drips land, and a faint pale line laps at the stones. No sky down here: only the lights
// nearby glint on it.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx, ambient_light_disabled;

uniform vec3 deep_color : source_color = vec3(0.012, 0.03, 0.035);
uniform vec3 tint : source_color = vec3(0.55, 0.75, 0.78);   // what the bed takes on, seen through the water
uniform float clarity = 0.5;                                  // metres of water you see the bed through
uniform float drip_density = 0.45;                            // share of the little cells that have a drip falling
uniform float roof = 3.0;   // metres up to the rock a lake's mirror is assumed to show (when the exact one finds nothing)
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// The view-space depth of the scene behind a screen spot.
float scene_z(vec2 suv, mat4 inv_proj) {
	float d = texture(depth_tex, suv).r;
	vec4 view = inv_proj * vec4(suv * 2.0 - 1.0, d, 1.0);
	return view.z / view.w;
}

// The slope of the water at p: rings spreading out from where drips land (each cell of a loose grid has its own
// drip, falling now and then), and a very slow swell.
vec2 surface_slope(vec2 p, float t) {
	vec2 g = vec2(0.0);
	const float CELL = 1.4;
	vec2 cell = floor(p / CELL);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			float h = hash(c);
			if (h > drip_density) {
				continue;
			}
			vec2 centre = (c + vec2(hash(c + 3.1), hash(c + 7.7))) * CELL;
			float period = 2.2 + hash(c + 1.9) * 4.5;
			float age = mod(t + h * 31.0, period);
			vec2 d = p - centre;
			float r = length(d);
			float w = r - age * 0.5;   // the ring's front, spreading at half a metre a second
			float amp = exp(-age * 1.3) * (1.0 - smoothstep(0.0, 0.3, abs(w)));
			g += d / max(r, 0.001) * sin(w * 30.0) * amp * 0.35;
		}
	}
	g += vec2(sin(p.x * 0.9 + t * 0.21 + sin(p.y * 0.7)), cos(p.y * 1.1 - t * 0.17)) * 0.012;
	return g;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = surface_slope(world_pos.xz, TIME);
	vec3 n = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = normalize(world_pos - cam);
	// How deep the water is here (the bed, seen through it near the shore): the length of the view through it,
	// turned to straight down (looked at low across a lake the view runs a long way through shallow water).
	float thick = max(VERTEX.z - scene_z(SCREEN_UV, INV_PROJECTION_MATRIX), 0.0) * max(-v.y, 0.05);
	vec2 bent = SCREEN_UV + g * 0.03 * clamp(thick * 2.0, 0.0, 1.0);
	if (VERTEX.z - scene_z(bent, INV_PROJECTION_MATRIX) < 0.0) {
		bent = SCREEN_UV;   // don't bend things in front of the water into it
	}
	float see = exp(-thick / clarity);
	vec3 bed = textureLod(screen_tex, bent, 0.0).rgb * tint;

	// The mirror: along the reflected ray, find where it passes behind what's on screen, and take the colour there.
	vec3 r = reflect(v, n);
	vec3 refl = vec3(0.0);
	float found = 0.0;
	float t = 0.1;
	for (int i = 0; i < 24; i++) {
		t *= 1.24;   // out to some 17 m, finer close in
		vec3 p = world_pos + r * t;
		vec4 pv = VIEW_MATRIX * vec4(p, 1.0);
		vec4 clip = PROJECTION_MATRIX * pv;
		if (clip.w <= 0.0) {
			break;
		}
		vec2 suv = clip.xy / clip.w * 0.5 + 0.5;
		if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
			break;
		}
		float sz = scene_z(suv, INV_PROJECTION_MATRIX);
		// Behind what's on screen there (not far behind: then it's passing behind something nearer, not meeting it).
		if (pv.z < sz - 0.02 && pv.z > sz - max(t * 0.35, 0.6)) {
			// Fades out toward the screen's edges, where what it would show is off screen.
			vec2 e = min(suv, 1.0 - suv);
			found = smoothstep(0.0, 0.08, min(e.x, e.y)) * (1.0 - float(i) / 24.0 * 0.4);
			refl = textureLod(screen_tex, suv, 1.0).rgb;
			break;
		}
	}
	// Where the exact mirror found nothing (or there's no depth to find it with), the rock and the lights over the water
	// as if they were a roof `roof` metres up: the reflected ray meets that roof, and whatever is drawn there on screen
	// is shown, softened. Still water under a cave roof looks just about right this way.
	if (found < 0.99) {
		float up = max(r.y, 0.06);
		vec3 q = world_pos + r * min(roof / up, 14.0);
		vec4 qc = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(q, 1.0));
		if (qc.w > 0.0) {
			vec2 quv = qc.xy / qc.w * 0.5 + 0.5;
			vec2 e = min(quv, 1.0 - quv);
			float ok = smoothstep(0.0, 0.1, min(e.x, e.y));
			vec3 approx = textureLod(screen_tex, clamp(quv, 0.0, 1.0), 1.5).rgb;
			refl = mix(approx, refl, found);
			found = mix(ok * 0.85, 1.0, found);
		}
	}
	float cos_v = clamp(dot(n, -v), 0.0, 1.0);
	float fres = 0.08 + 0.92 * pow(1.0 - cos_v, 4.0);
	float mirror = mix(0.45, 0.95, fres) * found;

	vec3 body = mix(deep_color, bed, see);
	vec3 col = mix(body, refl * 0.85, mirror);

	// A faint pale line where it laps at the stones and the shore, coming and going.
	float lap = sin(TIME * 1.3 + world_pos.x * 2.1 + world_pos.z * 1.7) * 0.012;
	float edge = 1.0 - smoothstep(0.0, 0.06, thick + lap);

	// The water's own colour is lit (by torches, fires and glow: no sky down here); what's seen in it and through it
	// is already lit, so it goes in as emission.
	ALBEDO = deep_color + vec3(0.32, 0.36, 0.36) * edge;
	EMISSION = col * (1.0 - edge * 0.6);
	ROUGHNESS = 0.035 + edge * 0.5;
	SPECULAR = 0.65;
	ALPHA = 0.999;   // (drawn with the see-through things, after the rock: it reads the rock behind it)
}
