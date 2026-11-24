shader_type spatial;
// Grass blades (MultiMesh). Wind sways every blade, big gusts roll across the field,
// cloud shadows pass over. Blades in the wrestling circle are short and trampled.
render_mode cull_disabled, world_vertex_coords;
#include "res://shaders/common.gdshaderinc"

uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float ring_radius = 6.0;
uniform float wind_strength = 1.0;

varying float hgt;
varying vec3 tint;
varying vec3 wpos;

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	hgt = UV.y;
	// trampled inside the circle
	float r = length(base.xz);
	float trample = mix(0.35, 1.0, smoothstep(ring_radius - 0.5, ring_radius + 1.5, r));
	vec3 v = VERTEX - base;
	v.y *= trample;
	// wind: steady sway + rolling gusts, stronger at the tip
	float gust = nc_gust(base.xz, TIME);
	float sway = sin(TIME * 2.4 + base.x * 0.7 + base.z * 0.5 + INSTANCE_CUSTOM.r * 6.0) * 0.18 + gust * 0.95;
	float bend = sway * hgt * hgt * wind_strength;
	v.xz += WIND_DIR * bend * 0.32;
	v.y -= bend * bend * 0.05;
	VERTEX = base + v;
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.65));
	tint = texture(grass_tex, base.xz / 7.0).rgb * (0.85 + INSTANCE_CUSTOM.g * 0.35);
	tint = mix(tint, tint * vec3(1.15, 1.08, 0.75), 1.0 - trample);
	wpos = base;
}

void fragment() {
	vec3 col = mix(tint * 0.45, tint * vec3(1.15, 1.08, 0.82) + vec3(0.03, 0.03, 0.0), hgt);
	col *= nc_cloud_shadow(wpos.xz, TIME);
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.16, 0.2, 0.07) * hgt;
}
