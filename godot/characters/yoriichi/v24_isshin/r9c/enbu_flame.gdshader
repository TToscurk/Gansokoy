shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
// R9-C 日之呼吸・圓舞：火焰層（火舌、尾焰、殘焰碎片、刀身火、命中火）。幾何與時間資料都來自 Blender（notes/r9c/build_enbu_vfx.py）：
//   UV  ＝火焰貼圖座標（r9c_tongue.png／r9c_ember.png：R＝熱度、G＝外緣、B＝撕裂紋、A＝輪廓）
//   UV2.x＝這一片火被刀「點燃」的技能時間（刀經過的時刻），UV2.y＝1 − 沿火舌位置（glTF 的 V 翻轉）
//   COLOR.r＝亂數種子，COLOR.b＝壽命倍率（0..1 → 0.6..1.4）
// 時鐘＝技能時間 skill_t（Hit Stop 停格時不前進 → 整個主斬畫面靜止，恢復後才繼續消散）。
uniform float skill_t = 0.0;
uniform float life = 0.25;              // 秒：點燃到熄滅
uniform float grow = 0.04;              // 秒：火舌從根部長到尖端
uniform float hold = 0.35;              // 0..1：壽命的前段保持完整，之後開始撕裂
uniform float use_reveal = 1.0;         // 1＝火舌由根往尖長出；0＝整片同時出現（殘焰碎片）
uniform float fixed_age = -1.0;         // ≥0：不看時間（刀身火：由 intensity 控制明暗）
uniform float flow = 0.0;               // 沿火舌捲動（刀身火的跳動）
uniform float intensity = 1.0;
uniform float flare = 0.0;              // 命中瞬間的亮度脈衝（場景給，0..1，真實時間 0.12 s 衰減）
uniform float emission = 2.0;
uniform float rim_k = 0.65;
uniform float cool = 0.55;
uniform float tear_heat = 0.45;
uniform float ignite_flash = 0.0;      // R9-C2：點燃瞬間的熱度脈衝（0＝關；A／B 不用）
uniform float flash_t = 0.06;
// R9-C2 命中點燃：刀在 ignite_from 之前掃過的部分先不燒（只留金色刀線），命中那一刻（ignite_t＝實際命中的技能時間，
// 沒命中就用 ignite_from）從命中點往回一口氣點燃；ignite_from ≤ 0 關閉（A／B）。
uniform float ignite_from = -1.0;
uniform float ignite_t = 0.6;
uniform float ignite_speed = 40.0;
uniform float ignite_lead = 0.03;         // R9-C2：撕裂順序裡熱度的權重（0＝完全依撕裂紋，日輪整段燒斷）              // 年齡越大越冷（黃 → 橘 → 紅）
uniform vec4 col_hot : source_color = vec4(1.0, 0.93, 0.62, 1.0);
uniform vec4 col_mid : source_color = vec4(1.0, 0.52, 0.10, 1.0);
uniform vec4 col_out : source_color = vec4(0.78, 0.13, 0.04, 1.0);
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;

varying float v_t0;
varying float v_along;
varying float v_seed;
varying float v_life;

void vertex() {
	v_t0 = UV2.x;
	if (v_t0 < ignite_from) {
		v_t0 = ignite_t - ignite_lead + (ignite_from - v_t0) / ignite_speed;
	}
	v_along = 1.0 - UV2.y;
	v_seed = COLOR.r;
	v_life = mix(0.6, 1.4, COLOR.b);
}

void fragment() {
	float age = fixed_age >= 0.0 ? fixed_age : skill_t - v_t0;
	if (age < 0.0) {
		discard;
	}
	float L = life * v_life;
	float k = clamp(age / L, 0.0, 1.0);
	float reveal = use_reveal > 0.5 ? smoothstep(v_along - 0.06, v_along + 0.02, age / max(grow, 0.001)) : 1.0;
	if (fixed_age >= 0.0) {
		// 刀身火：每條火舌長度各自跳動（依技能時間，停格時不動）
		float flick = 0.62 + 0.38 * sin(skill_t * 19.0 + v_seed * 40.0) * sin(skill_t * 7.3 + v_seed * 13.0);
		reveal = smoothstep(v_along - 0.08, v_along + 0.02, flick);
	}
	vec2 uv = UV;
	uv.x = uv.x - flow * skill_t * (0.6 + 0.4 * v_seed);
	vec4 tx = texture(tex, uv);
	// 撕裂：壽命後段依撕裂紋（B）與熱度由外往內斷開，不是整片一起變淡
	float tear = smoothstep(hold, 1.0, k);
	float keep = step(tear * 1.05, tx.b * (1.0 - tear_heat) + tx.r * tear_heat + 0.08 * fract(v_seed * 7.13));
	float a = tx.a * reveal * keep * (1.0 - smoothstep(0.9, 1.0, k)) * intensity;
	if (a < 0.02) {
		discard;
	}
	float heat = tx.r * (1.0 - cool * k) + ignite_flash * (1.0 - smoothstep(0.0, flash_t, age)) * tx.a;
	vec3 c = mix(col_out.rgb, col_mid.rgb, smoothstep(0.12, 0.45, heat));
	c = mix(c, col_hot.rgb, smoothstep(0.55, 0.92, heat));
	c = mix(c, col_out.rgb * 0.75, tx.g * rim_k * (0.4 + 0.6 * k));
	ALBEDO = c;
	EMISSION = c * emission * (0.15 + 0.85 * heat) * intensity * (1.0 + 1.2 * flare);
	ALPHA = clamp(a, 0.0, 1.0);
}
