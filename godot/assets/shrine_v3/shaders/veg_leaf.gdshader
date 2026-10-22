// 博麗神社 v3 葉卡 shader：人里 V2 P9 R1 共用葉卡 shader（res://assets/village_v2/veg_kit/veg_leaf.gdshader）的 v3 版本。
// 檔名必須維持 veg_leaf.gdshader：Wind autoload 用檔名（resource_path.get_file()）判斷「樹」並接風（scripts/wind.gd VEG_TREE_SHADERS）。
// 風、LOD、色彩變體全部沿用共用的 veg_common.gdshaderinc（只讀 include），與共用版只差一處：
//
//   陰影 pass 的葉卡 alpha（2026-10-23 光照診斷，docs/shrine_v3/02_植被光照診斷.md）
//   共用版在陰影 pass 也做「遠距 mip alpha 補償」——陰影圖一格 4–8 cm、葉卡貼圖一格 2–4 mm，
//   補償倍率 ×1.5–1.9 且 mip 平均把葉隙填滿 → 樹冠在陰影圖裡變成實心團塊，朝陽的外層葉卡也被自己的樹冠遮掉
//   45–75 % 的直射光（實測：外緣朝陽葉卡實得直射只有 Lambert 預期的 27–55 %），整棵樹只剩天空光照亮，
//   看起來像不受太陽影響、自己發亮。
//   v3 版：陰影 pass（正射投影）改取 shadow_alpha_lod 這一級 mip 的原始 alpha、不做補償 → 陰影圖保留葉隙，
//   光從葉隙穿進樹冠；相機 pass 完全不變（遠景剪影照舊補償）。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://assets/village_v2/veg_kit/veg_common.gdshaderinc"

uniform float alpha_cut = 0.5;
// 遠距 mip 會把 alpha 平均掉 → 卡片越遠越瘦；依 mip 等級補回覆蓋率（保住遠景 silhouette）。只用在相機 pass。
uniform float alpha_mip_boost = 0.18;
uniform float translucency = 0.35;
// 1＝背面也用匯出的樹冠球狀法線（cull_disabled 時引擎會在背面把法線翻向相機，這裡翻回來）
uniform float crown_normal = 1.0;
// 陰影 pass 取哪一級 mip 的 alpha（0＝原圖：保留葉隙）；< 0＝與相機 pass 相同（＝共用版行為）
uniform float shadow_alpha_lod = 0.0;

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
	// 方向光陰影 pass 是正射投影（同 veg_vertex_common 的判斷）；相機永遠是透視
	bool shadow_pass = PROJECTION_MATRIX[3][3] > 0.5 && shadow_alpha_lod >= 0.0;
	if (shadow_pass) {
		ALPHA = textureLod(albedo_tex, UV, shadow_alpha_lod).a;
		ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	} else {
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
}
