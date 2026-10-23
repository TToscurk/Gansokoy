// 日之呼吸火焰系統（統一版）— R9 程式刀光的「高溫刀光核心」材質。
// 幾何＝原始 R9 sun_trail_r9.gd 的核心 strip（刀身外段 → 刀尖，壽命＝刀光壽命 × core_ratio，含 head_fade：刀身本體不被洗掉）。
//   UV.x＝弧長（m），UV.y＝0 核心內側 → 1 刀尖；COLOR.a＝R9 的 (1−t)²×head_fade。
// 改掉霓虹感：亮度集中在刀尖側一條「斷續、粗細會變」的象牙白線＋幾條金黃伴線（噪聲沿弧長切開），不是均勻發光的圓弧帶。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_common.gdshaderinc"

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float fx_time = 0.0;
uniform float intensity = 1.0;
uniform float gain = 0.5;

void fragment() {
	float life = sqrt(clamp(COLOR.a, 0.0, 1.0));             // 1 剛掃過 → 0 熄滅
	float y = clamp(UV.y, 0.0, 1.0);
	float tr = UV.x;
	vec3 n = texture(noise_tex, vec2(tr * 0.75, y * 0.22 - fx_time * 1.4)).rgb;
	float nb = texture(noise_tex, vec2(tr * 2.4 + 0.3, y * 0.6 - fx_time * 2.0)).b;
	// 主線：刀尖外緣，寬度沿弧長變化（0.6–1.0），偶爾斷開
	float w = mix(0.06, 0.16, n.r);
	float line = smoothstep(1.0 - w - 0.05, 1.0 - w * 0.4, y) * (1.0 - smoothstep(0.985, 1.0, y));
	line *= smoothstep(0.18, 0.40, n.r + 0.25);
	// 伴線：往內側散開的金黃細流，被噪聲切成段
	float comp = pow(y, 2.4) * smoothstep(0.45, 0.70, nb) * 0.65;
	float m = (line + comp) * life;
	float heat = clamp(0.66 + 0.34 * life * (0.35 + 0.65 * line), 0.0, 1.0);
	ALBEDO = fire_ramp(heat) * m * gain * intensity;
	ALPHA = m * 0.35 * intensity;
}
