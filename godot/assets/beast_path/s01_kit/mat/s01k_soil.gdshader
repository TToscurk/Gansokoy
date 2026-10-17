// 獸道 S01 R6：耕地的土（畝・溝）。S01 專用；地面貼圖陣列（village_v2 P7）唯讀引用，層：2 trodden（乾土）、4 mud（濕土）。
// 頂點資料（tools/beast_path/s01_arch.gd 的 _field_soil）：COLOR.r＝溝（濕）、COLOR.g＝畝頂（乾、耕起的土塊）、COLOR.b＝外緣（往草地過渡）、COLOR.a＝塊狀雜訊。
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrh_arr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float ground_k = 0.26;
uniform float tile = 1.7;
uniform vec3 dry_tint : source_color = vec3(0.93, 0.90, 0.85);
uniform vec3 wet_tint : source_color = vec3(0.50, 0.47, 0.45);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz / tile;
	vec2 p2 = wpos.xz / (tile * 2.9) + vec2(0.37, 0.61);
	vec3 dry = mix(texture(albedo_arr, vec3(p, 2.0)).rgb, texture(albedo_arr, vec3(p2, 2.0)).rgb, 0.35);
	vec3 wet = mix(texture(albedo_arr, vec3(p, 4.0)).rgb, texture(albedo_arr, vec3(p2, 4.0)).rgb, 0.35);
	vec4 nb = texture(noise_tex, wpos.xz / 3.1);
	float w = clamp(COLOR.r * 0.85 + (nb.r - 0.5) * 0.3, 0.0, 1.0);
	vec3 alb = mix(dry * dry_tint, wet * wet_tint, w);
	alb *= mix(0.86, 1.08, COLOR.a) * mix(0.9, 1.05, nb.b);
	alb *= mix(0.92, 1.10, COLOR.g);
	alb = mix(alb, alb * vec3(0.9, 0.95, 0.9), COLOR.b);              // 外緣：踩實、帶點草色
	ALBEDO = alb * ground_k;
	vec4 nr = texture(nrh_arr, vec3(p, mix(2.0, 4.0, step(0.5, w))));
	NORMAL_MAP = vec3(nr.rg, 1.0);
	NORMAL_MAP_DEPTH = 1.2;
	ROUGHNESS = mix(0.95, 0.78, w);
	SPECULAR = 0.25;
}
