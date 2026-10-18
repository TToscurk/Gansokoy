// 幻想鄉全域風場 V1.2（WIND_V1_REVIEW）—— shader 端的唯一風場實作。
// 與 scripts/wind.gd 的 sample_field()／_gusts_at()／_vertical_factor()／_exposure() 逐項同一套公式：
// 植被（GPU）與道具／角色（CPU）吃同一個場、同一個陣風。改這裡一定要同步改 wind.gd。
//
// 本檔只放「場」：方向／強度空間擾動、沿風向推進的 front、行進陣風事件、垂直風剖面、
// 遮蔽體積、物種參數表、二階彈簧（樹冠延遲）。各植被 shader 只決定「怎麼把力變成位移」。
//
// global uniform（Wind autoload 上傳；project.godot [shader_globals] 註冊）：
//   gw_dir／gw_strength／gw_gust／gw_time／gw_flutter  —— V1 原有（gw_strength＝基礎風，不含陣風）
//   gw_ctrl   ＝ (事件數, 陣風總增益, 除錯模式, 遮蔽數)
//   gw_vprof  ＝ (剖面指數 α, 正規化高度 z0 m, 海拔參考 y, 海拔增益 /m)
//   gw_tune   ＝ (局部風力差異倍率, 0, 0, 0)：空間擾動振幅；1＝設計值（Wind.set_local_variation）
//   gw_events ＝ 4×3 RGBA32F：row0 (ox, oz, t0, amp)、row1 (dir.x, dir.z, dur, 響應最長範圍 tmax)、row2 (半寬, seed, 0, 0)
//               前緣速度固定 WF_GUST_SPEED（＝Wind.GUST_SPEED）；前緣彎曲相位＝fract(t0·0.618)（不必多讀一個 texel）
//   gw_shelters ＝ 8×2：row0 (x, z, 半徑, 係數)、row1 (遮蔽頂高 y, 0, 0, 0)
//   gw_species ＝ N×5：見 scripts/wind/wind_species.gd texel_rows()（欄順序同 SPECIES_ORDER）
//   gw_species_n ＝ 物種數；0＝表未上傳（編輯器預覽）→ 用內建預設
//   gw_resp   ＝ 65×(4×N) R32F：第 i 道陣風對物種 s 的「樹冠彈簧響應」查表（列 i×N+s；0–63＝取樣、64＝定義域長度）
//               CPU 在陣風生成／物種參數變動時預算（彈簧卷積 6 點），shader 只查表 → 每頂點不再重算 6 次驅動力

#ifndef WIND_FIELD_INC
#define WIND_FIELD_INC

global uniform vec3 gw_dir;
global uniform float gw_strength;
global uniform float gw_gust;
global uniform float gw_time;
global uniform float gw_flutter;
global uniform vec4 gw_ctrl;
global uniform vec4 gw_vprof;
global uniform vec4 gw_tune;
global uniform sampler2D gw_events;
global uniform sampler2D gw_shelters;
global uniform sampler2D gw_species;
global uniform float gw_species_n;
global uniform sampler2D gw_resp : filter_linear;

// 物種索引（與 wind_species.gd SPECIES_ORDER 一致）
const int WF_SP_BROAD_TALL = 0;
const int WF_SP_BROAD_SMALL = 1;
const int WF_SP_CONIFER = 2;
const int WF_SP_WEEPING = 3;
const int WF_SP_BAMBOO = 4;
const int WF_SP_BUSH = 5;
const int WF_SP_GRASS = 6;
const int WF_SP_PADDY = 7;
const int WF_SP_RIGID = 8;

const float WF_TAU = 6.2831853;
const float WF_GUST_SPEED = 9.0;

// 空間場：回傳 (風向 xz 單位向量, 強度空間倍率)。與 Wind.sample_field 的 n1／n2 同。
vec3 wf_field(vec2 p) {
	vec2 base = gw_dir.xz;
	if (dot(base, base) < 1e-8) {
		base = vec2(1.0, 0.0);
	}
	base = normalize(base);
	float n1 = 0.5 + 0.5 * sin(dot(p, vec2(0.045, 0.031)) + gw_time * 0.11);
	float n2 = 0.5 + 0.5 * sin(dot(p, vec2(-0.021, 0.038)) + gw_time * 0.07);
	float aoff = gw_tune.x * (0.38 * (n1 - 0.5) + 0.12 * (n2 - 0.5));
	// |aoff| ≤ 0.25 rad × gw_tune.x（≤ 0.5 rad 時誤差 < 3e-3）：小角度泰勒展開代替 cos／sin（誤差 < 2e-4 rad，省 2 個逐頂點三角函數）
	float a2 = aoff * aoff;
	float ca = 1.0 - 0.5 * a2 + a2 * a2 * (1.0 / 24.0);
	float sa = aoff * (1.0 - a2 * (1.0 / 6.0));
	vec2 wd = vec2(base.x * ca - base.y * sa, base.x * sa + base.y * ca);
	float m = (1.0 + gw_tune.x * 0.28 * (n1 - 0.5)) * (1.0 + gw_tune.x * 0.14 * (n2 - 0.5));
	return vec3(wd, m);
}

// 陣風封包：快升（前 30 %）慢落，0–1；tau 在 [0, dur] 外為 0（smoothstep 兩端自然歸零）。
float wf_env(float tau, float dur) {
	float r = 0.3 * dur;
	return smoothstep(0.0, r, tau) * (1.0 - smoothstep(r, dur, tau));
}

// 行進陣風：每個事件是一道沿自己方向以 WF_GUST_SPEED 推進的前緣，橫向有限寬（半寬 c.x）、
// 前緣沿橫向微彎、強度沿橫向起伏 → 相鄰植物相干但不同步，20 m 外明顯不同。
// 回傳 vec2(本地時間 tau, 橫向座標 across)；tau ≤ 0＝前緣未到。
// tau0＝不含前緣彎曲的本地時間（彎曲最多 ±0.6 s）：呼叫端先用它早退，才算 sin。
vec3 wf_event_local0(vec4 a, vec4 b, vec2 p) {
	vec2 rel = p - a.xy;
	float along = dot(rel, b.xy);
	float across = dot(rel, vec2(-b.y, b.x));
	return vec3(gw_time - a.z - along / WF_GUST_SPEED, across, 0.0);
}

float wf_event_bend(vec4 a, float across) {
	return 0.6 * sin(across * 0.07 + fract(a.z * 0.6180339) * WF_TAU);
}

float wf_event_k(vec4 a, vec4 c, float across) {
	float lat = 1.0 - smoothstep(0.55 * c.x, c.x, abs(across));
	return a.w * lat * (0.80 + 0.25 * sin(across * 0.11 + c.y * WF_TAU));
}

// 單點驅動力（草用：沒有樹冠層，只要一個純延遲 lag）。與 Wind.sample_field()["strength"] 同量。
float wf_force(vec2 p, vec2 wd, float m, float env, float t, float lag) {
	float front = 0.5 + 0.5 * sin((t - lag) * 1.25 - dot(p, wd) * 0.10);
	float g = 0.0;
	int n = int(gw_ctrl.x + 0.5);
	for (int i = 0; i < 4; i++) {
		if (i >= n) {
			break;
		}
		vec4 a = texelFetch(gw_events, ivec2(i, 0), 0);
		vec4 b = texelFetch(gw_events, ivec2(i, 1), 0);
		vec3 tl = wf_event_local0(a, b, p);
		float tau = tl.x - (gw_time - t) - lag;
		if (tau <= -0.6 || tau >= b.z + 0.6) {
			continue;
		}
		tau += wf_event_bend(a, tl.y);
		vec4 c = texelFetch(gw_events, ivec2(i, 2), 0);
		g += wf_event_k(a, c, tl.y) * wf_env(tau, b.z);
	}
	return env * (gw_strength * m * (0.85 + 0.30 * front) + g * gw_ctrl.y);
}

// 垂直風剖面（離地高度 z，m）：冪律 (z/z0)^α，夾在 0.55–1.9。z0＝草尖高度 → 草維持 P9 審定外觀。
float wf_height_factor(float z) {
	return clamp(pow(max(z, 0.05) / max(gw_vprof.y, 0.05), gw_vprof.x), 0.55, 1.9);
}

// 海拔：根部世界高度相對參考面每公尺 +gain（山丘上風較強），夾 0.7–1.5。
float wf_elev_factor(float y) {
	return clamp(1.0 + gw_vprof.w * (y - gw_vprof.z), 0.7, 1.5);
}

// 遮蔽（建築／牆／山丘的避風區）：水平圓、頂高以上 2 m 內漸回 1。
float wf_shelter(vec2 p, float y) {
	float f = 1.0;
	int n = int(gw_ctrl.w + 0.5);
	for (int i = 0; i < 8; i++) {
		if (i >= n) {
			break;
		}
		vec4 s = texelFetch(gw_shelters, ivec2(i, 0), 0);
		float top = texelFetch(gw_shelters, ivec2(i, 1), 0).x;
		float d = distance(p, s.xy);
		if (d < s.z) {
			float k = mix(s.w, 1.0, smoothstep(s.z * 0.55, s.z, d));
			f *= mix(k, 1.0, smoothstep(top, top + 2.0, y));
		}
	}
	return f;
}

// 物種參數（shader 只讀前 3 列）。r0=(stiffness, bend_mult, tip_response, response_lag)
//   r1=(damping, flutter_hz, max_deform_m, crown_gain)  r2=(front 波的彈簧增益, 相位, sway_hz, 響應範圍 lag+6dt)
void wf_species(int id, out vec4 r0, out vec4 r1, out vec4 r2) {
	if (gw_species_n < 0.5 || id < 0 || float(id) >= gw_species_n) {
		r0 = vec4(0.5, 1.0, 2.2, 0.45);
		r1 = vec4(0.32, 1.15, 0.8, 0.55);
		r2 = vec4(1.0, 0.0, 0.22, 0.0);
		return;
	}
	r0 = texelFetch(gw_species, ivec2(id, 0), 0);
	r1 = texelFetch(gw_species, ivec2(id, 1), 0);
	r2 = texelFetch(gw_species, ivec2(id, 2), 0);
}

// 第 i 道陣風對物種 sp 的彈簧響應查表（tau＝陣風本地時間）。span＝lag＋6·dt（物種列 r2.w），
// 定義域 [0, dur＋span]；硬體線性內插（1 次取樣）。
float wf_resp(int i, int sp, float tau, float dur, float span) {
	float tmax = dur + span;
	if (tau <= 0.0 || tau >= tmax) {
		return 0.0;
	}
	float rows = 4.0 * gw_species_n;
	vec2 uv = vec2((tau / tmax * 63.0 + 0.5) / 65.0, (float(i) * gw_species_n + float(sp) + 0.5) / rows);
	return textureLod(gw_resp, uv, 0.0).r;
}

// 驅動力（風場強度單位，與 Wind.sample_field()["strength"] 同一個量）——主幹與樹冠一次算完：
//   trunk＝驅動力在 t − 0.25·lag 的值（主幹：重、只略延遲）
//   crown＝驅動力經過物種欠阻尼彈簧（lag＋6 點脈衝響應）的輸出：
//     穩定風 → 不變（DC 增益 1）；front 正弦波 → 解析增益／相位（r2.xy）；行進陣風 → 查 gw_resp 表。
//   陣風過後主幹回正時，樹冠還在擺、並過衝一下再停（響應表含負權重）。
// 與 Wind.sample_vegetation()（CPU 直接做 6 點卷積）數學上相同。
void wf_drive(vec2 p, vec2 wd, float m, float env, float t, int sp, float lag, vec4 r2, out float trunk, out float crown) {
	float ph = dot(p, wd) * 0.10;
	float base = gw_strength * m;
	float front_t = 0.5 + 0.5 * sin((t - 0.25 * lag) * 1.25 - ph);
	float front_c = 0.5 + 0.5 * r2.x * sin(t * 1.25 - ph + r2.y);
	float gt = 0.0;
	float gc = 0.0;
	int n = int(gw_ctrl.x + 0.5);
	bool has_resp = gw_species_n > 0.5 && sp >= 0;
	for (int i = 0; i < 4; i++) {
		if (i >= n) {
			break;
		}
		vec4 a = texelFetch(gw_events, ivec2(i, 0), 0);
		vec4 b = texelFetch(gw_events, ivec2(i, 1), 0);
		vec3 tl = wf_event_local0(a, b, p);
		float tau = tl.x - (gw_time - t);
		// 前緣未到／所有物種的響應都已結束（b.w＝最長響應範圍；±0.6＝前緣彎曲上限）→ 不算 sin、不讀第三個 texel
		if (tau <= -0.6 || tau >= b.w + 0.6) {
			continue;
		}
		tau += wf_event_bend(a, tl.y);
		if (tau <= 0.0) {
			continue;
		}
		vec4 c = texelFetch(gw_events, ivec2(i, 2), 0);
		float k = wf_event_k(a, c, tl.y);
		if (k <= 0.0) {
			continue;
		}
		gt += k * wf_env(tau - 0.25 * lag, b.z);
		gc += k * (has_resp ? wf_resp(i, sp, tau, b.z, r2.w) : wf_env(tau - lag, b.z));
	}
	trunk = env * (base * (0.85 + 0.30 * front_t) + gt * gw_ctrl.y);
	crown = env * (base * (0.85 + 0.30 * front_c) + gc * gw_ctrl.y);
}

// 安全變形上限：長度軟夾 l' = l / sqrt(1 + (l/max_d)²) —— 小位移幾乎不變、大位移漸近 max_d，
// 不會硬切成平台（比 tanh 便宜：1 個 inversesqrt）。
vec3 wf_soft_clamp(vec3 off, float max_d) {
	if (max_d <= 0.0) {
		return vec3(0.0);
	}
	return off * inversesqrt(1.0 + dot(off, off) / (max_d * max_d));
}

// 實例雜湊（根部世界座標 → 0–1 相位），讓相鄰個體的自然擺動不同步（無 sin，便宜）。
float wf_hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

// 除錯熱圖：位移長度（m）→ 灰階 emission（0.6 m＝白）。gw_ctrl.z == 1 時各 shader 改輸出這個。
vec3 wf_heat(float d) {
	return vec3(clamp(d / 0.6, 0.0, 1.0));
}

#endif
