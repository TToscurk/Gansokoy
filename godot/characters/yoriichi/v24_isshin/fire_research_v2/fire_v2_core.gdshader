// FIRE_RESEARCH_V2 斬擊核心（刀路可讀性的主角）：只沿刀身外段、壽命很短的白金刀線。
// UV.y＝0 刀身內側（u0）→ 1 刀尖；UV2.x＝年齡比例（0 剛掃過）；COLOR.a＝出刀強度。
// 亮度集中在刀尖外緣並在 0.1 秒內由白金退到金黃：讀得出刀往哪裡揮，但不是霓虹光環（窄、短命、有噪聲閃爍）。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_common.gdshaderinc"

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float fx_time = 0.0;
uniform float brightness = 1.0;

void fragment() {
	float a = clamp(UV2.x, 0.0, 1.0);
	float y = clamp(UV.y, 0.0, 1.0);
	float n = texture(noise_tex, vec2(UV.x * 0.9, y * 0.25 - fx_time * 1.6)).b;
	float edge = pow(y, 2.2);                                 // 往刀尖越亮
	float line = smoothstep(0.80, 0.97, y) * (1.0 - smoothstep(0.985, 1.0, y));   // 刀尖外緣的細亮線
	float life = pow(1.0 - a, 1.6);
	float m = (edge * 0.75 + line * 0.9) * life * (0.8 + 0.4 * n);
	float heat = clamp(0.62 + 0.38 * life * (0.4 + 0.6 * y), 0.0, 1.0);
	ALBEDO = fire_ramp(heat) * m * COLOR.a * brightness * 0.5;
	ALPHA = 0.0;
}
