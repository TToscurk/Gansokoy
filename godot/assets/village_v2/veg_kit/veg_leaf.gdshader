// 人間之里 V2 P9 R1：植被庫葉卡（葉叢 atlas VL_A／VL_B 共用；材質實例只換貼圖）。說明見 veg_common.gdshaderinc。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://assets/village_v2/veg_kit/veg_common.gdshaderinc"

uniform float alpha_cut = 0.5;
// 遠距 mip 會把 alpha 平均掉 → 卡片越遠越瘦；依 mip 等級補回覆蓋率（保住遠景 silhouette）
uniform float alpha_mip_boost = 0.18;
uniform float translucency = 0.35;
// 1＝背面也用匯出的樹冠球狀法線（cull_disabled 時引擎會在背面把法線翻向相機，這裡翻回來）
uniform float crown_normal = 1.0;

void vertex() {
	float wdisp;
	v_lod_d = veg_vertex_common(VERTEX, NORMAL, UV2, COLOR.a, MODEL_MATRIX, MAIN_CAM_INV_VIEW_MATRIX, gw_time, 1.0, PROJECTION_MATRIX[3][3], wdisp);
	if (gw_ctrl.z > 0.5) {
		COLOR = vec4(wdisp / 0.6, 0.0, 0.0, COLOR.a);
	}
}

void fragment() {
	if (veg_lod_reject(FRAGCOORD.xy)) {
		discard;
	}
	vec4 a = texture(albedo_tex, UV);
	vec3 c = a.rgb;
	if (OUTPUT_IS_SRGB) {
		c = veg_s2l(c);
	}
	vec3 lin = c * COLOR.rgb * albedo_mul * leaf_tint;
	lin = mix(vec3(dot(lin, vec3(0.2126, 0.7152, 0.0722))), lin, leaf_sat);
	vec2 tp = UV * vec2(textureSize(albedo_tex, 0));
	float lod = 0.5 * log2(max(max(dot(dFdx(tp), dFdx(tp)), dot(dFdy(tp), dFdy(tp))), 1e-8));
	ALPHA = a.a * (1.0 + max(lod, 0.0) * alpha_mip_boost);
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	if (!FRONT_FACING) {
		NORMAL = mix(NORMAL, -NORMAL, crown_normal);
	}
	ALBEDO = OUTPUT_IS_SRGB ? veg_l2s(lin) : lin;
	BACKLIGHT = ALBEDO * translucency;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	// Wind 除錯熱圖（gw_ctrl.z==1）：位移長度（vertex 寫在 COLOR.r）→灰階 emission
	if (gw_ctrl.z > 0.5) {
		ALBEDO = vec3(0.0);
		EMISSION = wf_heat(COLOR.r * 0.6);
	}
}
