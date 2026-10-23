// 日之呼吸火焰系統（統一版）— Blender 火焰造型層。
// 幾何、時間資料沿用 R9-C2 的 Blender 資產（enbu_vfx_C2.glb：Flames／Sheet／Fin／Embers／BladeFlame，依實測刀路建模）：
//   UV   ＝Blender 貼圖座標（r9c_tongue／r9c2_body／r9c_ember：R＝熱度、G＝外緣、B＝撕裂紋、A＝輪廓；是「資料」不是顏色）
//   UV2.x＝這片火被刀點燃的技能時間；UV2.y＝1 − 沿火舌位置；COLOR.r＝亂數種子；COLOR.b＝壽命倍率
// 外觀沿用 FIRE_RESEARCH_V2：可平鋪噪聲往火舌尖端流動＋撕裂侵蝕、熱度 → 線性 HDR 黑體色、預乘 alpha（外緣先變透明，不會疊成棕色）。
// 修正 R9-C 舊材質的兩個問題：(1) unshaded 下 EMISSION 不輸出 → HDR 改寫在 ALBEDO；(2) 資料貼圖被當 sRGB 解碼（熱度 0.43 → 0.16，變暗）→ 這裡不加 source_color。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_common.gdshaderinc"

uniform sampler2D tex : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float skill_t = 0.0;          // 技能時間（Hit Stop 不前進）
uniform float fx_time = 0.0;          // 噪聲流動時鐘（Hit Stop 不前進）
uniform float cut_t = 99.0;           // 動作中斷的技能時間：之後才會被點燃的部分不再出現
uniform float life = 0.4;
uniform float grow = 0.04;
uniform float hold = 0.25;
uniform float use_reveal = 1.0;
uniform float fixed_age = -1.0;       // ≥0：刀身火（不看點燃時間，由 intensity 控制）
uniform float intensity = 1.0;
uniform float heat_gain = 1.0;
uniform float cool = 0.5;
uniform float occlusion = 0.75;       // 熱區蓋掉背景的比例（參考圖：火體實色、邊緣透明）
uniform float flow_speed = 1.0;
uniform float noise_amt = 0.55;
uniform float flare = 0.0;            // 命中瞬間的熱度脈衝
uniform float soft_dist = 0.08;       // 深度柔化距離（m）；刀身火貼著刀，設 0 關掉，否則會被刀身本體的深度吃掉

varying float v_t0;
varying float v_along;
varying float v_seed;
varying float v_life;

void vertex() {
	v_t0 = UV2.x;
	v_along = 1.0 - UV2.y;
	v_seed = COLOR.r;
	v_life = mix(0.6, 1.4, COLOR.b);
}

void fragment() {
	if (fixed_age < 0.0 && v_t0 > cut_t) {
		discard;
	}
	float age = fixed_age >= 0.0 ? fixed_age : skill_t - v_t0;
	if (age < 0.0) {
		discard;
	}
	float k = clamp(age / (life * v_life), 0.0, 1.0);
	float reveal = use_reveal > 0.5 ? smoothstep(v_along - 0.06, v_along + 0.02, age / max(grow, 0.001)) : 1.0;
	if (fixed_age >= 0.0) {
		float flick = 0.62 + 0.38 * sin(fx_time * 19.0 + v_seed * 40.0) * sin(fx_time * 7.3 + v_seed * 13.0);
		reveal = smoothstep(v_along - 0.08, v_along + 0.02, flick);
	}
	// 噪聲沿火舌往尖端流（UV.x），每片不同起點
	vec2 q = vec2(UV.x * 1.1 - fx_time * 0.9 * flow_speed + v_seed * 5.3, UV.y * 0.8 + v_seed * 2.7 - fx_time * 0.25);
	vec3 nA = texture(noise_tex, q).rgb;
	vec3 nB = texture(noise_tex, q * vec2(2.2, 1.9) + vec2(0.41, -fx_time * 0.5)).rgb;
	// 輪廓微扭（越往尖端越多），Blender 造型保持可辨識
	vec2 uv = UV + vec2((nA.r - 0.5) * 0.035, (nB.r - 0.5) * 0.05) * (0.3 + v_along);
	vec4 tx = texture(tex, uv);
	float n = nA.r * 0.5 + nB.b * 0.25 + (1.0 - nA.g) * 0.25;
	// 侵蝕：前段完整，壽命後段依 Blender 撕裂紋（B）＋噪聲由外往內撕開
	float erode = smoothstep(hold, 1.0, k);
	float field = tx.a * (0.80 + noise_amt * 0.5 * (n - 0.3)) - erode * (1.0 - 0.55 * tx.b) - (1.0 - n) * 0.14 * v_along * noise_amt;
	float dens = smoothstep(0.04, 0.26, field) * reveal * (1.0 - smoothstep(0.92, 1.0, k)) * intensity;
	if (dens < 0.004) {
		discard;
	}
	float heat = tx.r * heat_gain * (1.0 - cool * k) * (0.82 + 0.36 * nB.r) + flare * 0.25 * tx.r;
	heat *= 1.0 - 0.35 * tx.g * k;                 // Blender 外緣（rim）隨年齡先冷
	float cov = dens * (soft_dist > 0.0 ? soft_depth(depth_tex, SCREEN_UV, VERTEX.z, INV_PROJECTION_MATRIX, soft_dist) : 1.0);
	ALBEDO = fire_ramp(heat) * cov;
	ALPHA = cov * occlusion * smoothstep(0.08, 0.40, heat);
}
