// 獸道 S04 瀑布水幕（V1.1）。
// 技法沿用 P9 R4 hg_falls.gdshader（縱筋噪聲向下捲動、左右與落口淡出、不露矩形卡片），再加：
//   · 自由落體加速：越往下水絲越快（速度 ∝ √落距），所以上段看得清水絲、下段變成拉長的白霧；
//   · 三個尺度的水絲（粗股／中股／細絲）疊成股：厚處偏青綠、薄處偏白、股與股之間透明；
//   · 落口（crest）一圈充氣白邊；撞擊段（base）增白、變寬；
//   · 兩側邊緣用噪聲晃動淡出，水幕不是一整塊矩形。
// 頂點 UV：x＝橫向 0..1、y＝由崖口往下 0..1；height_m＝水幕高度（m）。
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 water_col : source_color = vec3(0.80, 0.86, 0.86);
uniform vec3 deep_col : source_color = vec3(0.36, 0.42, 0.42);
uniform float speed = 1.0;
uniform float height_m = 17.0;
// V1.2 D：第二層水幕（離崖面再遠 0.34 m）。股的位置左右鏡像、沿高度的相位錯開、速度不同、較淡 → 兩層疊起來有厚度和視差，
// 不再是「一片貼在崖上的半透明平面」。第一層全部維持預設值（不變）。
uniform float mirror = 0.0;
uniform float y_shift = 0.0;
uniform float alpha_k = 1.0;
// V1.3 崖口：水幕頂列現在直接接在崖頂河道末端的水面上（不再藏在懸空的河道帶底下）——
//   top_fade：頂端透明漸入的長度（v 比例；V1.2 0.035＝頂端 0.7 m 全透明 → 河道與水幕之間露出一道空隙）；
//   edge_top：頂端左右邊緣的漸隱寬度（V1.2 全高 0.36 → 頂端可見寬只有網格的 60 %，比崖口河寬窄一截）。
//   預設值＝V1.2（不設就不變），V1.3 的值在 terrain_generator.write_water_materials 寫進材質。
uniform float top_fade = 0.035;
uniform float edge_top = 0.36;

void fragment() {
	float u = mirror > 0.5 ? 1.0 - UV.x : UV.x;
	float v = UV.y;
	float y = v * height_m + y_shift;
	float fall = sqrt(max(y, 0.1)) * 0.9 + 0.35;               // 越往下越快
	float tt = TIME * speed;
	// 水流整體微微左右搖擺（隨高度），打破筆直的平行線
	float sway = (texture(noise_tex, vec2(y * 0.045 - tt * 0.10, 0.21)).g - 0.5) * 0.10;
	float uu = u + sway * (0.3 + v);

	// ---- 主水束：5 股，位置／寬度各自不同，沿高度蛇行；每股自己的水量隨高度緩慢起伏（有的段落細成一線、有的段落鼓起）
	float mainw = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float h1 = fract(sin(fi * 12.9898 + 4.1) * 43758.5453);
		float h2 = fract(sin(fi * 78.233 + 1.7) * 24634.6345);
		float h3 = fract(sin(fi * 37.719 + 9.2) * 17435.2331);
		float cxs = 0.13 + 0.74 * (fi + 0.5 * h1) / 4.6 + (texture(noise_tex, vec2(y * 0.022 + fi * 0.31, fi * 0.17)).g - 0.5) * 0.12;
		float wid = 0.045 + 0.050 * h2;
		float vol = smoothstep(0.12, 0.60, texture(noise_tex, vec2(fi * 0.23 + 0.1, y * 0.019 - tt * 0.10 * (0.5 + h3))).g);
		float dd = (uu - cxs) / (wid * (0.55 + 0.75 * vol));
		mainw = max(mainw, exp(-dd * dd) * (0.35 + 0.65 * vol));
	}
	// ---- 股間薄幕＋細絲（不是均勻的噪聲底）
	float s2 = texture(noise_tex, vec2(uu * 7.7 + 0.30, y * 0.052 - tt * 0.78 * fall)).b;
	float s3 = texture(noise_tex, vec2(uu * 17.0 + 0.71, y * 0.095 - tt * 1.20 * fall)).g;
	float film = smoothstep(0.56, 0.82, s2 * 0.65 + s3 * 0.35) * 0.30;   // 稀疏碎白絲，不鋪成一整片膜
	// 主水束內部的紋路（縱向、慢速下移）
	float grain = texture(noise_tex, vec2(uu * 11.0, y * 0.04 - tt * 0.9 * fall)).g;
	float strand = clamp(mainw * (0.72 + 0.50 * grain) + film * (1.0 - 0.6 * mainw), 0.0, 1.0);
	// 邊緣：隨高度緩慢晃動
	float wob = (texture(noise_tex, vec2(v * 1.7 - TIME * 0.05, 0.37)).g - 0.5) * 0.42 + (texture(noise_tex, vec2(v * 5.3 + 0.2, u * 3.0)).g - 0.5) * 0.14;
	float ew = mix(edge_top, 0.36, smoothstep(0.0, 0.12, v));
	float edge = smoothstep(0.03, ew, u + wob) * smoothstep(0.97, 1.0 - ew, u + wob);
	float top = smoothstep(0.0, top_fade, v);
	float crest_white = 1.0 - smoothstep(0.0, 0.10, v);
	float base_white = smoothstep(0.90, 1.0, v) * 0.55;
	float lace = smoothstep(0.66, 0.94, s3) * 0.30 * (0.3 + 0.7 * v);   // 細碎白絲，越往下越多
	float a = edge * top * mix(0.08, 0.90, strand);
	a = clamp(a + (crest_white * 0.28 + base_white * 0.18) * edge, 0.0, 1.0);
	a *= mix(1.0, 0.80, v);
	// V1.2 D：水幕底緣在潭面下 0.1 m 與水面相交，原本 v=1 仍不透明 → 一條筆直的交線。最後 6 % 淡出，交給潭面的落水泡沫接手
	a *= 1.0 - smoothstep(0.94, 1.0, v);
	vec3 col = mix(deep_col, water_col, clamp(strand * 1.15, 0.0, 1.0));
	col = mix(col, vec3(0.95, 0.98, 0.99), clamp(crest_white * 0.7 + base_white * 0.30 + lace + mainw * 0.22 + film * 0.9, 0.0, 0.90));
	ALBEDO = col;
	ALPHA = a * alpha_k;
	ROUGHNESS = 0.28;
	SPECULAR = 0.45;
	EMISSION = col * 0.06;
}
