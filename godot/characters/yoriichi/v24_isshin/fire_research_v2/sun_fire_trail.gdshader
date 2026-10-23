// 日之呼吸火焰系統（統一版）— R9 程式刀光的「動態火焰帶」材質。
// 幾何＝原始 R9 sun_trail_r9.gd（實際刀變換插值取樣、Catmull 平滑、Hit Stop 時鐘），這裡只換外觀：
//   UV.x＝刀尖走過的弧長（m），UV.y＝0 刀身內側 → 1 刀尖外側；COLOR.a＝R9 的淡出值（fade_hold＝0 時 ≈ 1 − 年齡）。
// FIRE_RESEARCH_V2 的噪聲侵蝕：剛掃過的前緣完整、很快從外緣撕成往後竄的火舌；顏色只由熱度決定。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_common.gdshaderinc"

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float fx_time = 0.0;
uniform float intensity = 1.0;
uniform float heat_gain = 1.0;
uniform float occlusion = 0.55;

void fragment() {
	float a = clamp(1.0 - COLOR.a, 0.0, 1.0);
	float y = clamp(UV.y, 0.0, 1.0);
	float tr = UV.x;
	vec2 q = vec2(tr * 1.15, y * 0.30 - fx_time * 0.85 - a * 0.30);
	vec3 nA = texture(noise_tex, q).rgb;
	vec3 nB = texture(noise_tex, q * vec2(2.1, 2.0) + vec2(0.53, -fx_time * 0.4)).rgb;
	float n = nA.r * 0.5 + nB.b * 0.25 + (1.0 - nA.g) * 0.25;
	float prof = smoothstep(0.05, 0.55, y) * (1.0 - 0.45 * smoothstep(0.82, 1.0, y));
	float thr = mix(0.22, 1.05, pow(a, 0.7));
	float field = prof * 0.92 + (n - 0.5) * (1.15 + 0.7 * a) * (0.6 + 0.6 * y);
	float dens = smoothstep(thr, thr + 0.18, field);
	float heat = dens * mix(0.80, 0.20, a) * (0.55 + 0.45 * y) * (0.78 + 0.36 * nB.r) * heat_gain;
	float cov = dens * intensity * (1.0 - smoothstep(0.85, 1.0, a));
	cov *= soft_depth(depth_tex, SCREEN_UV, VERTEX.z, INV_PROJECTION_MATRIX, 0.08);
	ALBEDO = fire_ramp(heat) * cov;
	ALPHA = cov * occlusion * smoothstep(0.08, 0.40, heat);
}
