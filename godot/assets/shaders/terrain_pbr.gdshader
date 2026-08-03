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
uniform sampler2D mask_tex : filter_linear_mipmap;
uniform float tile = 0.12;          // 世界座標 → 細節紋理 UV
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
	col = mix(col, texture(forest_diff, duv * 1.4).rgb, m.g);
	nor = mix(nor, texture(forest_nor, duv * 1.4).rgb, m.g);
	// 石徑
	col = mix(col, texture(path_diff, duv * 0.8).rgb, m.r);
	nor = mix(nor, texture(path_nor, duv * 0.8).rgb, m.r);
	// 大尺度明暗打破平舖感
	col *= mix(0.82, 1.12, m.b);
	ALBEDO = col;
	NORMAL_MAP = nor;
	NORMAL_MAP_DEPTH = 1.1;
	ROUGHNESS = mix(0.95, 0.9, m.r);
}
