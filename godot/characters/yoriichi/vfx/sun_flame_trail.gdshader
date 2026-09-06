shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Original procedural art: no third-party textures or anime footage.
uniform vec4 ember_color : source_color = vec4(0.68, 0.018, 0.008, 1.0);
uniform vec4 flame_color : source_color = vec4(1.0, 0.22, 0.012, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.86, 0.24, 1.0);
uniform float emission_strength : hint_range(0.0, 3.0) = 0.75;
uniform float flow_speed : hint_range(0.0, 4.0) = 0.8;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
		mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}
void fragment() {
	// UV.x is accumulated blade travel: points aging out cannot retile the flame.
	float x = UV.x * 3.2 - TIME * flow_speed;
	float y = UV.y;
	float curl = sin(x * 3.1 + sin(x * 1.3) * 1.6) * 0.10;
	float detail = noise2(vec2(x * 2.2, y * 4.0));
	float edge = 0.60 + curl + pow(max(0.0, sin(x * 4.7 + y * 2.4)), 3.0) * 0.30 + (detail - 0.5) * 0.10;
	float body = smoothstep(0.015, 0.14, y) * (1.0 - smoothstep(edge - 0.035, edge, y));
	float tongue = pow(max(0.0, sin(x * 5.7 + y * 5.0)), 5.0);
	float gap = smoothstep(0.23, 0.34, y) * (1.0 - smoothstep(0.41, 0.56, y));
	body *= 1.0 - gap * tongue * 0.85;
	float core = (1.0 - smoothstep(0.19, 0.56, y - curl * 0.5)) * smoothstep(0.04, 0.18, y);
	float rim = smoothstep(edge - 0.20, edge - 0.025, y);
	vec3 ink = mix(flame_color.rgb, core_color.rgb, core);
	ink = mix(ink, ember_color.rgb, rim);
	ALBEDO = ink;
	EMISSION = ink * emission_strength * (0.12 + core * 0.88);
	ALPHA = body * COLOR.a;
}
