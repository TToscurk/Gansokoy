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
uniform float dirt_tile = 2.6;
// terrain_path 那張本身偏紅褐（落葉土），直接用會讓廣場看起來鋪了一層樹皮屑。
// 踏み固めた土是灰黃的。
uniform vec3 dirt_tint : source_color = vec3(1.0, 1.0, 1.0);
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
	float dw = texture(mask_tex, map_uv).a * dirt_amount;
	vec3 dcol = texture(dirt_diff, duv * dirt_tile).rgb;
	// 那張貼圖是紅褐色的腐葉土，直接鋪出來像撒了一地樹皮屑。
	// 踏み固めた土偏灰 —— 先往灰階拉一半，再上色調。
	dcol = mix(vec3(dot(dcol, vec3(0.299, 0.587, 0.114))), dcol, 0.45) * dirt_tint;
	col = mix(col, dcol, dw);
	nor = mix(nor, texture(dirt_nor, duv * dirt_tile).rgb, dw);
	// 石徑
	col = mix(col, texture(path_diff, duv * path_tile).rgb, m.r);
	nor = mix(nor, texture(path_nor, duv * path_tile).rgb, m.r);
	// 大尺度明暗打破平舖感
	col *= mix(0.82, 1.12, m.b);
	ALBEDO = col;
	NORMAL_MAP = nor;
	NORMAL_MAP_DEPTH = 1.1;
	ROUGHNESS = mix(0.95, 0.9, m.r);
}
