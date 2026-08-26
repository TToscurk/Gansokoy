// 寫實地形：草地 / 腐葉土 / 石徑 三層 PBR 混合。
// 混合權重烤在 mask 貼圖（R=路徑、G=林床、B=大尺度明暗）；
// 細節紋理是 Poly Haven CC0（assets/textures/，terrain_* 系列）。
shader_type spatial;

uniform sampler2D grass_diff : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_nor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_diff : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_nor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D path_diff : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D path_nor : hint_normal, filter_linear_mipmap, repeat_enable;
// 第四層：踏み固めた土（院子、廣場）。人里的中庭鋪成翠綠草皮看起來像
// 高爾夫球場 —— 有人天天走的地方不長草。mask 的 A 通道是它的權重；
// 沒有第四層的地圖傳 RGB8（取樣 A 恆為 1），靠 dirt_amount=0 關掉。
uniform sampler2D dirt_diff : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_nor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float dirt_amount = 0.0;
// 村落可選的全域土覆蓋。只換表面權重，不改地形網格、道路高度或碰撞。
// 0 維持既有四層遮罩；1 讓整片 Terrain 讀成夯土並完全壓掉石板。
uniform float dirt_cover = 0.0;
uniform float dirt_tile = 2.6;
// terrain_path 那張本身偏紅褐（落葉土），直接用會讓廣場看起來鋪了一層樹皮屑。
// 踏み固めた土是灰黃的。
uniform vec3 dirt_tint : source_color = vec3(1.0, 1.0, 1.0);
// 全土村落可把原始腐葉土貼圖降成低對比細節，讓主色讀成乾燥夯土。
// 預設 texture_strength=1 保持其他地圖既有外觀；只有人里覆寫。
uniform vec3 dirt_base_color : source_color = vec3(0.0);
uniform float dirt_texture_strength : hint_range(0.0, 1.0) = 1.0;
uniform float dirt_normal_strength : hint_range(0.0, 1.0) = 0.45;
// 只在明確要求直接呈現指定圖片時開啟；預設 0 保持其他地圖原有土色處理。
uniform float dirt_raw_texture : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D mask_tex : filter_linear_mipmap;
uniform float tile = 0.12;          // 世界座標 → 細節紋理 UV
// 三層各自的密度倍率。石徑不能跟草用同一個 —— tile 0.12 * 0.8 是
// 「一次貼圖鋪 10 公尺」，石板貼圖大概 6 顆石頭，於是每顆石頭 1.7m 見方，
// 走在上面像走在停車場的水泥塊上。石板要細，草可以粗。
uniform float path_tile = 4.2;
uniform float forest_tile = 1.4;
uniform vec3 grass_tint : source_color = vec3(1.0, 1.0, 1.0);

varying vec3 wpos;
varying vec2 map_uv;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_uv = UV;
}

void fragment() {
	vec2 duv = wpos.xz * tile;
	vec3 m = texture(mask_tex, map_uv).rgb;
	vec3 col = texture(grass_diff, duv).rgb * grass_tint;
	vec3 nor = texture(grass_nor, duv).rgb;
	// 林床（往魔法之森愈濃）
	col = mix(col, texture(forest_diff, duv * forest_tile).rgb, m.g);
	nor = mix(nor, texture(forest_nor, duv * forest_tile).rgb, m.g);
	// 踏み固めた土（先鋪，石板要壓在它上面）
	float global_dirt = clamp(dirt_cover, 0.0, 1.0);
	float dw = max(texture(mask_tex, map_uv).a * dirt_amount, global_dirt);
	// 全土模式把細砂礫放大一點，並疊一層同貼圖的低頻採樣；避免近看像
	// 鬆散碎石，仍保留天然深淺與細粒，不增加新的材質或貼圖資源。
	float dirt_uv_scale = mix(dirt_tile, dirt_tile * 0.62, global_dirt);
	vec3 dcol_raw = texture(dirt_diff, duv * dirt_tile).rgb;
	vec3 dcol = texture(dirt_diff, duv * dirt_uv_scale).rgb;
	vec3 dcol_wide = texture(dirt_diff,
		duv * dirt_uv_scale * 0.41 + vec2(17.3, -9.1)).rgb;
	dcol = mix(dcol_wide, dcol, 0.50);
	// 那張貼圖是紅褐色的腐葉土，直接鋪出來像撒了一地樹皮屑。
	// 踏み固めた土偏灰 —— 先往灰階拉一半，再上色調。
	dcol = mix(vec3(dot(dcol, vec3(0.299, 0.587, 0.114))), dcol, 0.45) * dirt_tint;
	dcol = mix(dirt_base_color, dcol, dirt_texture_strength);
	dcol = mix(dcol, dcol_raw, dirt_raw_texture);
	// 舊道路遮罩只留下踩踏分區：主要通道較淺、路邊與樹下略深；
	// 它不再帶入石板紋理，也不改道路幾何。
	dcol *= mix(1.0 + global_dirt * mix(-0.035, 0.10, m.r), 1.0, dirt_raw_texture);
	col = mix(col, dcol, dw);
	nor = mix(nor, texture(dirt_nor, duv * dirt_tile).rgb, dw);
	// 石徑
	float path_w = m.r * (1.0 - global_dirt);
	col = mix(col, texture(path_diff, duv * path_tile).rgb, path_w);
	nor = mix(nor, texture(path_nor, duv * path_tile).rgb, path_w);
	// 大尺度明暗打破平舖感；全土村落收斂到 12%，遠看維持乾淨平整。
	float macro_low = mix(0.82, 0.94, global_dirt);
	float macro_high = mix(1.12, 1.06, global_dirt);
	col *= mix(mix(macro_low, macro_high, m.b), 1.0, dirt_raw_texture);
	ALBEDO = col;
	NORMAL_MAP = nor;
	NORMAL_MAP_DEPTH = mix(1.1, dirt_normal_strength, global_dirt);
	// 全土模式仍沿用烤好的低頻遮罩，讓乾濕／踩踏感有細微粗糙度起伏。
	float dirt_roughness = mix(0.94, 0.98, m.b) - m.r * global_dirt * 0.02;
	ROUGHNESS = mix(mix(0.95, 0.9, m.r), dirt_roughness, global_dirt);
}
