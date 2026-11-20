// Full-screen mood: frost creeping in from the edges when cold, a warm glow by a fire, the world draining of colour
// and pulsing when badly hurt, and a wobbling, softened view underwater. Drawn only while one of them is showing.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float frost = 0.0;
uniform float warm = 0.0;
uniform float hurt = 0.0;
uniform float water = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += noise(p) * a; p *= 2.1; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 c = (uv - 0.5) * vec2(aspect, 1.0);
	float edge = length(c);
	// Underwater: the view sways and softens.
	if (water > 0.0) {
		uv += vec2(sin(uv.y * 18.0 + TIME * 2.2), cos(uv.x * 14.0 + TIME * 1.7)) * 0.004 * water;
	}
	// Frost bends the light a little where it's thick.
	float crystals = fbm(c * 9.0) * 0.7 + fbm(c * 40.0) * 0.3;
	float frost_mask = smoothstep(0.78 - frost * 0.28, 0.98 - frost * 0.15, edge + (crystals - 0.5) * 0.3) * frost;
	uv += (vec2(crystals) - 0.5) * 0.012 * frost_mask;
	vec3 col = textureLod(screen, uv, water * 1.6).rgb;
	if (water > 0.0) {
		col = mix(col, col * vec3(0.55, 0.85, 0.95) + vec3(0.0, 0.03, 0.05), water * 0.6);
	}
	// Hurt: colour drains and the edges throb darker with the heartbeat.
	if (hurt > 0.0) {
		float grey = dot(col, vec3(0.3, 0.59, 0.11));
		float beat = pow(abs(sin(TIME * 2.6)), 6.0);
		col = mix(col, vec3(grey), hurt * 0.65);
		col *= 1.0 - hurt * (0.25 + 0.35 * beat) * smoothstep(0.25, 0.85, edge);
	}
	// Frost: white-blue rime with sparkly crystals.
	vec3 rime = vec3(0.85, 0.93, 1.0) * (0.75 + 0.35 * step(0.82, fbm(c * 60.0)));
	col = mix(col, rime, frost_mask * 0.6);
	// Warmth: a soft orange glow rising from the bottom and sides.
	float glow = smoothstep(0.25, 0.9, edge) * (0.6 + 0.4 * (1.0 - SCREEN_UV.y)) * (0.85 + 0.15 * sin(TIME * 7.0) * sin(TIME * 3.1));
	col += vec3(1.0, 0.45, 0.12) * glow * warm * 0.6;
	col = mix(col, col * vec3(1.06, 1.0, 0.9), warm * 0.5);   // and the whole picture a touch warmer
	COLOR = vec4(col, 1.0);
}
