// FIRE_RESEARCH_V2 刀身火（纏刀）：沿刀身、朝相機展開的火焰帶，由腳本每幀依刀的變換重建（永遠貼刀）。
// UV.x＝沿刀身的實際長度（m），UV.y＝0 刀身邊緣 → 1 火焰外緣；COLOR.a＝點燃程度（技能時間的包絡）。
// 噪聲往外流：火從刀刃竄出、尖端撕開；根部（貼刀處）最熱。刀身本體在中間 6 mm 內不畫，金屬保持看得見。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_common.gdshaderinc"

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float fx_time = 0.0;
uniform float brightness = 1.0;
uniform float side_seed = 0.0;

void fragment() {
	float x = UV.x;
	float y = clamp(UV.y, 0.0, 1.0);
	vec2 q = vec2(x * 1.25 + side_seed, y * 0.30 - fx_time * 1.9);
	vec3 nA = texture(noise_tex, q).rgb;
	vec3 nB = texture(noise_tex, q * vec2(2.1, 1.8) + vec2(0.17, -fx_time * 0.7)).rgb;
	float n = nA.r * 0.5 + nB.b * 0.25 + (1.0 - nA.g) * 0.25;
	float field = (1.0 - y) * 1.05 + (n - 0.5) * 0.95;
	float dens = smoothstep(0.34, 0.56, field);
	float heat = dens * (1.0 - y * 0.6) * (0.75 + 0.35 * nB.r);
	float cov = dens * COLOR.a;
	ALBEDO = fire_ramp(heat * (0.6 + 0.3 * COLOR.a)) * cov * brightness * 1.3;
	ALPHA = cov * 0.70 * smoothstep(0.1, 0.45, heat);
}
