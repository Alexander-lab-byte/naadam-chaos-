shader_type spatial;
// The steppe: grass with dry patches, a trampled wrestling circle, rock on steep
// slopes, darker ground under the larch forests, snow on the high peaks, cloud shadows.
#include "res://shaders/common.gdshaderinc"

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float ring_radius = 6.0;
uniform float snow_height = 400.0;

varying vec3 wpos;
varying vec3 wnorm;
varying float forest;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	forest = COLOR.r;
}

float slope0(vec3 n) { return 1.0 - n.y; }

void fragment() {
	vec2 p = wpos.xz;
	float dist = length(p);
	// grass: two scales so the tiling never shows
	vec3 g1 = texture(grass_tex, p / 7.0).rgb;
	vec3 g2 = texture(grass_tex, p / 41.0 + 0.37).rgb;
	vec3 grass = mix(g1, g2, 0.45);
	float macro = nc_fbm(p * 0.012);
	grass *= mix(vec3(0.85, 0.95, 0.85), vec3(1.12, 1.05, 0.9), macro);
	float dry = smoothstep(0.58, 0.78, nc_fbm(p * 0.004 + 9.0));
	grass = mix(grass, grass * vec3(1.35, 1.15, 0.75), dry * 0.55);
	// higher up: darker, more olive steppe grass; shaded slopes a bit darker (gives the hills shape)
	grass = mix(grass, grass * vec3(0.78, 0.82, 0.6), smoothstep(20.0, 160.0, wpos.y));
	grass *= mix(1.0, 0.8, smoothstep(0.08, 0.3, slope0(wnorm)));
	// larch forest floor
	grass = mix(grass, grass * vec3(0.55, 0.7, 0.5), forest);
	// trampled wrestling circle (and a worn path ring around it)
	vec3 dirt = texture(dirt_tex, p / 5.0).rgb;
	float wear = (1.0 - smoothstep(ring_radius - 1.2, ring_radius + 0.6, dist)) * (0.55 + 0.45 * nc_fbm(p * 0.8));
	vec3 col = mix(grass, mix(grass * vec3(1.1, 1.05, 0.8), dirt, 0.55), wear);
	// rock on steep slopes
	float slope = 1.0 - wnorm.y;
	vec3 rock = mix(texture(rock_tex, wpos.xy / 23.0).rgb, texture(rock_tex, wpos.zy / 23.0).rgb, abs(wnorm.x));
	col = mix(col, rock * vec3(0.85, 0.82, 0.78), smoothstep(0.26, 0.45, slope + (nc_fbm(p * 0.02) - 0.5) * 0.2));
	// snow on the peaks
	float snow = smoothstep(snow_height - 40.0, snow_height + 30.0, wpos.y + nc_fbm(p * 0.01) * 50.0) * smoothstep(0.35, 0.7, wnorm.y);
	col = mix(col, vec3(0.93, 0.95, 1.0), snow);
	// far away: a little darker and cooler, so the mountains have weight
	col *= mix(vec3(1.0), vec3(0.72, 0.78, 0.8), smoothstep(120.0, 900.0, dist));
	col *= nc_cloud_shadow(p, TIME);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.6, snow);
	SPECULAR = 0.25;
}
