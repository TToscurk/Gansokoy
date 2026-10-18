// 幻想鄉全域水面場 V2（WIND_V2_REVIEW）——河面與浮物共用的唯一水面公式（shader 端）。
// CPU 鏡像：scripts/water/water_field.gd（WaterField），兩邊逐項同式；改一邊就改另一邊。
//
// 三個分量（互相獨立，風不會改寫水流方向）：
//   1. 水流（current）：gw_flow 世界座標貼圖（RG＝流速向量 m/s，0.5 為零點、±FLOW_RANGE；B＝在水中 0–1）。
//      由 Wind 從河道中心線（layout_v2.json water.MainRiver pts／half_w，上游→下游）烘出：中央快、近岸慢。
//   2. 長波（undulation）：兩道沿／斜交流向的長波（λ 11 m、7 m），振幅 gw_water.x（預設 2 cm），
//      相位吃世界座標低頻擾動 → 不是整片同步起伏；風大時振幅最多 ×1.6（平滑，跟陣風走）。
//   3. 風漣漪（ripple）：三道沿「當地風向」±扇開的短波（λ 0.9／1.8／3.1 m），振幅 ∝ 當地風力
//      （wf_force：含空間差異與行進陣風 → 陣風掃過水面時漣漪也一道一道變強），並被水流帶著走。
//      漣漪只進法線（網格頂點距 ~2 m 解析不了）；CPU 浮物也吃同一個漣漪高度（低振幅代理）。
//
// global：gw_flow（sampler2D）、gw_flow_rect＝(x0, z0, 1/寬, 1/深)、gw_water＝(長波振幅 m, 漣漪增益, 0, 0)

#ifndef WATER_FIELD_INC
#define WATER_FIELD_INC

#include "res://assets/shaders/wind_field.gdshaderinc"

global uniform sampler2D gw_flow : filter_linear;
global uniform vec4 gw_flow_rect;
global uniform vec4 gw_water;

const float WF_FLOW_RANGE = 2.0;
const float WF_G = 9.81;

// (流速 x, 流速 z, 在水中)
vec3 wf_flow(vec2 p) {
	vec2 uv = (p - gw_flow_rect.xy) * gw_flow_rect.zw;
	if (gw_flow_rect.z <= 0.0 || uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return vec3(0.0);
	}
	vec3 f = textureLod(gw_flow, uv, 0.0).rgb;
	// RGBA8 的 0.5 零點量化成 ±0.008 m/s：水域外（B < 0.02）強制歸零
	return vec3((f.xy - 0.5) * 2.0 * WF_FLOW_RANGE * step(0.02, f.z), f.z);
}

// 當地風力（風場強度單位，env＝1：水面離地 ~0）
float wf_water_wind(vec2 p, float t) {
	vec3 fld = wf_field(p);
	return wf_force(p, fld.xy, fld.z, 1.0, t, 0.0);
}

// 長波高度（m，相對靜水面）。fd＝流向（單位向量）。
float wf_water_long(vec2 p, vec2 fd, float t, float wind) {
	float amp = gw_water.x * (1.0 + 0.6 * clamp(wind / 1.2, 0.0, 1.0));
	vec2 fs = vec2(-fd.y, fd.x);
	float n = sin(p.x * 0.071 + p.y * 0.053) + 0.6 * sin(p.x * -0.043 + p.y * 0.089);
	float h1 = sin(dot(p, fd) * (WF_TAU / 11.0) - t * 1.05 + 1.7 * n);
	float h2 = sin(dot(p, normalize(fd * 0.6 + fs * 0.8)) * (WF_TAU / 7.0) - t * 1.38 + 2.3 * n);
	return amp * (0.6 * h1 + 0.4 * h2);
}

// 風漣漪：回傳 (高度 m, ∂h/∂x, ∂h/∂z)。wdir＝當地風向；flow＝流速（漣漪被水流帶走）。
vec3 wf_water_ripple(vec2 p, vec2 wdir, vec2 flow, float t, float wind) {
	// 風斑（cat's paw）：漣漪強度在水面上成塊、隨風漂移（不是整片同一個規則紋）
	float patch = 0.5 + 0.5 * sin(dot(p, vec2(0.13, 0.07)) - t * 0.6 + 2.0 * sin(p.y * 0.09 + t * 0.2))
		* sin(dot(p, vec2(-0.05, 0.11)) + t * 0.37);
	float a0 = 0.0045 * gw_water.y * clamp(wind, 0.0, 2.0) * (0.25 + 1.1 * patch * patch);
	vec3 acc = vec3(0.0);
	if (a0 <= 0.0) {
		return acc;
	}
	vec2 q = p - flow * t;
	// 三道：λ 0.9／1.8／3.1 m，方向 −0.62／+0.08／+0.71 rad（扇開，避免平行條紋），相速＝深水色散 √(g/k)
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float lam = (i == 0) ? 0.9 : ((i == 1) ? 1.8 : 3.1);
		float ang = (i == 0) ? -0.62 : ((i == 1) ? 0.08 : 0.71);
		vec2 d = vec2(wdir.x * cos(ang) - wdir.y * sin(ang), wdir.x * sin(ang) + wdir.y * cos(ang));
		float k = WF_TAU / lam;
		float c = sqrt(WF_G / k);
		float ph = k * (dot(q, d) - c * t) + fi * 2.1 + 1.6 * sin(dot(p, vec2(0.21, -0.17)) + fi) + 1.1 * sin(dot(p, vec2(-0.09, 0.27)) - fi * 1.3);
		float a = a0 * (1.0 - 0.25 * fi);
		acc += vec3(a * sin(ph), a * k * cos(ph) * d.x, a * k * cos(ph) * d.y);
	}
	return acc;
}

#endif
