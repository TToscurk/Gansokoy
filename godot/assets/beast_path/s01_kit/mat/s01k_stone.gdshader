// 獸道 S01 R6：加工石（石燈籠、鳥居台座）。S01 專用。
// 天然岩用 s01k_rock（lichen_rock 貼圖，暗而斑駁）；鑿過的花崗岩面比較平、淺灰，帶細的黑白斑、雨水的縱向汙痕、局部苔。
// 頂點色與 s01k_rock 相同語意（s01_dress.gd rock_colors 依地形算）：COLOR.r＝苔、COLOR.g＝環境遮蔽、COLOR.b＝色差、COLOR.a＝腳邊泥土。
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 stone_a : source_color = vec3(0.64, 0.63, 0.59);
uniform vec3 stone_b : source_color = vec3(0.53, 0.52, 0.49);
uniform vec3 stain_col : source_color = vec3(0.33, 0.32, 0.29);
uniform vec3 moss_col : source_color = vec3(0.30, 0.37, 0.13);
uniform vec3 foot_col : source_color = vec3(0.27, 0.22, 0.16);
uniform float tone = 1.0;

varying vec3 wpos;
varying vec3 wnrm;

vec4 tri(vec3 p, vec3 tb, float k) {
	return texture(noise_tex, p.zy * k) * tb.x + texture(noise_tex, p.xz * k + 0.31) * tb.y + texture(noise_tex, p.xy * k + 0.67) * tb.z;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 N = normalize(wnrm);
	vec3 tb = pow(abs(N), vec3(4.0));
	tb /= (tb.x + tb.y + tb.z);
	vec4 big = tri(wpos, tb, 0.35);
	vec4 mid = tri(wpos, tb, 1.6);
	vec4 fine = tri(wpos, tb, 7.0);
	vec3 alb = mix(stone_b, stone_a, clamp(big.r * 0.8 + COLOR.b * 0.4 - 0.1, 0.0, 1.0));
	alb *= mix(0.88, 1.08, mid.g);
	// 花崗岩的細斑：少量暗粒、少量亮粒
	alb *= 1.0 - 0.22 * smoothstep(0.70, 0.85, fine.b);
	alb *= 1.0 + 0.10 * smoothstep(0.75, 0.9, fine.r);
	// 雨水汙痕：直立面上的縱向暗帶（世界 Y 拉長的雜訊）
	vec4 st = texture(noise_tex, vec2((wpos.x + wpos.z) * 2.2, wpos.y * 0.35));
	float stain = smoothstep(0.55, 0.85, st.g) * (1.0 - abs(N.y));
	alb = mix(alb, stain_col, stain * 0.35);
	// 朝下的面（笠の裏、中台の下）：灰黑
	alb = mix(alb, stain_col * 0.8, smoothstep(0.2, 0.8, -N.y) * 0.35);
	// 苔與腳邊泥土
	float moss = clamp(COLOR.r * (0.7 + 0.6 * mid.b), 0.0, 1.0);
	alb = mix(alb, moss_col * mix(0.75, 1.2, fine.g), smoothstep(0.15, 0.6, moss) * 0.85);
	alb = mix(alb, foot_col, COLOR.a * 0.55);
	alb *= mix(0.45, 1.0, COLOR.g);
	ALBEDO = alb * tone;
	ROUGHNESS = mix(0.82, 0.95, moss);
	SPECULAR = 0.3;
}
