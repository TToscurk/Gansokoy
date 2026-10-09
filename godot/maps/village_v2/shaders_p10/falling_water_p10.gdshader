shader_type spatial;
// P10 R5b ROUND 2：水車 2 の水の見せ方（同一 shader、mode で切替）
//   mode 0 落水の帯（柄杓→受け樋の注ぎ・こぼれ水）：UV.x＝横 0..1、UV.y＝上 0 → 下 1
//   mode 1 水面の泡：UV＝楕円の [0,1]² 座標
//   mode 2 柄杓の中の水：口が上を向いている柄杓だけ見える（法線の世界 y で出し入れ＝上り側だけ水が入って見える）
//   mode 3 樋の流れ（受け樋・落とし樋の水面）：UV.y＝流れ方向（m）、UV.x＝横 0..1
//   mode 4 滴り（上り側の柄杓から落ちる水）：途切れ途切れの水滴の列（棒に見えないように）
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.86, 0.91, 0.93, 1.0);
uniform float alpha_max = 0.85;
uniform float speed = 2.2;
uniform float streak_freq = 9.0;
uniform int mode = 0;
uniform float glow = 0.16;   // 泡立った水の散乱（日陰で暗い木に沈まないように少しだけ）

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float a;
	if (mode == 1) {
		vec2 q = UV * 2.0 - 1.0;
		float r = length(q);
		float n = vnoise(UV * 9.0 + vec2(TIME * 0.35, -TIME * 0.2)) * 0.6 + vnoise(UV * 23.0 - vec2(TIME * 0.5)) * 0.4;
		a = smoothstep(1.0, 0.35, r) * smoothstep(0.32, 0.72, n);
	} else if (mode == 2) {
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		float n = vnoise(UV * 7.0 + vec2(TIME * 0.6, TIME * 0.3));
		a = smoothstep(0.45, 0.8, wn.y) * (0.75 + 0.25 * n);
	} else if (mode == 3) {
		float edge = smoothstep(0.0, 0.12, UV.x) * smoothstep(1.0, 0.88, UV.x);
		float s1 = vnoise(vec2(UV.x * 6.0, UV.y * 2.5 - TIME * speed));
		float s2 = vnoise(vec2(UV.x * 13.0 + 3.0, UV.y * 5.0 - TIME * speed * 1.3));
		a = edge * (0.5 + 0.5 * smoothstep(0.3, 0.8, s1 * 0.6 + s2 * 0.4));
	} else if (mode == 4) {
		float edge = smoothstep(0.0, 0.3, UV.x) * smoothstep(1.0, 0.7, UV.x);
		float y = UV.y * 9.0 - TIME * speed * 2.0;
		float cell = floor(y);
		float f = fract(y);
		float len = 0.18 + 0.3 * hash21(vec2(cell, 3.1));
		float on = step(0.35, hash21(vec2(cell, 7.7)));
		a = edge * on * smoothstep(0.0, 0.05, f) * smoothstep(len, len - 0.06, f);
	} else {
		// 縁はほつれる（流れ方向にずれるノイズで幅が揺れる）＝まっすぐな板に見えない
		float rag = vnoise(vec2(UV.y * 7.0 - TIME * speed * 1.2, 3.7)) * 0.22;
		float edge = smoothstep(0.0 + rag, 0.22 + rag, UV.x) * smoothstep(1.0 - rag, 0.78 - rag, UV.x);
		float s1 = vnoise(vec2(UV.x * streak_freq, UV.y * 3.0 - TIME * speed));
		float s2 = vnoise(vec2(UV.x * streak_freq * 2.3 + 7.0, UV.y * 6.0 - TIME * speed * 1.4));
		a = edge * (0.35 + 0.65 * smoothstep(0.25, 0.75, s1 * 0.6 + s2 * 0.4));
		a *= smoothstep(0.0, 0.08, UV.y);
	}
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * glow;
	ROUGHNESS = 0.25;
	SPECULAR = 0.6;
	ALPHA = clamp(a, 0.0, 1.0) * alpha_max;
}
