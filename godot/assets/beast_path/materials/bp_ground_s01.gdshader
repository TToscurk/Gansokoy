// 獸道 S01 入口林道地表（R1）。
// 衍生自 S04 的 bp_ground.gdshader（同一組 P7 7 層 CC0 Texture2DArray、分層高度混合、三平面岩層、反平鋪、V1.3 的微起伏修正），
// 但是『獨立的材質入口』：不改 bp_ground.*，S04 的畫面因此不可能被這份影響（isolation.protected_files 會驗）。
// 層序固定：0 grass 1 street(不用) 2 trodden 3 gravel 4 mud 5 rock 6 forest
// 頂點資料（terrain_generator.build_tile 的 S01 模式；與 S04 同一套通道）：
//   COLOR＝(trodden, gravel, mud, rock)；UV＝(forest, wet)；UV2＝(moss, 路中心側向距離 m，右為正)；CUSTOM0.rgb＝白模頂點色（接縫淡出用）。草＝1 − Σ（剩餘）。
// 與 S04 不同的地方：
//   · 接縫在北端（z＝−100，和仍是白模的 S02 共用邊界列）：北端 seam_z0→南 seam_z1 之間由白模色淡入貼圖細節（S04 的接縫在南端，方向相反）；
//   · 村緣段的車轍：兩條淺凹痕（只動法線與一點明度），範圍由 rut_z 淡出，沿路向有斷續；
//   · 沒有古楓紅葉與瀑布濕岩（S01 沒有）；
//   · 草斑偏黃的幅度加大（S01 的草地是日照下的開闊草地，不能是一整片均勻的綠）。
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrh_arr : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float ground_k = 0.26;
uniform float seam_z0 = -100.0;              // 北端（和 S02 白模銜接）：完全是白模色
uniform float seam_z1 = -74.0;               // 往南 26 m 淡入完整貼圖細節
uniform vec3 moss_col : source_color = vec3(0.20, 0.32, 0.09);
uniform float wet_dark = 0.42;
uniform float bump_amp = 0.11;
uniform float cliff_tone = 0.85;
uniform float rut_amp = 0.55;                // 車轍凹痕的法線強度（0＝沒有）
uniform vec2 rut_z = vec2(-34.0, -54.0);     // 車轍的範圍：z > rut_z.x 全強度，淡出到 rut_z.y 為 0（村緣到鳥居前）
uniform float rut_gap = 0.78;                // 兩條轍距路中心的距離（m）
uniform vec2 slope_rock_rng = vec2(0.34, 0.52);      // 陡坡→岩層的坡度範圍（1−N.y）：0.34≈48.7°開始、0.52≈61°全岩。S04 用 0.20–0.42（≈37°起）；沿用到 S01 會把 19 % 的面積（緊貼谷底的一圈谷壁）染成灰岩牆
uniform vec2 bank_rng = vec2(0.07, 0.28);            // 中陡坡（≈26°–46°）不是裸岩而是長了草、蓋著落葉的土坡：forest 層（落葉）漸增
uniform vec4 gain_a = vec4(1.0, 1.0, 1.0, 1.0);      // 各層的亮度增益：x＝草、y＝壓實土、z＝礫、w＝泥（S01 的礫與落葉貼圖比草地亮／暗很多，要拉回同一個明度級）
uniform vec2 gain_b = vec2(1.0, 1.0);                // x＝岩、y＝林床落葉

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
uniform float far_steep_fix = 0.0;      // R2：遠景細節層（xz 投影）只用在較平的地面；陡坡上 xz 投影會被拉長成縱向條紋。R1＝0（與 R1 相同）
varying float soil_v;     // R2 土袋（1−CUSTOM0.a）：谷壁上植物扎根的土。R1／沒有土袋＝0，畫面與 R1 相同
// ---- R3 地表自然化（r3_on＝0：R1／R2 完全不進這些分支，畫面不變）
//   兩層 S01 專用貼圖（專案既有、CC0）：7＝林床落葉（Poly Haven forest_leaves_02）、8＝苔地（aerial_grass_rock）。不改共用貼圖陣列。
//   頂點 CUSTOM1＝(落葉, 苔地, 乾, 潤)。草（短草＝第 0 層、粗草＝第 6 層）降飽和；乾處偏枯黃、窪處偏潤綠。
uniform float r3_on = 0.0;
uniform sampler2D litter_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D litter_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mossg_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mossg_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec2 r3_tile = vec2(2.3, 3.1);                 // 落葉、苔地的貼圖尺寸（m）
uniform vec2 gain_c = vec2(0.82, 0.78);                // 落葉、苔地的亮度增益（拉回與其他層同一明度級）
uniform float grass_desat = 0.20;                      // 草（第 0、6 層）的去飽和
uniform vec3 dry_tint = vec3(1.15, 1.04, 0.72);
uniform vec3 lush_tint = vec3(0.86, 0.96, 0.84);
uniform float litter_desat = 0.18;                     // 落葉貼圖偏橘：稍微降飽和
uniform float r3_far_rot = 0.62;                       // R3：遠景細節層的 UV 旋轉（rad），打散與近景同向的平鋪
varying vec4 r3v;

vec3 s2l(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wa = COLOR;
	wb = vec4(UV, UV2);
	fbc = CUSTOM0.rgb;
	soil_v = 1.0 - CUSTOM0.a;
	r3v = (r3_on > 0.5) ? CUSTOM1 : vec4(0.0);
}

void fragment() {
	vec3 P = wpos;
	vec2 p = P.xz;
	vec3 N = normalize(wnrm);
	vec2 dpx = dFdx(p);
	vec2 dpy = dFdy(p);
	vec3 dPx = dFdx(P);
	vec3 dPy = dFdy(P);
	vec2 doff = vec2(dFdx(wb.w), dFdy(wb.w));        // 側向距離的螢幕導數（車轍法線用；導數一律在分支外取）
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
	float off = wb.w;
	float w[9] = float[9](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
	w[2] = a.r;
	w[3] = a.g;
	w[4] = a.b;
	w[5] = a.a;
	w[6] = w_for;
	if (r3_on > 0.5) {
		w[7] = clamp(r3v.r + pert * r3v.r * (1.0 - r3v.r) * 2.2, 0.0, 1.0);     // R3 林床落葉
		w[8] = clamp(r3v.g + pert * r3v.g * (1.0 - r3v.g) * 2.2, 0.0, 1.0);     // R3 苔地
	}
	// 坡度修正岩權重（谷壁的灰岩）：崖緣在 1 m 網格上畫不準，法線是連續的
	float steep = 1.0 - N.y;
	// 谷壁不能是『一整面同一種材質』：用兩個尺度的噪聲把坡面分塊（29 m 大塊＋9 m 小塊）。
	float pa = texture(noise_tex, p / 29.0 + vec2(0.37, 0.58)).g;
	float pb = texture(noise_tex, p / 9.0 + vec2(0.81, 0.12)).b;
	float patch_k = smoothstep(0.28, 0.72, pa * 0.65 + nb.r * 0.35);                  // 0＝草坡、1＝落葉土坡（大塊交錯）
	float rock_patch = smoothstep(0.35, 0.75, pa * 0.4 + pb * 0.6);                   // 岩面只在局部陡面成塊
	float soil = clamp(soil_v, 0.0, 1.0);                                              // R2：土袋裡沒有『陡坡→岩／落葉土坡』，交給頂點通道（草＋落葉＋苔）
	float slope_rock = smoothstep(slope_rock_rng.x, slope_rock_rng.y, steep) * mix(0.35, 1.0, rock_patch) * (1.0 - 0.92 * soil);
	float bank = smoothstep(bank_rng.x, bank_rng.y, steep) * (1.0 - slope_rock) * (1.0 - 0.75 * soil);
	w[6] = clamp(w[6] + bank * mix(0.15, 0.95, patch_k), 0.0, 1.0);                   // 土坡：落葉層（取代草）成塊出現
	float foot = smoothstep(0.05, 0.12, steep) * (1.0 - smoothstep(0.16, 0.30, steep));   // 坡腳帶（≈18°–35°）
	w[3] = clamp(w[3] + foot * 0.30 * smoothstep(0.45, 0.80, pb), 0.0, 1.0);          // 坡腳的崩落碎石：成堆、不成帶
	float rk = max(w[5], slope_rock);
	float others = w[2] + w[3] + w[4] + w[6] + w[7] + w[8];
	float scale_o = (1.0 - rk) / max(others, 1e-4);
	if (others > 1.0 - rk) {
		w[2] *= scale_o; w[3] *= scale_o; w[4] *= scale_o; w[6] *= scale_o; w[7] *= scale_o; w[8] *= scale_o;
	}
	w[5] = rk;
	float s = w[2] + w[3] + w[4] + w[5] + w[6] + w[7] + w[8];
	w[0] = max(1.0 - s, 0.0);

	// ---- 三平面（只在岩層、且面夠陡時）
	vec3 tb = pow(abs(N), vec3(4.0));
	tb /= (tb.x + tb.y + tb.z);
	bool tri = (w[5] > 0.02) && (tb.y < 0.86);

	// R3 兩層的取樣（落葉 7、苔地 8；不在貼圖陣列裡）：反照率先取好，高度用亮度近似（亮的葉片在上、暗的土在下）
	vec3 c_x[2] = vec3[2](vec3(0.0), vec3(0.0));
	vec4 nv[9];
	float sc[9];
	float smax = -10.0;
	for (int i = 0; i < 9; i++) {
		sc[i] = -10.0;
		nv[i] = vec4(0.5, 0.5, 0.5, 0.0);
		if (w[i] > 0.03) {
			vec4 q;
			if (i >= 7) {
				float Tx = (i == 7) ? r3_tile.x : r3_tile.y;
				vec2 uvx = p / Tx;
				vec3 cxx = (i == 7) ? textureGrad(litter_alb, uvx, dpx / Tx, dpy / Tx).rgb : textureGrad(mossg_alb, uvx, dpx / Tx, dpy / Tx).rgb;
				vec2 nxx = (i == 7) ? textureGrad(litter_nrm, uvx, dpx / Tx, dpy / Tx).rg : textureGrad(mossg_nrm, uvx, dpx / Tx, dpy / Tx).rg;
				c_x[i - 7] = cxx;
				q = vec4(nxx, clamp(dot(cxx, vec3(0.333)) * 1.5, 0.0, 1.0), 0.0);
			} else {
				float T = TILE[i];
				q = textureGrad(nrh_arr, vec3(p / T, float(i)), dpx / T, dpy / T);
				if (i == 5 && tri) {
					vec4 qx = textureGrad(nrh_arr, vec3(vec2(P.z, P.y) / T, 5.0), vec2(dPx.z, dPx.y) / T, vec2(dPy.z, dPy.y) / T);
					vec4 qz = textureGrad(nrh_arr, vec3(vec2(P.x, P.y) / T, 5.0), vec2(dPx.x, dPx.y) / T, vec2(dPy.x, dPy.y) / T);
					q = q * tb.y + qx * tb.x + qz * tb.z;
				}
			}
			nv[i] = q;
			sc[i] = w[i] + q.b * HB;
			smax = max(smax, sc[i]);
		}
	}
	float bw[9];
	float bsum = 0.0;
	for (int i = 0; i < 9; i++) {
		bw[i] = max(sc[i] - (smax - HB_DEPTH), 0.0);
		bsum += bw[i];
	}
	bsum = max(bsum, 1e-5);
	float fd_raw = smoothstep(14.0, 55.0, length(P - CAMERA_POSITION_WORLD));
	float fd = fd_raw * mix(1.0, smoothstep(0.55, 0.85, N.y), far_steep_fix);
	vec3 alb = vec3(0.0);
	vec3 nw = vec3(0.0);
	float rough = 0.0;
	mat2 FROT = mat2(vec2(cos(r3_far_rot), sin(r3_far_rot)), vec2(-sin(r3_far_rot), cos(r3_far_rot)));
	for (int i = 0; i < 9; i++) {
		if (bw[i] > 0.0) {
			float f = bw[i] / bsum;
			if (i >= 7) {
				float Tx = (i == 7) ? r3_tile.x : r3_tile.y;
				vec3 c = c_x[i - 7] * ((i == 7) ? gain_c.x : gain_c.y);
				c = mix(c, vec3(dot(c, vec3(0.30, 0.59, 0.11))), (i == 7) ? litter_desat : 0.0);
				if (fd > 0.0 && f > 0.26) {
					vec2 uvf = (FROT * p) / Tx * 0.31 + vec2(0.37, 0.61);
					vec3 c2 = (i == 7) ? textureGrad(litter_alb, uvf, (FROT * dpx) / Tx * 0.31, (FROT * dpy) / Tx * 0.31).rgb : textureGrad(mossg_alb, uvf, (FROT * dpx) / Tx * 0.31, (FROT * dpy) / Tx * 0.31).rgb;
					c = mix(c, (c + c2 * ((i == 7) ? gain_c.x : gain_c.y)) * 0.5, fd);
				}
				alb += c * f;
				vec2 t = (nv[i].rg * 2.0 - 1.0) * 0.9;
				nw += normalize(vec3(t.x, 0.0, -t.y) + N) * f;
				rough += mix(0.86, 0.98, clamp(0.5 + (nf - 0.5) * 0.8, 0.0, 1.0)) * f;
				continue;
			}
			float T = TILE[i];
			float gn = (i == 0) ? gain_a.x : ((i == 2) ? gain_a.y : ((i == 3) ? gain_a.z : ((i == 4) ? gain_a.w : ((i == 5) ? gain_b.x : ((i == 6) ? gain_b.y : 1.0)))));
			vec3 c = textureGrad(albedo_arr, vec3(p / T, float(i)), dpx / T, dpy / T).rgb * gn;
			if (i == 5 && tri) {
				vec3 cx = textureGrad(albedo_arr, vec3(vec2(P.z, P.y) / T, 5.0), vec2(dPx.z, dPx.y) / T, vec2(dPy.z, dPy.y) / T).rgb;
				vec3 cz = textureGrad(albedo_arr, vec3(vec2(P.x, P.y) / T, 5.0), vec2(dPx.x, dPx.y) / T, vec2(dPy.x, dPy.y) / T).rgb;
				c = c * tb.y + cx * tb.x + cz * tb.z;
				c *= vec3(1.07, 1.0, 0.86);
				c *= mix(1.0, cliff_tone, 1.0 - tb.y);
			}
			bool far_tri = (i == 5 && tri && far_steep_fix > 0.5);       // R2：陡坡岩層的遠景細節改用三平面（不拉長、保留防重複）
			float fdl = far_tri ? fd_raw : fd;
			if (fdl > 0.0 && f > 0.26) {
				vec3 c2;
				if (far_tri) {
					float T2 = T / 0.29;
					vec3 c2y = textureGrad(albedo_arr, vec3(p / T2 + vec2(0.37, 0.61), 5.0), dpx / T2, dpy / T2).rgb;
					vec3 c2x = textureGrad(albedo_arr, vec3(vec2(P.z, P.y) / T2 + vec2(0.37, 0.61), 5.0), vec2(dPx.z, dPx.y) / T2, vec2(dPy.z, dPy.y) / T2).rgb;
					vec3 c2z = textureGrad(albedo_arr, vec3(vec2(P.x, P.y) / T2 + vec2(0.37, 0.61), 5.0), vec2(dPx.x, dPx.y) / T2, vec2(dPy.x, dPy.y) / T2).rgb;
					c2 = (c2y * tb.y + c2x * tb.x + c2z * tb.z) * vec3(1.07, 1.0, 0.86) * mix(1.0, cliff_tone, 1.0 - tb.y);
				} else if (r3_on > 0.5) {
					vec2 uv2 = (FROT * p) / T * 0.29 + vec2(0.37, 0.61);                    // R3：遠景層旋轉，不與近景同向平鋪
					c2 = textureGrad(albedo_arr, vec3(uv2, float(i)), (FROT * dpx) / T * 0.29, (FROT * dpy) / T * 0.29).rgb;
				} else {
					vec2 uv2 = (p / T) * 0.29 + vec2(0.37, 0.61);
					c2 = textureGrad(albedo_arr, vec3(uv2, float(i)), dpx / T * 0.29, dpy / T * 0.29).rgb;
				}
				c = mix(c, (c + c2) * 0.5, fdl);
			}
			alb += c * f;
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
	// ---- 微起伏（V1.3 的中心差分＋正交旋轉兩層，避免同向斜紋）：只加在平地的土／泥／草／落葉層
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
			vec2 g = g0 * BRA + (g1 * BRB) * 2.2;
			vec3 nbump = normalize(vec3(-g.x * bump_amp * 0.9, 1.0, -g.y * bump_amp * 0.9));
			nw = normalize(nw + vec3(nbump.x, 0.0, nbump.z) * clamp(flat_w, 0.0, 1.0));
		}
	}

	// ---- 車轍：只在壓實土上、村緣到鳥居前；兩條淺凹痕（沿路向有斷續）。
	//      側向距離 off（UV2.y）是平滑的場，用螢幕空間導數解出它在世界 xz 的梯度＝側向方向，凹痕的法線沿這個方向傾斜（不需要另存路向）。
	float rut_k = rut_amp * smoothstep(rut_z.y, rut_z.x, P.z) * smoothstep(0.35, 0.85, w[2]);
	float rut = 0.0;
	if (rut_k > 0.01) {
		float wob = (nm.r - 0.5) * 0.30 + (nf - 0.5) * 0.10;
		float u0 = off + wob;
		float brk = smoothstep(0.28, 0.62, texture(noise_tex, p / 7.3 + vec2(0.19, 0.43)).g + (nb.b - 0.5) * 0.4);
		float G0 = 1.0 - smoothstep(0.05, 0.24, abs(abs(u0 - 0.06) - rut_gap));
		float G1 = 1.0 - smoothstep(0.05, 0.24, abs(abs(u0 + 0.06) - rut_gap));
		rut = 0.5 * (G0 + G1) * brk * rut_k;
		float det = dpx.x * dpy.y - dpx.y * dpy.x;
		if (abs(det) > 1e-8) {
			vec2 gl = vec2(doff.x * dpy.y - doff.y * dpx.y, -doff.x * dpy.x + doff.y * dpx.x) / det;
			vec2 lat = gl / max(length(gl), 1e-6);
			float dG = (G1 - G0) / 0.12;
			nw = normalize(nw + vec3(lat.x, 0.0, lat.y) * (-dG) * brk * rut_k * 0.22);
		}
	}

	// ---- 巨觀明暗（兩個尺度）：不要整片同一個亮度
	float macro = mix(0.84, 1.14, nb.r) * mix(0.93, 1.07, nm.r);
	alb *= macro;
	// 壓實土／泥的色相漂移
	float dirt_f = (bw[2] + bw[4]) / bsum;
	alb *= mix(vec3(1.0), mix(vec3(0.93, 0.95, 1.0), vec3(1.07, 1.02, 0.93), nm.g), dirt_f * 0.9);
	// 乾草斑偏黃（比 S04 重：開闊草地不是一整片均勻的綠）
	float g0 = bw[0] / bsum;
	alb = mix(alb, alb * vec3(1.14, 1.04, 0.74), g0 * smoothstep(0.42, 0.80, nb.a) * 0.75 * (1.0 - 0.6 * r3_on));
	// R3：草降飽和（短草全量、粗草七成）；乾／潤由頂點（地形凸處乾、窪處潤）決定，不再只靠一張噪聲
	if (r3_on > 0.5) {
		float g6 = bw[6] / bsum;
		float gf = g0 + 0.7 * g6;
		float lum = dot(alb, vec3(0.30, 0.59, 0.11));
		alb = mix(alb, vec3(lum), grass_desat * gf);
		alb = mix(alb, alb * dry_tint, clamp(r3v.b, 0.0, 1.0) * (g0 + 0.6 * g6) * 0.85);
		alb = mix(alb, alb * lush_tint, clamp(r3v.a, 0.0, 1.0) * g0 * 0.7);
	}
	alb *= 1.0 - 0.06 * rut;

	// ---- 濕度：壓暗＋降粗糙度
	alb *= mix(1.0, wet_dark, wet);

	// ---- 苔：噪聲成絨狀斑，偏愛上向面
	float mm = moss_w * (0.35 + 0.95 * nm.g) + (nvf - 0.5) * 0.4 * moss_w;
	float moss_m = smoothstep(0.30, 0.62, mm) * smoothstep(0.05, 0.65, nw.y + (nm.g - 0.5) * 0.3);
	vec3 mcol = moss_col * mix(0.62, 1.3, nvf);
	alb = mix(alb, mcol * 3.4 * (0.4 + 0.6 * dot(alb, vec3(0.333))), moss_m * 0.82);
	rough = mix(rough, 0.97, moss_m);
	rough = rough * mix(1.0, 0.62, wet);

	// ---- 輸出（含北端和 S02 白模的接縫淡出）
	float dk = clamp((P.z - seam_z0) / max(seam_z1 - seam_z0, 1.0), 0.0, 1.0);
	dk = dk * dk * (3.0 - 2.0 * dk);
	vec3 tex_lin = alb * ground_k;
	vec3 fb_lin = s2l(fbc);
	ALBEDO = mix(fb_lin, tex_lin, dk);
	vec3 Nf = normalize(mix(N, nw, dk));
	NORMAL = normalize((VIEW_MATRIX * vec4(Nf, 0.0)).xyz);
	ROUGHNESS = mix(1.0, clamp(rough, 0.05, 1.0), dk);
	SPECULAR = mix(0.15, 0.3 + 0.2 * wet, dk);
}
