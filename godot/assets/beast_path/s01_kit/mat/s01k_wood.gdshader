// 獸道 S01 Blender 環境資產 Kit 的木材質（R4 Demo）：倒木、斷枝、露根。
// 樹皮貼圖重用 village_v2 veg_kit 的 VB_*（唯讀引用）；UV 是公尺（Blender 端：繞一圈＝周長、沿長度＝弧長）。
// COLOR.rgb：白＝樹皮；偏米色＝斷面／木刺（新鮮木色）。苔：朝上的面＋低頻斑（instance uniform moss_k 控制量）。
// 腳邊：靠地面的部分變暗、帶土色（instance uniform ground_y＝這件的貼地高度，世界座標）。
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D bark_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float uv_m = 0.85;                                     // 樹皮貼圖一格多少公尺
uniform vec3 bark_tint : source_color = vec3(0.86, 0.80, 0.74);
uniform vec3 wood_col : source_color = vec3(0.62, 0.52, 0.38);
uniform vec3 moss_col : source_color = vec3(0.25, 0.33, 0.10);
uniform vec3 soil_col : source_color = vec3(0.17, 0.13, 0.09);
uniform float normal_depth = 1.0;
instance uniform float moss_k = 0.5;
instance uniform float ground_y = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV / uv_m;
	vec3 bark = texture(bark_alb, uv).rgb * bark_tint;
	float endg = 1.0 - smoothstep(0.92, 0.99, min(COLOR.r, min(COLOR.g, COLOR.b)));   // 斷面（頂點色不是白）
	vec3 N = normalize(wnrm);
	vec4 nb = texture(noise_tex, wpos.xz / 5.0 + wpos.y / 9.0);
	vec4 nm = texture(noise_tex, wpos.xz / 1.3 + vec2(wpos.y / 1.1, 0.7));
	vec3 grain = wood_col * mix(0.75, 1.15, texture(bark_alb, vec2(uv.x * 0.15, uv.y * 3.0)).r);
	vec3 alb = mix(bark, grain * COLOR.rgb * 1.1, endg);
	// 苔：朝上的面、斑駁
	float up = smoothstep(0.05, 0.75, N.y + (nm.r - 0.5) * 0.5);
	float mm = moss_k * up * smoothstep(0.30, 0.62, nb.g * 0.7 + nm.g * 0.5);
	vec3 mcol = moss_col * mix(0.7, 1.3, nm.b);
	alb = mix(alb, mcol, clamp(mm * 1.3, 0.0, 0.92) * (1.0 - endg * 0.7));
	// 腳邊：貼地 0.25 m 內變暗＋土色
	float foot = 1.0 - smoothstep(0.0, 0.25, wpos.y - ground_y + (nm.r - 0.5) * 0.08);
	alb = mix(alb, soil_col * mix(0.8, 1.2, nb.r), foot * 0.7);
	ALBEDO = alb;
	vec3 tn = texture(bark_nrm, uv).xyz * 2.0 - 1.0;
	NORMAL_MAP = texture(bark_nrm, uv).xyz;
	NORMAL_MAP_DEPTH = normal_depth * (1.0 - endg) * (1.0 - mm * 0.7);
	ROUGHNESS = mix(0.88, 0.97, mm);
	SPECULAR = 0.25;
	AO = mix(1.0, 0.6, foot);
	AO_LIGHT_AFFECT = 0.5;
}
