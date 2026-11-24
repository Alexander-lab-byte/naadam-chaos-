shader_type spatial;
// The crowd (MultiMesh of little people in deels).
// Per person (INSTANCE_CUSTOM): r = random phase, g = deel color index, b = shoulder height, a = 1 for zasuul.
// Mesh data: vertex color = base color, UV2.x = 1 on the deel (gets the person's color), UV2.y = 1 on the arms.
// `hype` (0..1) comes from the game: big throws make the crowd jump and throw their arms up.
#include "res://shaders/common.gdshaderinc"

uniform float hype = 0.15;
const vec3 DEEL[10] = vec3[10](
	vec3(0.48, 0.03, 0.04), vec3(0.03, 0.09, 0.42), vec3(0.75, 0.42, 0.05), vec3(0.03, 0.22, 0.12),
	vec3(0.17, 0.05, 0.25), vec3(0.75, 0.72, 0.62), vec3(0.62, 0.17, 0.03), vec3(0.08, 0.25, 0.48),
	vec3(0.32, 0.04, 0.1), vec3(0.12, 0.1, 0.09));

varying vec3 col;
varying vec3 wpos;

mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(vec2(c, s), vec2(-s, c)); }

void vertex() {
	float ph = INSTANCE_CUSTOM.r * 6.2831;
	float arm = UV2.y;
	float robe = UV2.x;
	vec3 deel = DEEL[int(INSTANCE_CUSTOM.g * 9.99)];
	col = mix(COLOR.rgb, COLOR.rgb * deel * 1.5, robe);
	float zasuul = INSTANCE_CUSTOM.a;
	float h = mix(hype, 0.05, zasuul);
	// cheering: arms go up and wave (some people clap instead)
	float cheer = clamp(h * 1.6 - 0.25 + sin(TIME * 0.7 + ph) * 0.25, 0.0, 1.0);
	float wave = sin(TIME * 7.0 + ph) * 0.35 * cheer;
	float side = sign(VERTEX.x);
	vec2 sh = vec2(side * 0.2, INSTANCE_CUSTOM.b);
	float raise = (cheer * 2.5 + wave) * side;
	vec2 p = VERTEX.xy - sh;
	p = rot(raise) * p;
	VERTEX.xy = mix(VERTEX.xy, sh + p, arm);
	// idle sway + jumping
	float jump = max(0.0, sin(TIME * (6.0 + INSTANCE_CUSTOM.r * 3.0) + ph)) * h * 0.22;
	VERTEX.y += jump + sin(TIME * 1.1 + ph) * 0.012;
	VERTEX.x += sin(TIME * 0.9 + ph) * 0.015 * VERTEX.y;
	wpos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	ALBEDO = col * nc_cloud_shadow(wpos.xz, TIME);
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
}
