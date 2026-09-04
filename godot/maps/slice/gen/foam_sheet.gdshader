shader_type spatial;
// Falling water sheet (nappe). A continuous curtain of water is the WRONG job
// for particles: particles give you separated droplets, but a nappe is a
// coherent film. Scroll two noise layers at different speeds down a quad and
// the eye reads flow without any simulation cost.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, unshaded;

uniform vec3 water_tint : source_color = vec3(0.72, 0.82, 0.86);
uniform vec3 foam_tint : source_color = vec3(0.97, 0.99, 1.0);
uniform float flow_speed = 1.6;
uniform float streak_density = 7.0;
uniform float opacity = 0.62;
// Fades the top edge so the sheet emerges from the paddle instead of starting
// with a hard line.
uniform float top_fade = 0.18;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * flow_speed;
	// Two layers at different rates: one alone looks like a sliding texture.
	float n1 = noise(vec2(uv.x * streak_density, uv.y * streak_density * 0.5 - t));
	float n2 = noise(vec2(uv.x * streak_density * 2.1 + 3.7, uv.y * streak_density - t * 1.7));
	float streak = n1 * 0.6 + n2 * 0.4;

	// Foam concentrates at the bottom where the sheet breaks up.
	float lower = smoothstep(0.35, 1.0, uv.y);
	float foam = smoothstep(0.45, 0.85, streak) * lower;

	vec3 col = mix(water_tint, foam_tint, foam);
	float a = opacity * mix(0.55, 1.0, streak);
	a *= smoothstep(0.0, top_fade, uv.y);

	ALBEDO = col;
	ALPHA = a;
}
