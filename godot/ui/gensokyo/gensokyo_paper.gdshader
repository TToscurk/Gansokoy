shader_type canvas_item;
// 幻想鄉 UI 共用「和紙＋毛筆墨框」底。GensokyoPanel 以一張白色 1x1 貼圖畫滿
// (邏輯矩形 + bleed)，UV 0..1 即繪製範圍。所有參數由 GensokyoPanel 餵入，
// 每個面板 seed / 邊權重不同 —— 刻意不讓所有框長得一樣（禁 NinePatch 統一框）。

uniform vec2 rect_size = vec2(400.0, 200.0);   // 含 bleed 的總繪製尺寸（px）
uniform float bleed = 14.0;                     // 邏輯矩形外擴（筆觸可以溢出）
uniform vec4 paper_color : source_color = vec4(0.910, 0.875, 0.800, 1.0);
uniform vec4 ink_color : source_color = vec4(0.090, 0.075, 0.063, 1.0);
uniform vec4 accent_color : source_color = vec4(0.655, 0.180, 0.180, 1.0);
uniform vec4 ember_color : source_color = vec4(0.847, 0.353, 0.220, 1.0);
uniform float opacity = 0.94;
uniform float paper_strength = 1.0;   // 纖維／紙紋
uniform float ink_strength = 1.0;     // 墨框濃度
uniform float accent_strength = 1.0;  // 朱色筆段
uniform float border_px = 3.0;
uniform float irregularity = 0.55;    // 邊緣不規則（0 = 直線）
uniform vec4 border_sides = vec4(1.0, 0.35, 0.85, 0.55); // 上、右、下、左 權重（不對稱）
uniform float taper = 0.6;            // 筆勢：上框左重右輕、下框右重左輕……
uniform int accent_edge = 2;          // 0 上 1 右 2 下 3 左；-1 無
uniform vec2 accent_span = vec2(0.80, 0.96);
uniform float soft_edge = 1.2;        // 紙緣柔化 px（HUD 紙條可開大）
uniform float seed = 0.0;
uniform float reveal = 1.0;           // 墨暈開：0 看不見 → 1 全顯
uniform vec2 reveal_origin = vec2(0.08, 0.5);
uniform float burn = 0.0;             // 御札燃燒：0 完整 → 1 燒盡

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// 每個八度旋轉 37°：value noise 的格線方向互相錯開，紙面不會出現方格紋。
const mat2 ROT = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	p = ROT * p;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise(p);
		p = ROT * p * 2.03 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return v;
}

// 單邊墨線：d = 到該邊的（擾動後）距離，along = 沿邊 0..1。
float edge_ink(float d, float along, float weight, float side_seed) {
	if (weight <= 0.001) {
		return 0.0;
	}
	float th = border_px * weight * mix(0.45, 1.45, vnoise(vec2(along * 9.0, side_seed)));
	float core = 1.0 - smoothstep(th * 0.55, th, abs(d - th * 0.35));
	// 乾筆：沿筆勢方向的條紋空洞
	float dry = smoothstep(0.22, 0.55, vnoise(vec2(along * 70.0, d * 0.6 + side_seed * 3.0)));
	return core * mix(1.0, dry, 0.55);
}

void fragment() {
	vec2 L = rect_size - vec2(2.0 * bleed);
	vec2 px = UV * rect_size - vec2(bleed);
	vec2 uvl = px / max(L, vec2(1.0));
	float irr = irregularity * 11.0;

	// 四邊距離，各自沿邊擾動 → 不規則紙緣
	float dt = px.y + irr * (fbm(vec2(px.x * 0.030 + seed, 1.3)) - 0.5);
	float db = (L.y - px.y) + irr * (fbm(vec2(px.x * 0.028 + seed, 7.7)) - 0.5);
	float dl = px.x + irr * (fbm(vec2(3.1, px.y * 0.035 + seed)) - 0.5);
	float dr = (L.x - px.x) + irr * (fbm(vec2(11.9, px.y * 0.033 + seed)) - 0.5);
	float d = min(min(dt, db), min(dl, dr));
	float inside = smoothstep(-soft_edge, soft_edge, d);

	// 和紙：細紋 + 長纖維 + 邊緣舊化
	// 雲紋（大塊濃淡）+ 細砂（逐像素）+ 長纖維（旋轉過的細長噪聲）
	float cloud = fbm(px * 0.012 + seed);
	float sand = hash(floor(px) + seed);
	vec2 fp = ROT * px;
	float fiber = vnoise(vec2(fp.x * 0.020, fp.y * 0.42) + seed);
	vec2 fq = ROT * ROT * px;
	float fiber2 = vnoise(vec2(fq.x * 0.45, fq.y * 0.024) + seed * 1.3);
	vec3 paper = paper_color.rgb;
	paper *= 1.0 - paper_strength * (0.06 * cloud + 0.025 * sand + 0.04 * smoothstep(0.80, 0.97, fiber) + 0.035 * smoothstep(0.82, 0.97, fiber2));
	paper *= 1.0 - paper_strength * 0.07 * (1.0 - smoothstep(0.0, 34.0, d));
	paper = mix(paper, paper * vec3(1.02, 0.99, 0.95), paper_strength * 0.5 * uvl.y);

	// 毛筆墨框（筆勢不對稱：taper 讓每邊一頭重一頭輕）
	float t_top = 1.0 - taper * clamp(uvl.x, 0.0, 1.0);
	float t_bot = 1.0 - taper * (1.0 - clamp(uvl.x, 0.0, 1.0));
	float t_lft = 1.0 - taper * clamp(uvl.y, 0.0, 1.0);
	float t_rgt = 1.0 - taper * (1.0 - clamp(uvl.y, 0.0, 1.0));
	float in_x = step(-2.0, dl) * step(-2.0, dr);
	float in_y = step(-2.0, dt) * step(-2.0, db);
	float ink_top = edge_ink(dt, uvl.x, border_sides.x * t_top, seed + 1.0) * in_x;
	float ink_rgt = edge_ink(dr, uvl.y, border_sides.y * t_rgt, seed + 2.0) * in_y;
	float ink_bot = edge_ink(db, uvl.x, border_sides.z * t_bot, seed + 3.0) * in_x;
	float ink_lft = edge_ink(dl, uvl.y, border_sides.w * t_lft, seed + 4.0) * in_y;

	// 朱色筆段：只佔一條邊的一小截
	float acc = 0.0;
	if (accent_edge == 0) { acc = ink_top * step(accent_span.x, uvl.x) * step(uvl.x, accent_span.y); ink_top -= acc; }
	if (accent_edge == 1) { acc = ink_rgt * step(accent_span.x, uvl.y) * step(uvl.y, accent_span.y); ink_rgt -= acc; }
	if (accent_edge == 2) { acc = ink_bot * step(accent_span.x, uvl.x) * step(uvl.x, accent_span.y); ink_bot -= acc; }
	if (accent_edge == 3) { acc = ink_lft * step(accent_span.x, uvl.y) * step(uvl.y, accent_span.y); ink_lft -= acc; }
	float ink = clamp(max(max(ink_top, ink_bot), max(ink_lft, ink_rgt)) * ink_strength, 0.0, 1.0);
	acc = clamp(acc * accent_strength, 0.0, 1.0);

	vec3 col = mix(paper, ink_color.rgb, ink);
	col = mix(col, accent_color.rgb, acc);
	float a = max(inside * opacity, max(ink * 0.92, acc * 0.9));

	// 墨水暈開（出現動畫）
	if (reveal < 0.999) {
		float dn = distance(uvl * vec2(L.x / max(L.y, 1.0), 1.0), reveal_origin * vec2(L.x / max(L.y, 1.0), 1.0));
		dn /= max(L.x / max(L.y, 1.0), 1.0);
		dn += (fbm(px * 0.02 + seed) - 0.5) * 0.28;
		float r = reveal * 1.35;
		float mask = 1.0 - smoothstep(r - 0.10, r, dn);
		float front = smoothstep(r - 0.14, r - 0.03, dn) * mask;
		col = mix(col, ink_color.rgb, front * 0.45);
		a *= mask;
	}

	// 御札燃燒：灰燼邊 + 餘燼色
	if (burn > 0.001) {
		float n = fbm(px * 0.018 + seed * 2.0) * 0.8 + (1.0 - uvl.y) * 0.25;
		float thr = burn * 1.25 - 0.05;
		float gone = step(n, thr);
		float ember = (1.0 - smoothstep(thr, thr + 0.035, n)) * (1.0 - gone);
		float charr = (1.0 - smoothstep(thr, thr + 0.11, n)) * (1.0 - gone);
		col = mix(col, ink_color.rgb * 0.6, charr * 0.8);
		col = mix(col, ember_color.rgb * 1.25, ember);
		a *= 1.0 - gone;
	}

	COLOR = vec4(col, a * COLOR.a);
}
