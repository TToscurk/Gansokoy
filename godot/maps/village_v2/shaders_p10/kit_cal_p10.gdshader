// P10 R6a albedo pilot：V2_MachiyaKit（StandardMaterial3D）的等價 shader＋依 atlas 色階分類的 albedo 係數。
// 由 tools/village_v2_albedo_pilot_lib.gd 產生，勿手改。原材質：albedo_color 0.42 灰、albedo_texture＝machiya_kit_atlas、
// vertex_color_use_as_albedo、roughness 0.9、emission（白）× emission_texture × 0.4（MULTIPLY）、cull back、linear mipmap。
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

float s2l(float c) {
	return c < 0.04045 ? c * (1.0 / 12.92) : pow((c + 0.055) * (1.0 / 1.055), 2.4);
}

float l2s(float c) {
	return c < 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb * COLOR.rgb;   // 線性（source_color 已轉線性；頂點色＝線性）
	float l = l2s(dot(base, vec3(0.2126, 0.7152, 0.0722)));
	float k = mix(k_dark, k_mid, smoothstep(band_dark.x, band_dark.y, l));
	k = mix(k, k_light, smoothstep(band_light.x, band_light.y, l));
	ALBEDO = base * s2l(k);
	ROUGHNESS = roughness_v;
	EMISSION = texture(emit_tex, UV).rgb * emission_energy;
}
