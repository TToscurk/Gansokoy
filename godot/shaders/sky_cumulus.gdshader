// 積雲天空（美術規格 §1：天空是最高優先的單項工程）
//
// 參考《幻走》街道圖：鈷藍的天 + 大朵積雲佔畫面一半，「超現實感」
// 有一半是這片天給的。舊的 ProceduralSkyMaterial 是一片淡漸層。
//
// 跟晝夜系統的接法：只讀 LIGHT0_DIRECTION（太陽方向）——
// daynight.gd 動的是 Main/Sun，這裡照太陽仰角調亮度與染色，
// 不需要腳本另外餵 uniform。
shader_type sky;

uniform vec3 zenith_color: source_color = vec3(0.13, 0.32, 0.72);   // 鈷藍
uniform vec3 horizon_color: source_color = vec3(0.72, 0.82, 0.92);
uniform vec3 cloud_lit: source_color = vec3(1.06, 1.04, 1.0);
uniform vec3 cloud_shade: source_color = vec3(0.62, 0.68, 0.80);
uniform float cloud_coverage: hint_range(0.0, 1.0) = 0.48;
// ⚠ 尺度是第一版的 bug：0.9 時整片天投影出來不到一個雜訊格，
// fbm 幾乎是常數 → 永遠過不了 coverage 門檻，一朵雲都沒有。
// 要讓天上橫跨 5~8 個格，雲才會成朵。
uniform float cloud_scale = 7.0;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x),
		mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int k = 0; k < 5; k++) {
		v += vnoise(p) * a;
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	// ⚠ sky shader 的 LIGHT0_DIRECTION 指**向**太陽（不是光線方向）——
	// 第一版取了負號，白天被判成黑夜，整片天壓成暗灰。
	float sun_up = clamp(LIGHT0_DIRECTION.y, -1.0, 1.0);
	// DayNight 夜間會把同一盞 DirectionalLight3D 當月光使用並留在天空中；
	// 只看方向會把月亮誤判成太陽。日光最低能量 0.35，月光固定 0.30，
	// 用能量窗分流即可保留既有月光方向、陰影與場景照明。
	float is_sun = smoothstep(0.305, 0.345, LIGHT0_ENERGY);
	float daylight = smoothstep(-0.08, 0.25, sun_up) * is_sun;
	float dawn = smoothstep(-0.06, 0.10, sun_up) * (1.0 - smoothstep(0.12, 0.35, sun_up)) * is_sun;

	// 天的漸層：仰角越高越藍。晨昏把地平線染橙。
	float h = clamp(dir.y, 0.0, 1.0);
	vec3 sky_col = mix(horizon_color, zenith_color, pow(h, 0.62));
	sky_col = mix(sky_col, vec3(0.95, 0.62, 0.38), dawn * (1.0 - h) * 0.85);
	sky_col *= mix(0.045, 1.0, daylight);                    // 夜裡壓暗（月光藍在下面補）
	sky_col += vec3(0.02, 0.03, 0.07) * (1.0 - daylight);

	// 太陽盤 + 光暈
	float sun_d = distance(dir, LIGHT0_DIRECTION);
	sky_col += vec3(1.0, 0.92, 0.75) * smoothstep(0.028, 0.012, sun_d) * daylight * 3.0;
	sky_col += vec3(0.9, 0.75, 0.5) * exp(-sun_d * 6.5) * 0.28 * daylight;

	// ── 積雲：把視線投影到一片高空平面，fbm 取雲量 ──
	if (dir.y > 0.015) {
		vec2 uv = dir.xz / (dir.y + 0.18) * cloud_scale;
		float n = fbm(uv * 0.5 + vec2(TIME * 0.004, 0.0));
		// coverage 之上才算雲；邊緣要「花椰菜」一點，再疊一層細節
		// 邊界窗收窄 + 細節少侵蝕 —— 雲要成「朵」（積雲），不是絲狀捲雲
		float cl = smoothstep(1.0 - cloud_coverage - 0.08, 1.0 - cloud_coverage + 0.16, n);
		float det = fbm(uv * 1.7 + vec2(31.7, TIME * 0.006));
		cl *= 0.72 + det * 0.5;
		cl *= smoothstep(0.015, 0.14, dir.y);               // 地平線收掉，別糊成霧
		// 雲的陰影腹：同一片雲往太陽反方向偏移取樣，暗的那面
		float n2 = fbm(uv * 0.5 - LIGHT0_DIRECTION.xz * 0.35 + vec2(TIME * 0.004, 0.0));
		float belly = smoothstep(0.0, 0.9, n2 - n + 0.45);
		vec3 ccol = mix(cloud_shade, cloud_lit, belly) * mix(0.10, 1.0, daylight);
		ccol = mix(ccol, vec3(1.0, 0.72, 0.52), dawn * 0.6); // 晨昏染雲
		sky_col = mix(sky_col, ccol, clamp(cl, 0.0, 1.0) * 0.96);
	}
	COLOR = sky_col;
}
