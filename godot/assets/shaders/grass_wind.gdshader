// 風吹草 —— 頂點沿高度加權搖擺；相位吃世界座標所以每簇錯開。
// Wind V1：方向／強度／陣風改吃 Wind autoload 的 global uniform（trail／kourindou／slice 共用），
//   本檔的 sway_strength／gust_strength 退成「這個材質的振幅」。
// 顏色來自頂點色（根暗尖亮烤在 mesh 裡）。
shader_type spatial;
render_mode cull_disabled;

uniform float sway_strength = 0.10;
uniform float sway_speed = 1.7;
uniform float gust_strength = 0.14;

#include "res://assets/shaders/wind_field.gdshaderinc"
// Wind V1.2：物種（預設 grass）
instance uniform int wind_species = 6;

varying vec3 vcol;

// 世界向量→局部（等比縮放＋旋轉；省掉逐頂點 mat4 反矩陣）
vec3 to_local(vec3 v, mat4 m) {
	return vec3(dot(v, m[0].xyz), dot(v, m[1].xyz), dot(v, m[2].xyz));
}

void vertex() {
	vcol = COLOR.rgb;
	// 根部 y=0 不動、愈往尖端擺愈多。Wind V1.2：權重＝pow(局部高度正規化, tip_response)，
	//   以叢內最高葉（0.4 m×1.6）為 1 —— 最高葉尖的振幅與 V1 相同，下段改成彎曲曲線（不是線性剪切）。
	vec4 r0;
	vec4 r1;
	vec4 r2;
	wf_species(wind_species, r0, r1, r2);
	float hn = clamp(VERTEX.y / 0.64, 0.0, 1.0);
	float h = 1.6 * pow(hn, r0.z) * (1.0 - 0.8 * r0.x) / 0.72;
	vec3 root = MODEL_MATRIX[3].xyz;
	float sc = length(MODEL_MATRIX[1].xyz);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 o = vec3(0.0);
	float dm = distance(MAIN_CAM_INV_VIEW_MATRIX[3].xyz, wp);
	if ((gw_strength > 0.0 || gw_ctrl.x * gw_ctrl.y > 0.001) && dm < 45.0) {
		vec3 fld = wf_field(root.xz);
		vec2 wd2 = fld.xy;
		// 草＝垂直剖面的正規化高度 z0（×1.00）：只乘海拔與遮蔽（樹冠才吃剖面增益）
		float env = wf_elev_factor(root.y) * wf_shelter(root.xz, root.y + 0.4 * sc);
		float t = gw_time;
		// 草沒有樹冠層：單點驅動力＋純延遲 lag（不查樹冠響應表，省頂點成本）
		float drive = wf_force(root.xz, wd2, fld.z, env, t, r0.w);
		float ph = wp.x * 0.9 + wp.z * 1.1 + wp.y * 0.4;
		// 高頻細顫 + 低頻草浪（沿風向掃過草原）
		float flutter = sin(t * sway_speed + ph) * 0.6
			+ sin(t * sway_speed * 2.33 + ph * 1.7) * 0.4;
		float along = dot(wp.xz, wd2);
		float across = dot(wp.xz, vec2(-wd2.y, wd2.x));
		float gust = pow(0.5 + 0.5 * sin(t * 0.55 - along * 0.045 + sin(across * 0.07) * 1.3), 2.0);
		// BREEZE（drive≈0.55）＝原本的外觀；陣風（行進事件）時整片更倒、細顫更快
		float gscale = r0.y * drive / 0.55;
		float amp = (sway_strength * flutter * gw_flutter + gust_strength * gust * (1.0 + 1.2 * clamp(drive - gw_strength, 0.0, 1.0))) * gscale;
		o = vec3(wd2.x, 0.0, wd2.y) * amp * h;
		o += vec3(-wd2.y, 0.0, wd2.x) * amp * 0.35 * cos(t * sway_speed * 0.77 + ph) * h;
		o.y -= length(o.xz) * 0.25 * h;
		o = wf_soft_clamp(o, r1.z * sc);
	}
	if (gw_ctrl.z > 0.5) {
		vcol = vec3(length(o) / 0.6);
	}
	VERTEX += to_local(o, MODEL_MATRIX) / max(dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz), 1e-6);
}

void fragment() {
	ALBEDO = vcol;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	// 葉片一律朝上打光，跟地面一致 —— 放 fragment 才不會被背面
	// 自動翻法線弄成朝下（症狀：散落的黑色草簇）
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	if (gw_ctrl.z > 0.5) {
		ALBEDO = vec3(0.0);
		EMISSION = wf_heat(vcol.r * 0.6);
	}
}
