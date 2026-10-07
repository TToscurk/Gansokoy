// P8 Farmland pilot r4：淺水田水面（數公分深、看得到泥底）。
// 預乘 alpha（blend_premul_alpha）：ALBEDO＝水體色 × 水體不透明度（混濁／浮渣／藻），天空反射由引擎 PBR 鏡面
// （reflected_light_source＝sky、SPECULAR＝0.32 → F0≈0.026，略高於純水 0.02：水面浮膜；0.5 是玻璃值）完整加上、不再被 alpha 壓暗；
// 背景（泥底）透過率＝1 − (body + (1 − body)·F)：垂直看泥底清楚、斜看天空反射變強——物理 Fresnel，不手繪天色。
// 風紋、浮渣、藻、渠流改粗糙度，避免整片白色鏡面／塑膠。
// UV.x＝離岸距離（m）：岸邊更淺更清、帶斷續浮渣線；各田以 uniform 區分混濁度、水色、藻量。
// 遠景秧苗：網格秧苗超出 visibility range 後，由這裡依同一行定義（row_origin／row_dir／row_sp）畫行紋接手。
shader_type spatial;
render_mode blend_premul_alpha, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 water_tint : source_color = vec3(0.26, 0.25, 0.19);
uniform float clarity : hint_range(0.0, 1.0) = 0.6;
uniform float rough_base : hint_range(0.0, 1.0) = 0.05;
uniform float ripple : hint_range(0.0, 2.0) = 0.6;
uniform vec3 scum_color : source_color = vec3(0.34, 0.31, 0.23);
uniform float algae : hint_range(0.0, 1.0) = 0.0;
uniform vec3 algae_color : source_color = vec3(0.24, 0.30, 0.12);
uniform float seed = 0.0;
uniform float flow = 0.0;
uniform vec2 row_origin = vec2(0.0);
uniform vec2 row_dir = vec2(0.0, 1.0);
uniform float row_sp = 0.3;
uniform float hill_sp = 0.18;
uniform vec3 rice_color : source_color = vec3(0.35, 0.5, 0.2);
uniform float rice_cov = 0.0;
uniform float front_z = 1e9;
uniform float lod_start = 40.0;
uniform float lod_end = 52.0;
// 漫射倍率（保留調整口）：r4 試過 0.4——白帶不是漫射造成（實測不變），反而讓水面發黑、讀成濕土，回 1.0
uniform float diffuse_k = 1.0;
// 中遠景掠射（r6 全區 closure）：1.7 m 玩家視角 3–14 m 外、N·V < 0.5 時，實景水田的水面大半被秧苗葉片投影遮住、
// 並有風紋；r5 以前 pilot 只有近景，全區擴張後中遠景整片 RGB≈190–200（與天空同亮）讀成白玻璃。
// 依秧苗覆蓋（rice_cov）把掠射處水面換成秧苗色並壓鏡面（實測亮像素集中在 8–30 m：插秧行距 0.3 m、苗高 0.15–0.25 m，
// 視線俯角 < 8° 時每一行遮住其後 ≈1.4 m，葉片（行寬約 1/3）遮去約一半水面）；近景（< 3 m）與正俯視不變，泥底照舊看得到。休耕／渠道 rice_cov＝0 只壓鏡面。
uniform float graze_near = 3.0;
uniform float graze_far = 14.0;
uniform float graze_spec = 0.45;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz + vec2(seed * 13.7, seed * 7.1);
	float t = TIME * 0.12;
	vec2 fl = vec2(0.0, -TIME * 0.35 * flow);
	float e = 0.05;
	vec2 q = p * 2.4 + vec2(t, -t * 0.7) + fl;
	float h0 = fbm(q);
	float hx = fbm(q + vec2(e, 0.0));
	float hz = fbm(q + vec2(0.0, e));
	vec2 q2 = p * 7.5 - vec2(t * 1.3, t) + fl * 3.0;
	float g0 = vnoise(q2);
	float gx = vnoise(q2 + vec2(e, 0.0));
	float gz = vnoise(q2 + vec2(0.0, e));
	// 風：大尺度分區（無風區＝近鏡面、有風區＝細紋）
	float wind = smoothstep(0.38, 0.72, fbm(p * 0.075 + vec2(seed, 2.0 * seed)));
	float amp = ripple * mix(0.3, 1.0, wind) * 0.016;
	vec2 grad = vec2(hx - h0, hz - h0) / e * amp + vec2(gx - g0, gz - g0) / e * amp * 0.35;
	vec3 nw = normalize(vec3(-grad.x, 1.0, -grad.y));
	vec3 N = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float ndv = clamp(dot(N, VIEW), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);

	float edge = UV.x;
	float nf = fbm(p * 3.1);
	float shallow = 1.0 - smoothstep(0.0, 1.4, edge);
	float scum = (1.0 - smoothstep(0.04, 0.30, edge + (nf - 0.5) * 0.35)) * smoothstep(0.35, 0.6, fbm(p * 1.3 + 5.0)) * 0.85 * (1.0 - flow * 0.6);
	float alg = algae * smoothstep(0.52, 0.72, fbm(p * 0.55 + 3.1)) * (1.0 - smoothstep(0.4, 3.2, edge));
	float murk = mix(1.0 - clarity, 1.0 - clarity * 0.6, fbm(p * 0.22 + 9.0));
	// 水體不透明度（懸浮泥）：岸邊更淺更清
	float body = mix(murk, murk * 0.5, shallow) * 0.85;
	body = max(body, scum * 0.9);
	body = max(body, alg * 0.95);

	vec3 alb = water_tint * mix(0.8, 1.15, nf);
	alb = mix(alb, scum_color, scum);
	alb = mix(alb, algae_color, alg);
	// 粗糙度：無風處近鏡面（天空清楚），風紋／浮渣／藻區霧化；岸邊細碎波紋略粗。
	// 岸際浮渣／藻是漂浮的泥膜與植物，不是鏡面：粗糙＋低鏡面率（r4 實測：浮渣帶粗糙度 0.6 仍以 F0 0.04 接住
	// 太陽的寬鏡面瓣，正俯視在田緣切出 RGB≈220 的白帶）
	float film = max(scum, alg);
	float rough = clamp(mix(rough_base, rough_base + 0.14, wind) + scum * 0.75 + alg * 0.75 + flow * 0.08 + shallow * 0.04, 0.02, 1.0);

	// 遠景秧苗行紋（網格秧苗淡出後接手）
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float far = smoothstep(lod_start, lod_end, dist) * rice_cov;
	if (far > 0.001 && wpos.z < front_z) {
		vec2 d = wpos.xz - row_origin;
		vec2 nn = vec2(-row_dir.y, row_dir.x);
		float rr = dot(d, nn) / row_sp;
		float fw = fwidth(rr) + 1e-4;
		// 行＝一串株點（行寬約 0.25 行距、株間有縫），像素大於行距時淡成平均覆蓋 ≈ 0.2
		float band = abs(fract(rr) - 0.5) * 2.0;
		float line = 1.0 - smoothstep(0.25 - fw, 0.25 + fw, band);
		float aa = dot(d, row_dir) / hill_sp + floor(rr) * 0.37;
		float fa = fwidth(aa) + 1e-4;
		float dots = 1.0 - smoothstep(0.55 - fa, 0.55 + fa, abs(fract(aa) - 0.5) * 2.0);
		dots = mix(0.6, dots, clamp(1.0 - fa * 1.5, 0.0, 1.0));
		line *= dots;
		line = mix(0.2, line, clamp(1.0 - fw * 1.5, 0.0, 1.0));
		float holes = smoothstep(0.62, 0.8, fbm(wpos.xz * 0.22 + seed));
		float cov = far * line * (1.0 - holes) * smoothstep(0.3, 0.7, edge);
		vec3 rc = rice_color * mix(0.75, 1.1, vnoise(wpos.xz * 1.7));
		float nb = max(body, cov);
		alb = mix(alb, rc, cov / max(nb, 1e-3));
		body = nb;
		rough = mix(rough, 0.8, cov);
	}
	// 中遠景掠射：秧苗葉片投影遮水面＋壓天空鏡面
	float graze = smoothstep(graze_near, graze_far, dist) * (1.0 - smoothstep(0.12, 0.5, ndv));
	float gcov = graze * step(0.001, rice_cov) * clamp(0.35 + rice_cov * 0.6, 0.0, 0.65) * smoothstep(0.3, 0.9, edge);
	if (gcov > 0.001) {
		vec3 rc2 = rice_color * mix(0.7, 1.0, vnoise(wpos.xz * 0.9 + seed));
		float nb2 = max(body, gcov);
		alb = mix(alb, rc2, gcov / max(nb2, 1e-3));
		body = nb2;
	}
	rough = mix(rough, max(rough, 0.32), graze);
	// 預乘：漫射只來自水體（懸浮泥）那一份；背景透過率再扣 Fresnel（反射越強、看到的泥底越少）
	// 水線：貼岸 4 cm 內表面張力彎月面＝更平滑、略亮的細線，界定水與濕泥（1.7 m 讀得出「有水」）
	float meniscus = 1.0 - smoothstep(0.0, 0.04, edge);
	rough = mix(rough, 0.06, meniscus * (1.0 - film));
	ALBEDO = alb * body * diffuse_k;
	ROUGHNESS = rough;
	// SPECULAR 0.32（F0≈0.026）；r4 前用 0.5（玻璃 F0 0.04），10:00 太陽鏡面在 W3 北緣切出 RGB≈229 白帶（現約 196）；
	// 0.25 時中景天空反射太弱、1.7 m 讀成濕土
	// 視角相依：斜看（1.7 m 前中景，N·V < 0.55）用 0.5 讓天空反射夠亮、讀得出積水；
	// 正俯視（N·V → 1）降到 0.3，壓掉太陽鏡面在田緣切出的白帶
	// 掠射處被秧苗遮住的那一份不反射天空：Godot 環境 BRDF 的掠射項按 clamp(50·F0) 縮放（F0＝0.16·SPECULAR²），
	// 只降 SPECULAR 0.45 倍時 F0 仍 > 0.02、掠射項不變（實測 RGB 幾乎不動）→ 依遮蔽比例 (1 − gcov) 再壓
	SPECULAR = mix(mix(0.5, 0.3, smoothstep(0.55, 0.9, ndv)), 0.05, film) * (1.0 - graze_spec * graze) * (1.0 - gcov);
	NORMAL = N;
	ALPHA = clamp(body + (1.0 - body) * fres, 0.0, 0.98);
}
