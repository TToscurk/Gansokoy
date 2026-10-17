shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

// 獸道 BOSS 場石鋪（V0.1 白模材質）
// 世界座標上的不規則石板（Voronoi）＋三道同心環帶（帶內換成較小、較冷較暗的石板）＋缺失成裸土的石板＋苔。
// 疊在地形上方 9 cm；外緣按「整塊石板」被吃掉（越外越多），再加頂點 alpha 淡出——不是一圈硬邊的圓盤。
// 1 m 的地形頂點色畫不出石板，所以用材質畫。
uniform vec2 arena_c = vec2(4.0, -398.0);
uniform float cell = 1.45;
uniform vec4 rings = vec4(6.5, 13.0, 18.0, 1.6);     // 三道環半徑＋帶寬
uniform vec2 erosion = vec2(15.0, 21.6);             // 石板開始被吃掉的半徑／全部消失的半徑
uniform vec3 stone_a : source_color = vec3(0.52, 0.51, 0.48);
uniform vec3 stone_b : source_color = vec3(0.37, 0.38, 0.38);
uniform vec3 mortar : source_color = vec3(0.22, 0.21, 0.18);
uniform vec3 moss : source_color = vec3(0.24, 0.33, 0.17);
uniform vec3 dirt : source_color = vec3(0.34, 0.27, 0.18);

varying vec3 wpos;

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// 回傳 (到最近石縫的距離, 石板雜湊)
vec2 voro(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = 0.5 + 0.40 * sin(6.2831 * hash22(n + g));
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = g;
			}
		}
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 o = 0.5 + 0.40 * sin(6.2831 * hash22(n + g));
			vec2 r = g + o - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return vec2(md, hash12(n + mg));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 q = wpos.xz;
	float rr = length(q - arena_c);
	// 環帶：離最近一道環的距離 < 帶半寬 → 帶內
	float rd = min(min(abs(rr - rings.x), abs(rr - rings.y)), abs(rr - rings.z));
	float half_w = rings.w * 0.5 + 0.3;
	float band = 1.0 - smoothstep(half_w - 0.2, half_w, rd);
	vec2 vb = voro(q / cell);
	vec2 vs = voro(q / (cell * 0.5));
	vec2 v = mix(vb, vs, band);
	// 外緣：整塊石板被吃掉（以大石板格的雜湊決定，越外越容易消失）
	float er = smoothstep(erosion.x, erosion.y, rr + (hash12(floor(q / cell)) - 0.5) * 3.2);
	if (vb.y < er) {
		discard;
	}
	float edge = smoothstep(0.012, 0.038, v.x);         // 0＝石縫、1＝石面（縫細：近景才不會每塊石頭都被粗線描邊）
	float bevel = smoothstep(0.02, 0.18, v.x);          // 板緣倒角感：越靠縫越暗
	vec3 st = mix(stone_a, stone_b, v.y);
	st = mix(st, st * vec3(0.62, 0.65, 0.72), band);    // 環帶：偏冷偏暗
	// 約 12% 的石板缺失成裸土；部分覆苔
	float miss = step(0.88, hash12(vec2(v.y * 91.7, v.y * 13.3)));
	st = mix(st, dirt * 0.8, miss * 0.9);
	float m = smoothstep(0.50, 0.95, hash12(floor(q * 0.45) + 3.1) * 0.55 + v.y * 0.45);
	st = mix(st, moss, m * 0.5);
	st *= mix(0.70, 1.0, bevel);
	vec3 joint = mix(mortar, dirt * 0.7, 0.65);
	ALBEDO = mix(joint, st, edge);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	ALPHA = COLOR.a;
}
