shader_type sky;
// Deep Mongolian blue sky ("Eternal Blue Sky", Мөнх хөх тэнгэр) with drifting clouds.
#include "res://shaders/common.gdshaderinc"

uniform vec3 top_color : source_color = vec3(0.13, 0.33, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.76, 0.92);
uniform vec3 ground_color : source_color = vec3(0.32, 0.38, 0.28);
uniform float cloud_cover = 0.45;
uniform float cloud_speed = 0.004;

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.45));
	col = mix(col, ground_color, smoothstep(0.0, -0.08, h));
	float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
	col += LIGHT0_COLOR * (pow(sd, 900.0) * 8.0 + pow(sd, 12.0) * 0.18);
	if (h > 0.0 && !AT_CUBEMAP_PASS) {
		vec2 uv = d.xz / (h + 0.1) * 0.55 + TIME * cloud_speed * vec2(1.0, 0.35);
		float n = nc_fbm(uv * 1.6) * 0.65 + nc_fbm(uv * 4.3 + 3.0) * 0.35;
		float c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.22, n);
		float shade = smoothstep(0.0, 0.25, n - (1.0 - cloud_cover)) ;
		vec3 ccol = mix(vec3(0.72, 0.75, 0.82), vec3(1.0, 0.99, 0.97), 1.0 - shade * 0.6);
		ccol += LIGHT0_COLOR * pow(sd, 6.0) * 0.25;
		float fade = smoothstep(0.0, 0.18, h);
		col = mix(col, ccol, c * fade);
	}
	COLOR = col;
}
