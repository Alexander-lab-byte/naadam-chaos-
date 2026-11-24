shader_type spatial;
// Cloth flag waving in the wind. UV2.y = 0 at the pole, 1 at the free edge.
render_mode cull_disabled;
#include "res://shaders/common.gdshaderinc"

uniform sampler2D flag_tex : source_color, filter_linear_mipmap;

varying float k;

void vertex() {
	k = UV2.y;
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float g = 0.6 + nc_gust(base.xz, TIME) * 0.8;
	float x = VERTEX.x;
	float w = sin(x * 3.2 - TIME * 6.5 + base.x) * 0.16 + sin(x * 5.7 - TIME * 9.0 + VERTEX.y * 2.0) * 0.05;
	VERTEX.z += w * k * g;
	VERTEX.y -= (1.0 - g * 0.7) * k * k * 0.25;       // droops a bit when the wind drops
	NORMAL = normalize(NORMAL + vec3(-cos(x * 3.2 - TIME * 6.5 + base.x) * 0.5 * k * g, 0.0, 0.0));
}

void fragment() {
	ALBEDO = texture(flag_tex, UV).rgb;
	ROUGHNESS = 0.75;
	BACKLIGHT = vec3(0.3);
}
