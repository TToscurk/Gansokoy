// 日之呼吸火焰系統（統一版）— 風格化火帶層（stroke）。目標：《鬼滅之刃》動畫的手繪火焰語言，不是寫實火。
// 幾何：sun_fire.gd 每幀沿「刀尖實際走過的路徑」建一條朝相機展開的火帶（ImmediateMesh）。
//   UV.x＝沿整條火帶的位置（整圈一張貼圖，不重複）；UV.y＝0 內緣 → 1 外側火舌尖端
//   UV2.x＝這一段被刀點燃的技能時間；UV2.y＝這一段在角色與鏡頭之間的程度（0–1，越大越透明）
// 貼圖 stylized_flame_band.png（線性資料）：R＝火體距離場、G＝黃色核心位移、B＝白熱亮線、A＝內部深色摺痕。
// 著色：用門檻切出硬邊色塊（黃核心／橘中層／紅外焰／深色輪廓線），不是平滑漸層；形狀抖動以 12 fps 跳格（動畫「一拍二」的手感）。
// 輸出：unshaded＋預乘 alpha；亮度直接寫進 ALBEDO（unshaded 時 EMISSION 不輸出）。深色輪廓線用 ALPHA 擋掉背景才看得見。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D band_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float skill_t = 0.0;          // 技能時間（Hit Stop 不前進）
uniform float fx_time = 0.0;          // 抖動時鐘（Hit Stop 不前進）
uniform float cut_t = 99.0;           // 動作中斷：之後才會被點燃的部分不出現
uniform float intensity = 1.0;
uniform float flare = 0.0;            // 命中熱度脈衝：黃色核心瞬間擴大
uniform float grow = 0.07;            // 點燃後火帶從內緣長到全高的時間（s）
uniform float head_len = 0.06;        // 刀尖前緣的高溫段（s）
uniform float ring_t0 = 0.53;         // 火環第一段被點燃的時間
uniform float tear_t = 1.10;          // 開始撕裂（最先點燃的那一段）
uniform float gone_t = 1.50;          // 燒完（最先點燃的那一段）
uniform float tear_lag = 0.30;        // 越晚點燃的部分越晚撕裂（每秒點燃時間延後幾秒）
uniform float vanish_age = 99.0;      // 選用（R13 炎舞）：每一段點燃後多久完全消失（預設 99＝不消失，舊行為：撕裂後殘留到 stroke.end_t）
uniform float vanish_soft = 0.12;     // 消失前的淡出長度（s）
uniform float step_fps = 12.0;
uniform float wobble = 1.0;
uniform float yellow_cut = 0.80;
uniform float orange_cut = 0.40;
uniform float outline_w = 0.07;
uniform float opacity = 0.95;
uniform float near_fade = 0.65;
uniform float head_gain = 0.3;
uniform float taper_u = 0.035;        // 火環起點（＝閉合處）兩端收尖的長度（整圈的比例）
uniform float taper_head = 0.03;      // 刀尖前緣收尖的時間（s）
uniform vec3 col_white = vec3(1.0, 0.92, 0.70);
uniform float white_gain = 3.2;
uniform vec3 col_yellow = vec3(1.0, 0.62, 0.10);
uniform float yellow_gain = 1.9;
uniform vec3 col_orange = vec3(1.0, 0.26, 0.02);
uniform float orange_gain = 1.25;
uniform vec3 col_red = vec3(0.55, 0.035, 0.008);
uniform float red_gain = 1.0;
uniform vec3 col_line = vec3(0.07, 0.006, 0.002);

varying float v_t0;
varying float v_near;

void vertex() {
	v_t0 = UV2.x;
	v_near = UV2.y;
}

void fragment() {
	if (v_t0 > cut_t) {
		discard;
	}
	float age = skill_t - v_t0;
	if (age < 0.0) {
		discard;
	}
	float van = 1.0 - smoothstep(vanish_age - vanish_soft, vanish_age, age);
	if (van <= 0.0) {
		discard;
	}
	float V = UV.y;
	float st = floor(fx_time * step_fps) / step_fps;
	vec2 q = vec2(UV.x * 7.0 + st * 0.37, V * 0.9 - st * 1.3);
	vec3 n1 = texture(noise_tex, q).rgb;
	vec3 n2 = texture(noise_tex, q * vec2(2.3, 1.7) + vec2(st * 0.21, st * 0.6)).rgb;
	// 火舌尖端隨跳格擺動（越外側越大），整體造型維持手繪的輪廓
	vec2 uv = UV + vec2((n1.g - 0.5) * 0.010, (n1.r - 0.5) * 0.07 * V * V) * wobble;
	// 展開：剛點燃時火帶只有內緣，0.07 s 內長到全高
	float g = mix(0.40, 1.0, smoothstep(0.0, grow, age));
	uv.y /= g;
	if (uv.y >= 0.995) {
		discard;
	}
	vec4 tx = texture(band_tex, vec2(uv.x, 1.0 - uv.y));   // 貼圖第 0 列＝火舌尖端（外側），UV.y＝0 是內緣
	// 消散：由外側火舌往內撕開，越早點燃的部分越早散
	float lag = (v_t0 - ring_t0) * tear_lag;
	float er = smoothstep(tear_t + lag, gone_t + lag, skill_t);
	float nn = n1.b * 0.6 + n2.r * 0.4;
	// 收尖：起點與刀尖前緣不是直切的矩形斷口，而是由外往內收成尖角
	float tp = max(1.0 - smoothstep(0.0, taper_u, UV.x), 1.0 - smoothstep(0.0, taper_head, age));
	float field = tx.r - er * (0.35 + 0.75 * nn) * (0.55 + 0.7 * V) - tp * (0.12 + 0.9 * abs(V - 0.3));
	float aa = fwidth(field) * 1.2 + 0.004;
	float cov = smoothstep(0.0, aa, field) * intensity * van;
	if (cov < 0.003) {
		discard;
	}
	float head = 1.0 - smoothstep(0.0, head_len, age);
	float tone = field * 1.6 + (0.45 - V) * 1.2 + (tx.g - 0.5) * 0.5 + flare * 0.35 + head * head_gain - er * 0.55;
	float sy = smoothstep(yellow_cut - 0.02, yellow_cut + 0.02, tone);
	vec3 c = col_red * red_gain;
	c = mix(c, col_orange * orange_gain, smoothstep(orange_cut - 0.02, orange_cut + 0.02, tone));
	c = mix(c, col_yellow * yellow_gain, sy);
	c = mix(c, col_white * white_gain, smoothstep(0.35, 0.6, tx.b) * smoothstep(0.55, 0.65, tone) * (1.0 - er));
	c = mix(c, col_white * white_gain, head * smoothstep(0.3, 0.0, V) * 0.5);
	// 內部深色摺痕：只在橘／紅區
	c = mix(c, col_red * 0.45, smoothstep(0.3, 0.6, tx.a) * (1.0 - sy) * 0.9);
	// 外側深色輪廓線（內緣不描，讓內側的黃色直接接背景）
	float ol = (1.0 - smoothstep(outline_w * 0.6, outline_w, field)) * smoothstep(0.28, 0.42, V);
	c = mix(c, col_line, ol);
	float a = opacity * (1.0 - near_fade * v_near);
	ALBEDO = c * cov * mix(1.0, 0.7, v_near);
	ALPHA = cov * a;
}
