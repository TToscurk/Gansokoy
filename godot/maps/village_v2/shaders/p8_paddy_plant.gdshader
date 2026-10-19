// P8 Farmland pilot r4：秧苗／田埂雜草（頂點色＝sRGB；UV.y＝葉片高度比例 0 基部 → 1 葉尖）。
// MultiMesh 秧苗叢：頂點色＝灰階＋葉尖偏黃漸層，每株葉色由 instance color 給（引擎相乘進 COLOR）。
// 法線自己給（世界空間、偏上；MODEL_MATRIX 已含 instance 變換），雙面渲染時背面不會被翻黑；
// 基部壓暗＝水中陰影；葉尖輕微隨風擺動（世界公尺，換回 local 以免被叢的縮放放大）。
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float sway = 0.035;

// 風 V1：方向／強度／陣風吃 Wind autoload 的 global uniform；sway 是這個材質的振幅倍率。
#include "res://assets/shaders/wind_field.gdshaderinc"
// Wind V1.2：物種（預設 paddy）
instance uniform int wind_species = 7;

varying vec3 wn;

vec3 s2l(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

vec3 l2s(vec3 c) {
	return mix(vec3(1.055) * pow(c, vec3(1.0 / 2.4)) - vec3(0.055), c * 12.92, lessThan(c, vec3(0.0031308)));
}

// 世界向量→局部（等比縮放＋旋轉；省掉逐頂點 mat4 反矩陣）
vec3 to_local(vec3 v, mat4 m) {
	return vec3(dot(v, m[0].xyz), dot(v, m[1].xyz), dot(v, m[2].xyz));
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 r0;
	vec4 r1;
	wf_species_grass(wind_species, r0, r1);
	// 高度權重：UV.y＝作者烘的葉片高度比例（不是世界 Y）；paddy tip_response 2.0＝V1 的 UV.y²
	float k = pow(clamp(UV.y, 0.0, 1.0), r0.z) * (1.0 - 0.8 * r0.x) / 0.68;
	vec3 root = MODEL_MATRIX[3].xyz;
	float sc = length(MODEL_MATRIX[1].xyz);
	vec3 o = vec3(0.0);
	float dm = distance(MAIN_CAM_INV_VIEW_MATRIX[3].xyz, w);
	if ((gw_strength > 0.0 || gw_ctrl.x * gw_ctrl.y > 0.001) && dm < 45.0 && wf_tex_ok()) {
		// 場（Wind V2 效能版：共用風場貼圖）
		vec2 wd2;
		float g_warp;
		float g_force;
		float g_mod;
		wf_tex_grass(wind_species, root.xz, wd2, g_warp, g_force, g_mod);
		vec3 wd = vec3(wd2.x, 0.0, wd2.y);
		vec3 side = vec3(-wd2.y, 0.0, wd2.x);
		// 草＝垂直剖面的正規化高度 z0（×1.00）：只乘海拔與遮蔽（樹冠才吃剖面增益）
		float env = wf_elev_factor(root.y) * wf_shelter(root.xz, root.y + 0.45 * sc);
		// 草沒有樹冠層：單點驅動力＋純延遲 lag（不查樹冠響應表，省頂點成本）
		float drive = env * g_force;
		// 沿風向推進的草浪（相位吃世界座標）＋葉片自己的細顫
		float along = dot(w.xz, wd2);
		float across = dot(w.xz, vec2(-wd2.y, wd2.x));
		float wave = 0.5 + 0.5 * sin(along * 0.42 - gw_time * 1.55 + sin(across * 0.11) * 1.6);
		float flut = sin(gw_time * WF_TAU * r1.y + w.x * 1.7 + w.z * 2.3);
		float amp = sway * 2.2 * r0.y * drive;
		o = wd * amp * k * (0.45 + 0.75 * wave)
			+ side * amp * 0.35 * k * flut * gw_flutter;
		o.y -= length(o.xz) * 0.25 * k;
		o = wf_soft_clamp(o, r1.z * sc);
	}
	if (gw_ctrl.z > 0.5) {
		COLOR = vec4(length(o) / 0.6, 0.0, 0.0, 1.0);
	}
	VERTEX += to_local(o, MODEL_MATRIX) / max(dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz), 1e-6);
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = s2l(clamp(COLOR.rgb, vec3(0.0), vec3(1.0))) * mix(0.45, 1.0, smoothstep(0.0, 0.35, UV.y));
	ALBEDO = OUTPUT_IS_SRGB ? l2s(c) : c;
	ROUGHNESS = 0.72;
	SPECULAR = 0.35;
	BACKLIGHT = c * 0.25;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	if (gw_ctrl.z > 0.5) {
		ALBEDO = vec3(0.0);
		EMISSION = wf_heat(COLOR.r * 0.6);
	}
}
