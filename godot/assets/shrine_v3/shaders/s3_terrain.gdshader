// 博麗神社 v3 近景地形（Poly Haven CC0 貼圖，見 assets/shrine_v3/tex/ph/SOURCES.json）。
// 遮罩（UV2 0..1 覆蓋近景）：mask_a = R 夯土／參道、G 林床、B 岩、A 草；mask_b = R 獸道碎石、G 濕暗、B 落花、A 苔。
// 法線：世界空間（頂部投影 T=+x、B=−z；岩用三向投影），不依賴網格切線。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://assets/shrine_v3/shaders/s3_canopy.gdshaderinc"

uniform sampler2D mask_a : filter_linear_mipmap, repeat_disable;
uniform sampler2D mask_b : filter_linear_mipmap, repeat_disable;
// mask_c（美術深化 2026-10-22）：R 踩踏量（壓實、草少、掃過）、G 楓落葉
uniform sampler2D mask_c : filter_linear_mipmap, repeat_disable;

uniform sampler2D grass_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D trail_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D trail_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float grass_tile = 2.0;     // 公尺／一格
uniform float forest_tile = 2.4;
uniform float dirt_tile = 2.2;
uniform float trail_tile = 2.6;
uniform float rock_tile = 5.0;
uniform float moss_tile = 3.0;
uniform vec3 grass_tint : source_color = vec3(0.92, 1.0, 0.86);
uniform vec3 forest_tint : source_color = vec3(0.95, 0.93, 0.90);
uniform vec3 dirt_tint : source_color = vec3(1.0, 0.97, 0.93);
uniform vec3 rock_tint : source_color = vec3(0.80, 0.82, 0.79);
uniform float rock_desat = 0.5;
uniform vec3 petal_col : source_color = vec3(0.98, 0.86, 0.90);
uniform vec3 leaf_col_a : source_color = vec3(0.62, 0.16, 0.07);    // 楓落葉（紅）
uniform vec3 leaf_col_b : source_color = vec3(0.58, 0.36, 0.12);    // 楓落葉（褐黃）
uniform float earth_var = 0.20;     // 夯土色差（0.5–3 m 尺度深淺、乾濕）
uniform float normal_strength = 0.85;
uniform float macro_var = 0.16;      // 5–20 m 尺度明暗
uniform float blend_sharp = 6.0;     // 高度混合銳利度
uniform vec4 near_rect = vec4(-78.0, -96.0, 78.0, 108.0);  // 近景範圍（x0, z0, x1, z1）
uniform float edge_blend_m = 10.0;   // 近景邊緣這麼寬的帶狀區漸變成中景林冠色（實體樹蓋住的地方）
uniform float albedo_gain = 0.86;    // 整體反照率（Poly Haven 原圖在 ACES＋強日照下偏亮）

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}
float fbm2(vec2 p) {
	return 0.5 * vnoise(p) + 0.3 * vnoise(p * 2.07 + 13.1) + 0.2 * vnoise(p * 4.13 + 7.7);
}

// 兩個尺度＋旋轉的取樣混合（抗重複）
vec4 tex2(sampler2D t, vec2 uv) {
	vec4 a = texture(t, uv);
	vec2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv * 0.37 + vec2(0.31, 0.77);
	vec4 b = texture(t, r);
	float m = smoothstep(0.35, 0.65, vnoise(uv * 0.21));
	return mix(a, b, m * 0.55);
}
// 法線圖以 RGTC 匯入（只有 RG）→ 一律只取 xy、z 重建
vec3 unpack_n(vec4 t) {
	vec2 xy = t.xy * 2.0 - 1.0;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}
vec3 nrm2(sampler2D t, vec2 uv) {
	vec3 a = unpack_n(texture(t, uv));
	vec2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv * 0.37 + vec2(0.31, 0.77);
	vec3 b = unpack_n(texture(t, r));
	// 旋轉後的切線方向也要轉回來
	b.xy = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * b.xy;
	float m = smoothstep(0.35, 0.65, vnoise(uv * 0.21));
	return normalize(mix(a, b, m * 0.55));
}

void fragment() {
	vec2 wp = v_wpos.xz;
	vec4 ma = texture(mask_a, UV2);
	vec4 mb = texture(mask_b, UV2);
	vec4 mc = texture(mask_c, UV2);
	// 細節雜訊擾動遮罩邊界（0.75 m 遮罩格看不出方格）
	float jit = (fbm2(wp * 1.7) - 0.5) * 0.35;

	vec4 cg = tex2(grass_d, wp / grass_tile);
	vec4 cf = tex2(forest_d, wp / forest_tile);
	vec4 cd = tex2(dirt_d, wp / dirt_tile);
	vec4 ct = tex2(trail_d, wp / trail_tile);
	vec4 cm = tex2(moss_d, wp / moss_tile);
	vec3 ng = nrm2(grass_n, wp / grass_tile);
	vec3 nf = nrm2(forest_n, wp / forest_tile);
	vec3 nd = nrm2(dirt_n, wp / dirt_tile);
	vec3 nt = nrm2(trail_n, wp / trail_tile);

	// 岩：三向投影
	vec3 bw = pow(abs(v_wnrm), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 rp = v_wpos / rock_tile;
	vec4 rx = texture(rock_d, rp.zy);
	vec4 ry = texture(rock_d, rp.xz);
	vec4 rz = texture(rock_d, rp.xy);
	vec4 cr = rx * bw.x + ry * bw.y + rz * bw.z;
	vec3 nrx = unpack_n(texture(rock_n, rp.zy));
	vec3 nry = unpack_n(texture(rock_n, rp.xz));
	vec3 nrz = unpack_n(texture(rock_n, rp.xy));
	// 各投影面的切線空間 → 世界（近似：whiteout）
	vec3 wrx = vec3(0.0, -nrx.y, nrx.x) * sign(v_wnrm.x);
	vec3 wry = vec3(nry.x, 0.0, -nry.y);
	vec3 wrz = vec3(nrz.x, -nrz.y, 0.0) * sign(v_wnrm.z);
	vec3 rock_dn = wrx * bw.x + wry * bw.y + wrz * bw.z;

	// 權重：遮罩 × 貼圖亮度當高度（高度混合）
	float wd = clamp(ma.r + jit * 0.6, 0.0, 1.0);
	float wf = clamp(ma.g - jit * 0.4, 0.0, 1.0);
	float wr = clamp(ma.b + jit * 0.3, 0.0, 1.0);
	float wg = clamp(ma.a - jit * 0.3, 0.0, 1.0);
	float wt = clamp(mb.r + jit * 0.5, 0.0, 1.0);
	float hd = dot(cd.rgb, vec3(0.333));
	float hf = dot(cf.rgb, vec3(0.333));
	float hg = dot(cg.rgb, vec3(0.333));
	float hr = dot(cr.rgb, vec3(0.333));
	float ht = dot(ct.rgb, vec3(0.333));
	vec4 hw = vec4(wd * (0.6 + hd), wf * (0.6 + hf), wr * (0.8 + hr), wg * (0.6 + hg));
	float hwt = wt * (0.6 + ht);
	float mx = max(max(max(hw.x, hw.y), max(hw.z, hw.w)), hwt);
	hw = max(hw - (mx - 0.35), vec4(0.0));
	hwt = max(hwt - (mx - 0.35), 0.0);
	hw = pow(hw, vec4(blend_sharp * 0.25));
	hwt = pow(hwt, blend_sharp * 0.25);
	float sw = hw.x + hw.y + hw.z + hw.w + hwt + 1e-4;
	hw /= sw;
	hwt /= sw;

	vec3 crs = mix(cr.rgb, vec3(dot(cr.rgb, vec3(0.299, 0.587, 0.114))), rock_desat);   // rock_face_03 偏橘褐：降彩度成風化灰岩
	// 夯土色差：大斑（~2 m）深淺＋小斑（~0.5 m）乾濕；踩踏處較亮、較平、彩度低（掃過、壓實）
	float ev1 = fbm2(wp * 0.45) - 0.5;
	float ev2 = fbm2(wp * 1.9 + 3.3) - 0.5;
	float dirt_dark = 0.88;     // 審圖 r1：夯土太亮、和白灰踏石同明度 → 整體壓暗，踩踏處不再提亮
	vec3 cdirt = cd.rgb * dirt_tint * dirt_dark * (1.0 + ev1 * earth_var * 1.6 + ev2 * earth_var * 0.6);
	cdirt = mix(cdirt, cdirt * vec3(0.84, 0.83, 0.82), smoothstep(0.05, 0.3, ev1) * 0.75);      // 陰濕的冷暗斑
	// 審圖 r2：前庭大尺度土色分區（mask_c.a，6–12 m）：暖赭（乾、外圍）↔ 冷褐（壓實、樹蔭、北半）
	cdirt *= mix(vec3(1.06, 1.0, 0.9), vec3(0.86, 0.85, 0.86), mc.a);
	float worn = mc.r;
	// 踩踏：壓實（略暗、略灰、細節少），不是曬白
	cdirt = mix(cdirt, mix(cdirt, vec3(dot(cdirt, vec3(0.333))), 0.25) * 0.94, worn * 0.6);
	vec3 col = cdirt * hw.x + cf.rgb * forest_tint * hw.y + crs * rock_tint * hw.z + cg.rgb * grass_tint * hw.w + ct.rgb * hwt;
	// 苔：林床與岩上的綠斑
	float moss = clamp(mb.a * (0.4 + 0.8 * fbm2(wp * 0.35)), 0.0, 1.0) * (1.0 - hw.x);
	col = mix(col, cm.rgb * vec3(0.85, 0.95, 0.75), moss * 0.65);
	// 濕暗（林下、谷側）
	col *= 1.0 - mb.g * 0.28;
	// 鋪石接地（mask_c.b）：石縫與石外 0.3 m 稍暗——石塊「坐進土裡」，石與土的邊界讀得出來
	col *= 1.0 - mc.b * 0.22;
	// 大尺度明暗
	float mv = fbm2(wp * 0.06) - 0.5;
	col *= 1.0 + mv * macro_var * 2.0;
	// 落花（細碎花瓣點）
	float pet = mb.b * smoothstep(0.62, 0.70, vnoise(wp * 9.0)) * smoothstep(0.3, 0.8, vnoise(wp * 1.3 + 5.0));
	col = mix(col, petal_col, clamp(pet, 0.0, 1.0) * 0.85);
	// 楓落葉（比花瓣大的斑點，紅／褐黃兩色）
	float lf = mc.g * smoothstep(0.58, 0.66, vnoise(wp * 5.3 + 11.0)) * smoothstep(0.25, 0.75, vnoise(wp * 0.9 + 2.0));
	vec3 lcol = mix(leaf_col_a, leaf_col_b, step(0.5, vnoise(wp * 2.7 + 7.0)));
	col = mix(col, lcol, clamp(lf, 0.0, 1.0) * 0.8);

	vec3 tn = nd * hw.x * (1.0 - worn * 0.45) + nf * hw.y + ng * hw.w + nt * hwt;
	vec3 n = normalize(v_wnrm + (vec3(tn.x, 0.0, -tn.y) + rock_dn * hw.z) * normal_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float rough = 0.94 - hw.z * 0.12 - mb.g * 0.15;
	col *= albedo_gain;
	// 近景邊緣 → 中景林冠（與 s3_vista 同一函式，接縫處顏色一致）
	float edge = min(min(v_wpos.x - near_rect.x, near_rect.z - v_wpos.x), min(v_wpos.z - near_rect.y, near_rect.w - v_wpos.z));
	float ew = 1.0 - smoothstep(0.0, edge_blend_m, edge);
	if (ew > 0.001) {
		vec3 cc;
		vec3 cn;
		float cr;
		s3_canopy(wp, v_wnrm, length(v_wpos - CAMERA_POSITION_WORLD), v_wpos.y, cc, cn, cr);
		col = mix(col, cc, ew);
		n = normalize(mix(n, normalize(v_wnrm + cn), ew));
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
