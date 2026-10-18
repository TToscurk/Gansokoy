// 人間之里 V2 P9 R1：植被庫樹皮（9 種樹皮共用；材質實例只換貼圖）。說明見 veg_common.gdshaderinc。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://assets/village_v2/veg_kit/veg_common.gdshaderinc"

void vertex() {
	float wdisp;
	v_lod_d = veg_vertex_common(VERTEX, NORMAL, UV2, 0.0, MODEL_MATRIX, MAIN_CAM_INV_VIEW_MATRIX, gw_time, 3.0, wdisp);
	if (gw_ctrl.z > 0.5) {
		COLOR = vec4(wdisp / 0.6, 0.0, 0.0, COLOR.a);
	}
}

void fragment() {
	if (veg_lod_reject(FRAGCOORD.xy)) {
		discard;
	}
	vec3 c = texture(albedo_tex, UV).rgb;
	if (OUTPUT_IS_SRGB) {
		c = veg_s2l(c);
	}
	vec3 lin = c * COLOR.rgb * albedo_mul;
	ALBEDO = OUTPUT_IS_SRGB ? veg_l2s(lin) : lin;
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
