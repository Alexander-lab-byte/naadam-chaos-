shader_type spatial;
// White horsehair of the Nine White Banners: alpha strands that swing in the wind.
render_mode cull_disabled;
#include "res://shaders/common.gdshaderinc"

uniform sampler2D hair_tex : source_color, filter_linear_mipmap;

void vertex() {
	float k = UV2.y;                         // 0 at the top ring, 1 at the tips
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float g = nc_gust(base.xz, TIME);
	float s = sin(TIME * 2.1 + VERTEX.x * 3.0 + VERTEX.z * 2.0) * 0.06 + g * 0.22;
	VERTEX.x += s * k * k + sin(TIME * 5.0 + VERTEX.z * 9.0) * 0.015 * k;
	VERTEX.z += s * 0.6 * k * k;
}

void fragment() {
	vec4 t = texture(hair_tex, UV);
	ALBEDO = t.rgb * vec3(1.0, 0.99, 0.96);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.35;
	ROUGHNESS = 0.55;
	BACKLIGHT = vec3(0.35);
}
