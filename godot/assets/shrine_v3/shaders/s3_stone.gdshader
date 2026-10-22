// 博麗神社 v3：石材（花崗岩＋苔）。上表面與近地處長苔；三向投影（物件空間）給沒有好 UV 的雕像用。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D stone_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.86, 0.85, 0.82);
uniform float tile = 1.2;
uniform float moss_tile = 0.9;
uniform float moss_amount = 0.45;
uniform float moss_low_m = 0.45;   // 物件底部這麼高以內苔較多
uniform bool triplanar = false;

varying vec3 v_lpos;
varying vec3 v_lnrm;
varying vec3 v_wnrm;

void vertex() {
	v_lpos = VERTEX;
	v_lnrm = NORMAL;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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

vec4 tri(sampler2D t, vec3 p, vec3 n, float s) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(t, p.zy / s) * w.x + texture(t, p.xz / s) * w.y + texture(t, p.xy / s) * w.z;
}

void fragment() {
	vec4 c;
	vec3 nmap;
	if (triplanar) {
		c = tri(stone_d, v_lpos, v_lnrm, tile);
		nmap = vec3(0.5, 0.5, 1.0);
	} else {
		c = texture(stone_d, UV / tile);
		nmap = texture(stone_n, UV / tile).xyz;
	}
	vec3 col = c.rgb * tint * COLOR.rgb;
	float up = smoothstep(0.35, 0.9, v_wnrm.y);
	float low = 1.0 - smoothstep(0.0, moss_low_m, v_lpos.y);
	float nz = vn(v_lpos.xz * 7.0 + v_lpos.y * 3.0) * 0.6 + vn(v_lpos.xz * 23.0) * 0.4;
	float m = clamp((up * 0.8 + low * 0.7) * moss_amount * 1.6 - (1.0 - nz) * 0.9, 0.0, 1.0);
	vec3 mc = tri(moss_d, v_lpos, v_lnrm, moss_tile).rgb * vec3(0.78, 0.9, 0.62);
	col = mix(col, mc, m);
	ALBEDO = col;
	ROUGHNESS = mix(0.82, 0.95, m);
	NORMAL_MAP = mix(nmap, vec3(0.5, 0.5, 1.0), m * 0.6);
}
