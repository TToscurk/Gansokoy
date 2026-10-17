// 獸道 S04 天然地表（V1.1；V1.2 G：效能削減——nrh 非等向→三線性、啟用層門檻 0.03、遠處反平鋪只對主要層）。
// 衍生自人間之里 P7 ground.gdshader 的分層混合法：同一組 7 層 CC0 Texture2DArray（Poly Haven，唯讀重用，不改 _matlib）、
// 高度混合（nrh.b）讓土石交界不成直線、遠處雙尺度取樣壓平鋪重複。層序固定：
//   0 grass 1 street(不用) 2 trodden 3 gravel 4 mud 5 rock 6 forest
// 頂點資料（terrain_generator.build_tile 的 ground 模式）：
//   COLOR＝(trodden, gravel, mud, rock)；UV＝(forest, wet)；UV2＝(moss, 保留)；CUSTOM0.rgb＝白模頂點色（S03 接縫淡出用）。
//   草＝1 − Σ（剩餘）。
// 與 P7 不同的地方：
//   · 岩層用三平面投影（崖面 79° 時 XZ 投影會被拉成條紋）＋坡度修正岩權重（頂點 1 m 解析度畫不準崖緣）；
//   · 苔：綠色絨狀斑（噪聲驅動），偏愛上向面與濕處；濕度壓暗＋降粗糙度；
//   · 紅葉：古楓周圍的林床落葉帶暖紅（落葉的來源有理由）；
//   · 接縫：S04 南端 seam_z0→seam_z1 之間由白模頂點色淡入貼圖細節，與尚未改材質的 S03 無縫銜接
//     （S03 改材質後把 seam 兩值設成同一點即可關閉）。
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrh_arr : filter_linear_mipmap, repeat_enable;          // V1.2 G：非等向 → 三線性（法線／高度；albedo 仍非等向）
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float ground_k = 0.26;
uniform float seam_z0 = -340.0;
uniform float seam_z1 = -366.0;
uniform vec4 autumn = vec4(4.0, -386.0, 18.0, 1.0);          // xz＝古楓落葉帶中心、z＝半徑、w＝強度
uniform vec3 moss_col : source_color = vec3(0.20, 0.32, 0.09);
uniform float wet_dark = 0.42;
uniform float bump_amp = 0.11;                // V1.2：平地的低頻微起伏（只動法線，不動高度、不動碰撞）
uniform float cliff_tone = 0.85;              // V1.3：陡崖面（三平面岩層）的明度——對齊 bp_rock 岩片（tone 0.92＋頂點 AO）；V1.2 的崖壁在岩柱間的縫裡露出一條條淺色（審圖：「柱子站在一面淺色的坡前」）。1.0＝V1.2

const float TILE[7] = float[7](2.51, 2.07, 2.11, 2.16, 1.3, 2.0, 1.5);
const vec2 ROUGH[7] = vec2[7](vec2(0.82, 0.98), vec2(0.8, 0.96), vec2(0.82, 0.97), vec2(0.62, 0.92), vec2(0.45, 0.85), vec2(0.7, 0.95), vec2(0.85, 0.98));
const float NSTR[7] = float[7](0.9, 0.8, 0.8, 1.0, 0.7, 1.0, 0.8);
const float HB = 0.55;
const float HB_DEPTH = 0.22;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 wa;
varying vec4 wb;
varying vec3 fbc;

vec3 s2l(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

vec3 l2s(vec3 c) {
	return mix(vec3(1.055) * pow(c, vec3(1.0 / 2.4)) - vec3(0.055), c * 12.92, lessThan(c, vec3(0.0031308)));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wa = COLOR;
	wb = vec4(UV, UV2);
	fbc = CUSTOM0.rgb;
}

void fragment() {
	vec3 P = wpos;
	vec2 p = P.xz;
	vec3 N = normalize(wnrm);
	vec2 dpx = dFdx(p);
	vec2 dpy = dFdy(p);
	vec3 dPx = dFdx(P);
	vec3 dPy = dFdy(P);
	vec4 nb = texture(noise_tex, p / 61.0);
	vec4 nm = texture(noise_tex, p / 13.0 + vec2(0.31, 0.77));
	float nf = texture(noise_tex, p / 3.7 + vec2(0.53, 0.11)).b;
	float nvf = texture(noise_tex, p / 1.9 + vec2(0.11, 0.73)).b;

	// ---- 權重（頂點 1 m 解析度 → 用噪聲推擠交界，不留格線）
	float pert = (nm.g - 0.5) * 1.1 + (nf - 0.5) * 0.45;
	vec4 a = clamp(wa + pert * wa * (1.0 - wa) * 2.2, 0.0, 1.0);
	float w_for = clamp(wb.x + pert * wb.x * (1.0 - wb.x) * 2.2, 0.0, 1.0);
	float wet = clamp(wb.y + (nm.b - 0.5) * 0.25, 0.0, 1.0);
	float moss_w = wb.z;
	// 崖面雨痕：垂直拉長的暗流痕（只在近垂直的面）；濕處沿著流痕更濕
	float side_k = 1.0 - smoothstep(0.35, 0.85, N.y);
	float streak = texture(noise_tex, vec2(P.x + P.z, P.y * 0.10) * 0.9 + vec2(0.27, 0.0)).b;
	wet = clamp(wet * mix(0.70, 1.15, smoothstep(0.35, 0.75, streak) * side_k + (1.0 - side_k) * 0.5), 0.0, 1.0);
	float w[7] = float[7](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
	w[2] = a.r;
	w[3] = a.g;
	w[4] = a.b;
	w[5] = a.a;
	w[6] = w_for;
	// 坡度修正岩權重：崖緣在 1 m 網格上畫不準，法線是連續的
	float slope_rock = smoothstep(0.20, 0.42, 1.0 - N.y);
	float rk = max(w[5], slope_rock);
	float others = w[2] + w[3] + w[4] + w[6];
	float scale_o = (1.0 - rk) / max(others, 1e-4);
	if (others > 1.0 - rk) {
		w[2] *= scale_o; w[3] *= scale_o; w[4] *= scale_o; w[6] *= scale_o;
	}
	w[5] = rk;
	float s = w[2] + w[3] + w[4] + w[5] + w[6];
	w[0] = max(1.0 - s, 0.0);

	// ---- 三平面（只在岩層、且面夠陡時）
	vec3 tb = pow(abs(N), vec3(4.0));
	tb /= (tb.x + tb.y + tb.z);
	bool tri = (w[5] > 0.02) && (tb.y < 0.86);

	vec4 nv[7];
	float sc[7];
	float smax = -10.0;
	for (int i = 0; i < 7; i++) {
		sc[i] = -10.0;
		nv[i] = vec4(0.5, 0.5, 0.5, 0.0);
		if (w[i] > 0.03) {                                    // V1.2 G：0.015 → 0.03（<3 % 的層不取樣，剩下的權重由 bsum 正規化）
			float T = TILE[i];
			vec4 q = textureGrad(nrh_arr, vec3(p / T, float(i)), dpx / T, dpy / T);
			if (i == 5 && tri) {
				vec4 qx = textureGrad(nrh_arr, vec3(vec2(P.z, P.y) / T, 5.0), vec2(dPx.z, dPx.y) / T, vec2(dPy.z, dPy.y) / T);
				vec4 qz = textureGrad(nrh_arr, vec3(vec2(P.x, P.y) / T, 5.0), vec2(dPx.x, dPx.y) / T, vec2(dPy.x, dPy.y) / T);
				q = q * tb.y + qx * tb.x + qz * tb.z;
			}
			nv[i] = q;
			sc[i] = w[i] + q.b * HB;
			smax = max(smax, sc[i]);
		}
	}
	float bw[7];
	float bsum = 0.0;
	for (int i = 0; i < 7; i++) {
		bw[i] = max(sc[i] - (smax - HB_DEPTH), 0.0);
		bsum += bw[i];
	}
	bsum = max(bsum, 1e-5);
	float fd = smoothstep(14.0, 55.0, length(P - CAMERA_POSITION_WORLD));
	vec3 alb = vec3(0.0);
	vec3 nw = vec3(0.0);
	float rough = 0.0;
	for (int i = 0; i < 7; i++) {
		if (bw[i] > 0.0) {
			float f = bw[i] / bsum;
			float T = TILE[i];
			vec3 c = textureGrad(albedo_arr, vec3(p / T, float(i)), dpx / T, dpy / T).rgb;
			if (i == 5 && tri) {
				vec3 cx = textureGrad(albedo_arr, vec3(vec2(P.z, P.y) / T, 5.0), vec2(dPx.z, dPx.y) / T, vec2(dPy.z, dPy.y) / T).rgb;
				vec3 cz = textureGrad(albedo_arr, vec3(vec2(P.x, P.y) / T, 5.0), vec2(dPx.x, dPx.y) / T, vec2(dPy.x, dPy.y) / T).rgb;
				c = c * tb.y + cx * tb.x + cz * tb.z;
				c *= vec3(1.07, 1.0, 0.86);              // 與 bp_rock 同一個暖色校正（崖面地形和岩片是同一種石頭）
				c *= mix(1.0, cliff_tone, 1.0 - tb.y);   // V1.3：只壓陡面（tb.y＝上向投影比重）
			}
			if (fd > 0.0 && f > 0.26) {                           // V1.2 G：遠處反平鋪只對佔 26 % 以上的層做（次要層的重複看不出，省下一半以上的遠處 albedo 取樣）
				vec2 uv2 = (p / T) * 0.29 + vec2(0.37, 0.61);
				vec3 c2 = textureGrad(albedo_arr, vec3(uv2, float(i)), dpx / T * 0.29, dpy / T * 0.29).rgb;
				c = mix(c, (c + c2) * 0.5, fd);
			}
			alb += c * f;
			// 法線：平面層同 P7；岩層三平面用 UDN 重定向
			vec2 t = (nv[i].rg * 2.0 - 1.0) * NSTR[i];
			vec3 n_i = normalize(vec3(t.x, 0.0, -t.y) + N);
			if (i == 5 && tri) {
				vec3 nx_ = normalize(vec3(N.x, t.y + N.y, t.x + N.z));
				vec3 nz_ = normalize(vec3(t.x + N.x, t.y + N.y, N.z));
				n_i = normalize(n_i * tb.y + nx_ * tb.x + nz_ * tb.z);
			}
			nw += n_i * f;
			rough += mix(ROUGH[i].x, ROUGH[i].y, clamp(0.5 + (nf - 0.5) * 0.8, 0.0, 1.0)) * f;
		}
	}
	nw = normalize(nw);
	// ---- V1.2 微起伏：0.5~3 m 尺度的緩丘與淺窪（兩個頻率，噪聲高度的梯度 → 法線）。
	//      只加在平地的土／泥／草／落葉層，岩層與陡面不加；戰鬥圓平坦度（碰撞）完全不受影響。
	// V1.3：修「全場同向斜紋」。舊版用前向差分、步長 0.30 m（第二層 1.7 m 尺度＝90 texel，雜訊特徵只有 30–80 texel），
	//      差分跨過整個特徵 → 法線一律朝 (+x,+z) 偏 → 平行斜紋（隔離實驗：灰反照率下 0.3–1.5 m 頻帶能量
	//      全部法線 558.7k、只留法線貼圖 7.6k、只留舊微起伏 561.6k）。改成中心差分＋1.5 texel 步長；
	//      兩層都用 R 通道（G 通道的雲塊帶方向性），各自旋轉 +30°／−60°（互相正交，把殘留的方向性抵掉），
	//      第二層放大到 11 m（1.7 m 那層正是條紋的尺度）。取樣 6 → 8 次，只在平地。
	{
		float flat_w = (w[0] + w[2] + w[3] + w[4] + w[6]) * smoothstep(0.80, 0.96, N.y);
		if (flat_w > 0.02) {
			const mat2 BRA = mat2(vec2(0.866, 0.5), vec2(-0.5, 0.866));
			const mat2 BRB = mat2(vec2(0.5, -0.866), vec2(0.866, 0.5));
			const float BE = 1.5 / 512.0;
			vec2 q0 = (BRA * p) / 4.6 + vec2(0.13, 0.41);
			vec2 q1 = (BRB * p) / 11.0 + vec2(0.71, 0.29);
			vec2 g0 = vec2(texture(noise_tex, q0 + vec2(BE, 0.0)).r - texture(noise_tex, q0 - vec2(BE, 0.0)).r,
				texture(noise_tex, q0 + vec2(0.0, BE)).r - texture(noise_tex, q0 - vec2(0.0, BE)).r) / (2.0 * BE * 4.6);
			vec2 g1 = vec2(texture(noise_tex, q1 + vec2(BE, 0.0)).r - texture(noise_tex, q1 - vec2(BE, 0.0)).r,
				texture(noise_tex, q1 + vec2(0.0, BE)).r - texture(noise_tex, q1 - vec2(0.0, BE)).r) / (2.0 * BE * 11.0);
			vec2 g = g0 * BRA + (g1 * BRB) * 2.2;          // 梯度轉回世界 xz（v * M ＝ Mᵀ v）
			vec3 nbump = normalize(vec3(-g.x * bump_amp * 0.9, 1.0, -g.y * bump_amp * 0.9));
			nw = normalize(nw + vec3(nbump.x, 0.0, nbump.z) * clamp(flat_w, 0.0, 1.0));
		}
	}

	// ---- 巨觀明暗（兩個尺度）：不要整片同一個亮度
	float macro = mix(0.84, 1.14, nb.r) * mix(0.93, 1.07, nm.r);
	alb *= macro;
	// V1.2：壓實土／泥的色相漂移——同一片土不是同一個顏色（乾高處偏暖亮、窪濕處偏冷暗，幅度 ±7 %）
	float dirt_f = (bw[2] + bw[4]) / bsum;
	alb *= mix(vec3(1.0), mix(vec3(0.93, 0.95, 1.0), vec3(1.07, 1.02, 0.93), nm.g), dirt_f * 0.9);
	// 乾草斑偏黃
	float g0 = bw[0] / bsum;
	alb = mix(alb, alb * vec3(1.09, 1.03, 0.84), g0 * smoothstep(0.55, 0.85, nb.a) * 0.55);

	// ---- 古楓的紅葉（只染林床／落葉層）
	float am = (1.0 - smoothstep(autumn.z * 0.35, autumn.z, distance(p, autumn.xy) + (nm.g - 0.5) * 7.0)) * autumn.w;
	float f6 = bw[6] / bsum;
	alb = mix(alb, alb * vec3(1.55, 0.72, 0.36), clamp(am * f6 * 1.2 + am * 0.18 * g0, 0.0, 0.8) * mix(0.55, 1.0, nvf));

	// ---- 濕度：壓暗＋降粗糙度；崖面另有乾的雨痕（不濕的崖也不是一整片同色）
	alb *= mix(1.0, wet_dark, wet);
	alb *= 1.0 - 0.26 * smoothstep(0.52, 0.80, streak) * side_k * w[5];

	// ---- 苔：噪聲成絨狀斑，偏愛上向面；坡太陡（崖面）也有，但稀疏
	float mm = moss_w * (0.35 + 0.95 * nm.g) + (nvf - 0.5) * 0.4 * moss_w;
	float moss_m = smoothstep(0.30, 0.62, mm) * smoothstep(0.05, 0.65, nw.y + (nm.g - 0.5) * 0.3);
	vec3 mcol = moss_col * mix(0.62, 1.3, nvf);
	alb = mix(alb, mcol * 3.4 * (0.4 + 0.6 * dot(alb, vec3(0.333))), moss_m * 0.82);
	rough = mix(rough, 0.97, moss_m);
	rough = rough * mix(1.0, 0.62, wet);

	// ---- 輸出（含 S03 接縫淡出）
	float dk = clamp((seam_z0 - P.z) / max(seam_z0 - seam_z1, 1.0), 0.0, 1.0);
	dk = dk * dk * (3.0 - 2.0 * dk);
	vec3 tex_lin = alb * ground_k;
	vec3 fb_lin = s2l(fbc);
	ALBEDO = mix(fb_lin, tex_lin, dk);
	vec3 Nf = normalize(mix(N, nw, dk));
	NORMAL = normalize((VIEW_MATRIX * vec4(Nf, 0.0)).xyz);
	ROUGHNESS = mix(1.0, clamp(rough, 0.05, 1.0), dk);
	SPECULAR = mix(0.15, 0.3 + 0.2 * wet, dk);
}
