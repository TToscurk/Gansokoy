// 博麗神社 v3：程序林冠（中景／遠景地形與近景外圍共用同一個函式 → 接縫看不出換材質）。
// s3_canopy(wp, wn, dist, out col, out nrm_offset)：wp＝世界 xz、wn＝世界法線、dist＝離相機距離。
// 春天：常綠闊葉深綠、杉檜墨綠、落葉樹新綠；山櫻只在少數樹冠、柔和。陡坡露岩；谷底草地與田。

uniform vec3 cn_dark : source_color = vec3(0.070, 0.105, 0.058);
uniform vec3 cn_mid : source_color = vec3(0.120, 0.170, 0.080);
uniform vec3 cn_fresh : source_color = vec3(0.270, 0.350, 0.140);
uniform vec3 cn_conifer : source_color = vec3(0.055, 0.082, 0.058);
uniform vec3 cn_sakura : source_color = vec3(0.780, 0.640, 0.680);
uniform vec3 cn_rock : source_color = vec3(0.360, 0.345, 0.320);
uniform vec3 cn_meadow : source_color = vec3(0.260, 0.320, 0.150);
uniform float cn_crown_m = 5.5;
uniform float cn_sakura_amount = 0.035;
uniform float cn_floor_y = -128.0;

float cn_h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
vec2 cn_h22(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}
float cn_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(cn_h21(i), cn_h21(i + vec2(1, 0)), u.x), mix(cn_h21(i + vec2(0, 1)), cn_h21(i + vec2(1, 1)), u.x), u.y);
}
float cn_fbm(vec2 p) {
	return 0.5 * cn_vnoise(p) + 0.3 * cn_vnoise(p * 2.03 + 11.7) + 0.2 * cn_vnoise(p * 4.11 + 3.3);
}
// Worley F1：(到樹心距離 0..~0.9, 樹的雜湊)
vec2 cn_crowns(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = cn_h22(i + g) * 0.8 + 0.1;
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < best) {
				best = d;
				id = cn_h21(i + g + 0.37);
			}
		}
	}
	return vec2(sqrt(best), id);
}

void s3_canopy(vec2 wp, vec3 wn, float dist, float wy, out vec3 col, out vec3 nofs, out float rough) {
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	float zone = cn_fbm(wp / 160.0);
	vec3 base = mix(cn_mid, cn_conifer, smoothstep(0.50, 0.70, zone));
	base = mix(base, cn_dark, smoothstep(0.45, 0.75, cn_fbm(wp / 47.0 + 5.1)) * 0.5);
	base = mix(base, cn_fresh, smoothstep(0.60, 0.80, cn_fbm(wp / 70.0 + 7.3)) * 0.55);
	// 樹冠：近處看得到單棵樹冠的明暗；遠處（> 700 m）淡出成平均色（避免閃爍）
	float detail = 1.0 - smoothstep(250.0, 900.0, dist);
	vec2 c = cn_crowns(wp / cn_crown_m);
	vec2 c2 = cn_crowns(wp / (cn_crown_m * 2.3) + 17.0);
	float cshade = 1.0 - smoothstep(0.30, 0.85, c.x) * 0.42;
	float cshade2 = 1.0 - smoothstep(0.35, 0.90, c2.x) * 0.30;
	float sh = mix(0.80, cshade * cshade2, detail);
	col = base * (0.88 + 0.24 * (c.y - 0.5) * detail + 0.18 * (c2.y - 0.5)) * sh;
	// 山櫻：少數樹冠，柔和粉白（以大樹冠為單位，避免碎片）
	float sk = step(1.0 - cn_sakura_amount, c2.y) * smoothstep(0.55, 0.15, c2.x) * smoothstep(0.35, 0.65, cn_vnoise(wp / 260.0 + 3.1));
	col = mix(col, cn_sakura * (0.7 + 0.3 * cshade), sk * 0.75);
	// 陡坡露岩
	float rk = smoothstep(0.46, 0.66, slope + (cn_vnoise(wp / 24.0) - 0.5) * 0.22);
	col = mix(col, cn_rock * (0.8 + 0.3 * cn_vnoise(wp / 9.0)), rk);
	// 谷底：草地、田、林斑
	float vf = smoothstep(cn_floor_y + 10.0, cn_floor_y - 6.0, wy) * (1.0 - rk);
	float fields = smoothstep(0.45, 0.55, cn_vnoise(wp / 120.0)) * (0.6 + 0.4 * cn_vnoise(floor(wp / 38.0)));
	vec3 vcol = mix(col, cn_meadow * (0.85 + 0.3 * cn_vnoise(wp / 25.0)), fields);
	col = mix(col, vcol, vf);
	// 法線偏移：樹冠鼓起（近距）
	float e = 0.06;
	float hx = cn_crowns((wp + vec2(e * cn_crown_m, 0.0)) / cn_crown_m).x - c.x;
	float hz = cn_crowns((wp + vec2(0.0, e * cn_crown_m)) / cn_crown_m).x - c.x;
	nofs = vec3(hx, 0.0, hz) * 4.0 * detail * (1.0 - rk) * (1.0 - vf * fields);
	rough = 1.0;
}

// 空氣透視（反照率版）：遠處降飽和、偏亮藍灰；仍受日照影響（夜裡不會發光）
vec3 s3_haze(vec3 col, float dist, float k) {
	float h = 1.0 - exp(-dist * k);
	vec3 hz = vec3(0.50, 0.57, 0.66);
	return mix(col, hz, clamp(h, 0.0, 0.88));
}
