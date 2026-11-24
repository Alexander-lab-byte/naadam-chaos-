shader_type spatial;
// Vertex-colored nature props (larch trees, rocks, flowers). Trees sway a little in the wind.
#include "res://shaders/common.gdshaderinc"

uniform float sway = 0.0;      // 0 for rocks, ~0.08 for trees
varying vec3 col;
varying vec3 wpos;

void vertex() {
	col = COLOR.rgb;
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	float g = nc_gust(base.xz, TIME);
	VERTEX.x += (sin(TIME * 1.3 + base.x * 0.1) * 0.3 + g) * sway * h * 0.1;
	VERTEX.z += cos(TIME * 1.1 + base.z * 0.1) * sway * h * 0.05;
	wpos = base;
}

void fragment() {
	ALBEDO = col * nc_cloud_shadow(wpos.xz, TIME);
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.08, 0.12, 0.04) * sway * 10.0;
}
