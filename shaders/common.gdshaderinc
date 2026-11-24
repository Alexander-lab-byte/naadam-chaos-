// Shared helpers for the Naadam field shaders: noise, wind, cloud shadows.
// The same functions are used everywhere, so clouds and gusts line up across grass, ground and trees.

const vec2 WIND_DIR = vec2(0.85, 0.53);

float nc_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float nc_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(nc_hash(i), nc_hash(i + vec2(1.0, 0.0)), f.x),
			mix(nc_hash(i + vec2(0.0, 1.0)), nc_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float nc_fbm(vec2 p) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 4; i++) { s += nc_noise(p) * a; p = p * 2.03 + 11.7; a *= 0.5; }
	return s / 0.9375;
}

// Big wind gusts that roll across the steppe (0..1)
float nc_gust(vec2 world_xz, float t) {
	return nc_fbm(world_xz * 0.045 - WIND_DIR * t * 0.35);
}

// Moving cloud shadows on the ground (1 = sun, ~0.6 = under a cloud)
float nc_cloud_shadow(vec2 world_xz, float t) {
	float c = nc_fbm(world_xz * 0.0045 + vec2(t * 0.004, t * 0.0015));
	return mix(1.0, 0.62, smoothstep(0.52, 0.68, c));
}
