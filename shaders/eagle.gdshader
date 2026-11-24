shader_type spatial;
// Steppe eagle: wings flap (UV2.y = distance from the body), mostly gliding.
render_mode cull_disabled;
uniform float phase = 0.0;
varying vec3 col;
void vertex() {
	col = COLOR.rgb;
	float t = TIME + phase;
	float flap = sin(t * 7.0) * smoothstep(0.55, 0.8, sin(t * 0.4 + phase) * 0.5 + 0.5);
	float k = UV2.y;
	VERTEX.y += (flap * 0.55 + 0.1) * k * k * 1.8;
}
void fragment() { ALBEDO = col; ROUGHNESS = 0.8; }
