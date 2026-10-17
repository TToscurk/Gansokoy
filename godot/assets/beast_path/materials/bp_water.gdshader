// 獸道 S04 水面（瀑布潭／支流，V1.1）。
// 技法沿用 P9 R4 hg_water.gdshader（深度差讓淺瀨透出底、noise 兩層捲動漣漪、水際漸層不見硬多邊形邊），再加：
//   · 水色三段：淺處透出暗綠褐的泥底 → 中段 → 深處近黑綠（森林潭的水不是亮藍）；
//   · 漣漪法線（噪聲梯度）＋低粗糙度 → 天空與樹影的倒映、菲涅耳在掠射角更不透明；
//   · 岸邊碎泡沫（水深 ≈ 0 的細帶，噪聲破碎）；
//   · 瀑布落水泡沫：以 fall.xy 為中心，向外擴散的環紋＋噪聲破碎；
//   · 支流流向：uv_flow > 0 時漣漪沿 UV.y（沿流程）捲動。
// 水面網格依地形裁切（岸線＝地面等高線）；這裡用 ALPHA 隨水深漸變，岸緣自然消失。
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 deep_col : source_color = vec3(0.012, 0.036, 0.034);
uniform vec3 mid_col : source_color = vec3(0.030, 0.072, 0.060);
uniform vec3 shallow_col : source_color = vec3(0.120, 0.138, 0.098);
uniform vec3 foam_col : source_color = vec3(0.74, 0.80, 0.80);
uniform float shallow_depth = 0.55;
uniform float deep_depth = 2.4;
uniform float ripple = 0.030;
uniform float uv_flow = 0.0;
uniform vec4 fall = vec4(-8.0, -436.0, 3.6, 1.0);        // 落水點 xz、泡沫半徑、強度（支流材質設 0）
uniform vec4 lip = vec4(0.0, 0.0, 0.0, 0.0);             // V1.2 D：崖口白水（x, z, 上游影響長度, 強度）。只有崖頂上游溪的材質設，其他 = 0（關）

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 flow_uv(vec2 uv, float t, float scale) {
	if (uv_flow > 0.0) {
		return vec2(uv.x * 3.0 * scale, uv.y * 1.6 * scale - t * uv_flow);
	}
	return wpos.xz * 0.9 * scale;
}

void fragment() {
	float zb = texture(depth_tex, SCREEN_UV).r;
	vec4 vb = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, zb, 1.0);
	vb.xyz /= vb.w;
	float slant = max(length(vb.xyz) - length(VERTEX), 0.0);
	vec3 up_v = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float dv = slant * abs(dot(normalize(VERTEX), up_v));
	float t_mid = smoothstep(0.0, shallow_depth, dv);
	float t_deep = smoothstep(shallow_depth, deep_depth, dv);
	vec3 col = mix(mix(shallow_col, mid_col, t_mid), deep_col, t_deep);
	float alpha = mix(0.03, 0.78, smoothstep(0.02, 0.80, dv));      // V1.2 D：淺水更透（透出岸邊的石與泥底）
	alpha = mix(alpha, 0.88, t_deep);

	// ---- 漣漪（兩個尺度的噪聲梯度）
	float tt = TIME;
	vec2 p1 = flow_uv(UV, tt, 1.0) + vec2(tt * 0.020, tt * 0.013);
	vec2 p2 = flow_uv(UV, tt, 2.3) + vec2(-tt * 0.016, tt * 0.021) + vec2(0.37, 0.11);
	float e = 0.014;
	float h1 = texture(noise_tex, p1).g;
	vec2 g1 = vec2(texture(noise_tex, p1 + vec2(e, 0.0)).g - h1, texture(noise_tex, p1 + vec2(0.0, e)).g - h1) / e;
	float h2 = texture(noise_tex, p2).g;
	vec2 g2 = vec2(texture(noise_tex, p2 + vec2(e, 0.0)).g - h2, texture(noise_tex, p2 + vec2(0.0, e)).g - h2) / e;
	vec2 g = g1 * 0.65 + g2 * 0.35;
	vec3 nw = normalize(vec3(-g.x * ripple, 1.0, -g.y * ripple));
	vec3 nv = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// ---- 泡沫：岸緣＋落水點
	float nf = texture(noise_tex, wpos.xz * 1.7 + vec2(tt * 0.05, -tt * 0.04)).b;
	float nf2 = texture(noise_tex, wpos.xz * 3.1 + vec2(-tt * 0.03, tt * 0.02)).g;
	float fd = distance(wpos.xz, fall.xy);
	// V1.2 D：岸緣泡沫只在落水點附近成形（靜水的遠岸沒有泡沫）；遠岸只剩偶爾一小塊浮沫。支流（fall.w = 0）維持很淡
	float near_fall = fall.w > 0.0 ? (1.0 - smoothstep(2.2, 5.2, fd)) : 0.0;
	float shore = (1.0 - smoothstep(0.0, 0.085, dv)) * smoothstep(0.50, 0.74, nf * 0.6 + nf2 * 0.5) * mix(0.04, 0.50, near_fall);
	float imp = (1.0 - smoothstep(0.45, fall.z, fd + (nf - 0.5) * 1.7)) * fall.w;
	float rings = 0.5 + 0.5 * sin((fd - tt * 0.9) * 5.2 + nf * 6.0);
	float broken = smoothstep(0.30, 0.62, nf2 * 0.7 + nf * 0.5);      // 浮沫成塊、中間露出水
	// 崖口白水：水快到崖口時加速、碎成白水（沿流向的條紋），和水幕頂端的白邊接起來，不再是「深色水 → 突然不透明的白」
	float lipf = 0.0;
	if (lip.w > 0.0) {
		float dl = lip.y - wpos.z;                                   // 上游為正（流向 +z）
		float lx = 1.0 - smoothstep(2.4, 4.6, abs(wpos.x - lip.x));
		float streak = texture(noise_tex, vec2(wpos.x * 2.1, wpos.z * 0.55 - tt * 1.3)).g;
		float streak2 = texture(noise_tex, vec2(wpos.x * 4.7 + 0.3, wpos.z * 0.9 - tt * 2.1)).b;
		dl += (streak2 - 0.5) * 1.6;                                  // 端點破碎：不是一條筆直的切線
		float body = (1.0 - smoothstep(0.0, lip.z, max(dl, 0.0))) * (1.0 - smoothstep(-1.2, -0.2, -dl));
		lipf = lip.w * lx * body * smoothstep(0.52, 0.84, streak * 0.62 + streak2 * 0.5 + body * 0.18);
	}
	float foam = clamp(shore + imp * (0.30 + 0.45 * rings) * broken, 0.0, 1.0);

	float fres = pow(1.0 - clamp(dot(nv, normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = mix(mix(col, foam_col, foam), vec3(0.88, 0.93, 0.94), lipf);
	ALPHA = clamp(max(max(alpha + fres * 0.16, foam * 0.90), lipf * 0.58), 0.0, 1.0);
	ROUGHNESS = mix(0.22, 0.65, foam);
	SPECULAR = mix(0.30, 0.25, foam);
	NORMAL = nv;
}
