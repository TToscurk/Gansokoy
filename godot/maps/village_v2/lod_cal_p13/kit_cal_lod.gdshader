// P13 W8 TASK B：LOD1／LOD2 町家 atlas 材質（按建築調色盤分類）。kit_cal.gdshader（P10 R6a・封存）の複製に、色の乗数だけを足したもの。
// 原因（W8 実測 evidence/albedo_probe_batch.json）：LOD1／LOD2 の壁箱 l_box は atlas の『米白』1 格（#E8E0CF）を引くだけで、どの建物も同じ 0.36／0.33／0.28、
// LOD0 の灰泥（Plaster_K 変体×頂点色）は 0.15／0.10／0.05 級の暖色 → LOD 切替で壁の色相と明るさが跳ぶ。LOD1 の正面（l_f*）は逆に暗すぎる。
// 乗数は建物ごとに『LOD0 の対応部位の面積加重平均 albedo ÷ その LOD の現在値』で擬合し、調色盤へ丸めたもの（tools/p13/w8/w8_lod_fit.py）。
//   box_mul  ：壁箱の格（atlas の #E8E0CF）の画素にかける線形乗数
//   face_mul ：atlas の格の外（正面・窓の絵）の画素にかける線形乗数
//   roof_mode：true の材質は屋根専用（l_rh_*）。ALBEDO＝base × roof_k（原 V2_MachiyaKit の 0.42 灰＝線形 0.1413 を LOD0 の瓦に合わせ直したもの）
// 3 つとも既定（box_mul＝face_mul＝1・roof_mode＝false）なら kit_cal.gdshader と同じ出力。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D emit_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float k_dark = 0.75;
uniform float k_mid = 0.42;
uniform float k_light = 0.70;
uniform vec2 band_dark = vec2(0.26, 0.34);
uniform vec2 band_light = vec2(0.55, 0.70);
uniform float roughness_v = 0.9;
uniform float emission_energy = 0.4;
uniform vec3 box_mul = vec3(1.0);
uniform vec3 face_mul = vec3(1.0);
uniform bool roof_mode = false;
uniform vec3 roof_k = vec3(0.1413);

float s2l(float c) {
	return c < 0.04045 ? c * (1.0 / 12.92) : pow((c + 0.055) * (1.0 / 1.055), 2.4);
}

float l2s(float c) {
	return c < 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb * COLOR.rgb;
	if (roof_mode) {
		ALBEDO = base * roof_k;
	} else {
		float l = l2s(dot(base, vec3(0.2126, 0.7152, 0.0722)));
		float k = mix(k_dark, k_mid, smoothstep(band_dark.x, band_dark.y, l));
		k = mix(k, k_light, smoothstep(band_light.x, band_light.y, l));
		// atlas の swatch 領域（右 1/4・y 0.5–0.625）。壁箱は #E8E0CF の格（x 0.875–0.9375・y 0.5–0.5625）。それ以外の swatch 格（木・瓦の色）は不変
		bool in_swatch = UV.x > 0.75 && UV.y > 0.5 && UV.y < 0.625;
		bool wall_cell = in_swatch && UV.x > 0.875 && UV.x < 0.9375 && UV.y < 0.5625;
		vec3 tint = vec3(1.0);
		if (wall_cell) {
			tint = box_mul;
		} else if (!in_swatch) {
			tint = face_mul;
		}
		ALBEDO = base * s2l(k) * tint;
	}
	ROUGHNESS = roughness_v;
	EMISSION = texture(emit_tex, UV).rgb * emission_energy;
}
