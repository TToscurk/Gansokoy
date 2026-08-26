// 風吹草 —— 頂點沿高度加權搖擺；相位吃世界座標所以每簇錯開，
// 疊一層低頻「陣風」讓整片草地有波浪掃過的隨機感。
// 顏色來自頂點色（根暗尖亮烤在 mesh 裡）。
shader_type spatial;
render_mode cull_disabled;

uniform float sway_strength = 0.10;
uniform float sway_speed = 1.7;
uniform float gust_strength = 0.14;

varying vec3 vcol;

void vertex() {
	vcol = COLOR.rgb;
	// 根部 y=0 不動、愈往尖端擺愈多
	float h = clamp(VERTEX.y / 0.4, 0.0, 1.6);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ph = wp.x * 0.9 + wp.z * 1.1;
	// 高頻細顫 + 低頻陣風（陣風沿 x 方向掃過草原）
	float flutter = sin(TIME * sway_speed + ph) * 0.6
		+ sin(TIME * sway_speed * 2.33 + ph * 1.7) * 0.4;
	float gust = pow(0.5 + 0.5 * sin(TIME * 0.55 - wp.x * 0.045 + sin(wp.z * 0.07) * 1.3), 2.0);
	float amp = sway_strength * flutter + gust_strength * gust;
	VERTEX.x += amp * h;
	VERTEX.z += (0.5 * cos(TIME * sway_speed * 0.77 + ph) * sway_strength + 0.35 * gust_strength * gust) * h;
}

void fragment() {
	ALBEDO = vcol;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	// 葉片一律朝上打光，跟地面一致 —— 放 fragment 才不會被背面
	// 自動翻法線弄成朝下（症狀：散落的黑色草簇）
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
