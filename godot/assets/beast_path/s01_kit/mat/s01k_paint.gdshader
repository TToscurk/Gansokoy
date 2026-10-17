// 獸道 S01 R6：朱漆木構（鳥居）材質。S01 專用；共用 shader 不動。
// 頂點資料（assets/beast_path/s01_kit/src/build_s01_shrine.py）：
//   COLOR.rgb ＝ 塗色（sRGB；朱／黑漆／素木，已含低頻色斑與朝上面的日曬褪色）
//   UV        ＝ 木紋座標（公尺）：u 繞周／橫向、v 沿構件
//   UV2.x     ＝ 材質（0 朱漆、0.25 黑漆、0.5 素木）；UV2.y ＝ 木紋方向（0 直立構件、1 水平構件）
// 風化：沿木紋的細條紋（漆的刷痕與龜裂）、局部掉漆露出暗木、柱腳的泥濺與濕痕、朝上面少量地衣。
// instance uniform ground_y＝這座鳥居腳下的地面高度（世界座標）。
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 grime_col : source_color = vec3(0.20, 0.155, 0.11);
uniform vec3 bare_wood : source_color = vec3(0.30, 0.22, 0.15);
uniform vec3 lichen_col : source_color = vec3(0.42, 0.45, 0.33);
uniform float tone = 1.0;
instance uniform float ground_y = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

vec3 s2l(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = s2l(clamp(COLOR.rgb, vec3(0.0), vec3(1.0)));
	float mat = UV2.x;
	bool hor = UV2.y > 0.5;
	// 木紋座標：沿構件慢、橫向快 → 細長條紋
	vec2 g = vec2(UV.x * 5.0, UV.y * 0.45);
	vec4 n1 = texture(noise_tex, g * 0.5);
	vec4 n3 = texture(noise_tex, vec2(UV.x * 23.0, UV.y * 1.7));
	vec4 n2 = texture(noise_tex, wpos.xz * 0.45 + vec2(wpos.y * 0.23, -wpos.y * 0.11));
	float streak = n1.b * 0.6 + n3.g * 0.4;
	vec3 alb = base * mix(0.92, 1.05, streak) * mix(0.94, 1.04, n2.g);
	// 掉漆：朱漆最多、黑漆少、素木不適用
	float wear_k = mat < 0.12 ? 1.0 : (mat < 0.37 ? 0.55 : 0.0);
	vec4 nc = texture(noise_tex, vec2(UV.x * 2.4, UV.y * 2.4) + 0.5);      // 等向的小剝落（不沿木紋拉長）
	float wear = smoothstep(0.74, 0.86, n2.r * 0.5 + nc.b * 0.6) * wear_k;
	alb = mix(alb, s2l(bare_wood) * mix(0.8, 1.1, n3.r), wear * 0.5);
	// 柱腳：泥濺＋濕痕（離地 0–1.3 m）
	float above = wpos.y - ground_y;
	float grime = 1.0 - smoothstep(0.15, 1.35, above + (n2.b - 0.5) * 0.5 + (n3.a - 0.5) * 0.2);
	alb = mix(alb, s2l(grime_col), grime * 0.55);
	// 構件下緣的雨垂れ（直立構件、上方 3 m 以上的部分略暗）
	vec3 N = normalize(wnrm);
	float drip = hor ? 0.0 : smoothstep(2.6, 4.2, above) * smoothstep(0.6, 0.9, n1.a) * 0.10;
	alb *= 1.0 - drip;
	// 朝上的面：少量灰綠地衣
	float up = smoothstep(0.55, 0.92, N.y);
	float lich = up * smoothstep(0.52, 0.72, n2.a * 0.7 + n3.r * 0.4);
	alb = mix(alb, s2l(lichen_col) * 0.55, lich * 0.45);
	ALBEDO = alb * tone;
	ROUGHNESS = mat < 0.12 ? mix(0.58, 0.82, streak + wear * 0.4) : (mat < 0.37 ? mix(0.42, 0.7, n2.r) : 0.88);
	SPECULAR = mat < 0.37 ? 0.42 : 0.25;
}
