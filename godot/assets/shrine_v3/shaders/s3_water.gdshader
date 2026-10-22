// 博麗神社 v3：池塘／手水盤水面。深淺依深度差，程序細波法線，菲涅耳靠引擎反射（低粗糙度）。
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 shallow_col : source_color = vec3(0.22, 0.27, 0.20);
uniform vec3 deep_col : source_color = vec3(0.025, 0.055, 0.050);
uniform float depth_m = 1.1;         // 這個深度以上就是深色
uniform float edge_fade_m = 0.12;    // 岸邊透明過渡
uniform float wave_scale = 1.6;
uniform float wave_speed = 0.35;
uniform float wave_strength = 0.35;
uniform float clarity = 0.55;        // 0＝不透明、1＝很清
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}
float waves(vec2 p, float t) {
	return vn(p * wave_scale + vec2(t, t * 0.6)) * 0.6 + vn(p * wave_scale * 2.3 - vec2(t * 0.8, -t * 0.5)) * 0.4;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = v_wpos.xz;
	float e = 0.06;
	float h0 = waves(p, t);
	float hx = waves(p + vec2(e, 0.0), t);
	float hz = waves(p + vec2(0.0, e), t);
	vec3 n = normalize(vec3(-(hx - h0) / e * wave_strength * 0.12, 1.0, -(hz - h0) / e * wave_strength * 0.12));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float zd = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, zd, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	vpos.xyz /= vpos.w;
	float thick = max(-vpos.z - (-VERTEX.z), 0.0);
	float dk = clamp(thick / depth_m, 0.0, 1.0);
	vec3 water = mix(shallow_col, deep_col, dk);
	vec2 refr_uv = SCREEN_UV + n.xz * 0.012 * (1.0 - dk);
	vec3 bg = textureLod(screen_tex, refr_uv, 0.0).rgb;
	vec3 col = mix(water, bg * mix(vec3(0.75, 0.85, 0.75), water * 3.0, dk), clarity * (1.0 - dk));
	ALBEDO = col;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = clamp(thick / edge_fade_m, 0.0, 1.0);
}
