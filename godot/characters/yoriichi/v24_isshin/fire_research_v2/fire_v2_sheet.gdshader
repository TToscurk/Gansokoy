// FIRE_RESEARCH_V2 斬擊火幕（刀路上的主要火體，世界座標 ribbon，由腳本每幀依實際刀的變換重建）。
// 頂點資料：UV.x＝刀尖走過的弧長（m，讓噪聲黏在空間裡，不跟著刀滑），UV.y＝0 刀身內側 → 1 刀尖外側；
//          UV2.x＝年齡比例（0 剛掃過、1 熄滅），UV2.y＝種子；COLOR.a＝出刀強度（依刀尖速度）。
// 外觀：剛掃過的前緣最熱最密；隨年齡，噪聲侵蝕門檻上升，火幕從外緣撕成一條條往後、往上竄的火舌，最後變冷、透明。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_common.gdshaderinc"

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float fx_time = 0.0;
uniform float brightness = 1.0;
uniform float occlusion = 0.72;      // 熱區像《隻狼》Normal 混合那樣蓋掉背景：亮天空前仍是飽和的橘金，不會被沖成淡粉

void fragment() {
	float a = clamp(UV2.x, 0.0, 1.0);
	float y = clamp(UV.y, 0.0, 1.0);
	float tr = UV.x;
	float s = UV2.y;
	// 噪聲：沿刀路的座標＋往外（刀尖方向）與往上流
	vec2 q = vec2(tr * 1.15 + s, y * 0.30 - fx_time * 0.85 - a * 0.30);   // 沿刀路高頻、往外拉長 → 外緣是一根根火舌，不是一整條帶子
	vec3 nA = texture(noise_tex, q).rgb;
	vec3 nB = texture(noise_tex, q * vec2(2.1, 2.0) + vec2(0.53, -fx_time * 0.4)).rgb;
	float n = nA.r * 0.5 + nB.b * 0.25 + (1.0 - nA.g) * 0.25;
	// 橫切面輪廓：火體集中在刀身外段，內側（靠手）淡；外緣交給噪聲撕
	float prof = smoothstep(0.05, 0.55, y) * (1.0 - 0.45 * smoothstep(0.82, 1.0, y));
	float thr = mix(0.22, 1.05, pow(a, 0.7));                 // 侵蝕快：一出生外緣就有缺口，一半壽命時已撕成分離的火舌
	float field = prof * 0.92 + (n - 0.5) * (1.15 + 0.7 * a) * (0.6 + 0.6 * y);
	float dens = smoothstep(thr, thr + 0.18, field);
	// 熱度：前緣與刀尖側熱，越老越冷
	float heat = dens * mix(0.74, 0.18, a) * (0.55 + 0.45 * y) * (0.78 + 0.36 * nB.r);
	float cov = dens * COLOR.a * (1.0 - smoothstep(0.85, 1.0, a));
	cov *= smoothstep(0.0, 0.12, a);                         // 火幕從刀後一點點開始：刀身本體與核心刀線在最前面
	cov *= soft_depth(depth_tex, SCREEN_UV, VERTEX.z, INV_PROJECTION_MATRIX, 0.10);
	ALBEDO = fire_ramp(heat) * cov * brightness;
	ALPHA = cov * occlusion * smoothstep(0.08, 0.40, heat);
}
