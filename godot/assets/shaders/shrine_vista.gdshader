// 博麗神社 r3 中景／遠景地面：林冠質感（近景範圍外沒有真的樹）。
// 世界 xz 平面投影（遠景坡度小）；canopy_far.png 是可無縫平鋪的樹冠團塊貼圖（一像素 ≈ 0.22 m）。
// 遮罩 mask_tex（UV = 網格 0..1）：G＝森林密度（小＝草坡空地）、B＝大尺度明暗。
shader_type spatial;

uniform sampler2D canopy : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_tex : filter_linear_mipmap;
uniform float tile = 0.0045;                       // 1 / 222 m
uniform vec3 meadow_tint : source_color = vec3(0.50, 0.62, 0.34);
uniform float meadow_amount : hint_range(0.0, 1.0) = 0.6;

varying vec3 wpos;
varying vec2 map_uv;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_uv = UV;
}

void fragment() {
	vec2 uv = wpos.xz * tile;
	vec3 c1 = texture(canopy, uv).rgb;
	vec3 c2 = texture(canopy, uv * 2.7 + vec2(0.37, 0.61)).rgb;
	vec3 can = mix(c1, c2, 0.4);
	vec4 mk = texture(mask_tex, map_uv);
	float forest = smoothstep(0.12, 0.42, mk.g);
	float lum = dot(can, vec3(0.333));
	vec3 meadow = mix(can, vec3(lum) * meadow_tint * 2.4, meadow_amount);
	vec3 col = mix(meadow, can, forest);
	col *= mix(0.82, 1.14, mk.b);
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
