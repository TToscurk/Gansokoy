shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

// 日之呼吸刀光 —— 內層白熱核心。
// 原創程序美術：不含任何第三方貼圖或動畫影格擷取。
//
// 這層跟外焰層分工相反：
//   外焰層 blend_mix 保深赤實色輪廓（形狀辨識）。
//   這層 blend_add 推過 HDR 門檻進 bloom（速度感與熱度）。
// 兩層都做同一件事就沒有層次；分開才有「刀刃在燒」的立體感。
//
// 本層壽命由腳本設成外焰的一半左右 —— 核心收得比火舌快，
// 揮刀才會讀成「快」而不是「拖著一條光」。

uniform vec4 core_color : source_color = vec4(1.000, 0.984, 0.910, 1.0);  // #FFFBE8
uniform vec4 gold_color : source_color = vec4(1.000, 0.847, 0.290, 1.0);  // #FFD84A
// 核心亮度。專案 glow_hdr_threshold 最低 1.05、最高 1.25，
// 要進 bloom 必須讓 EMISSION 明顯推過 1.25，所以預設給到 3.4。
uniform float emission_strength : hint_range(0.0, 8.0) = 3.4;
// 核心厚度（佔 ribbon 寬度比例）。太厚會蓋掉外焰的色階。
uniform float core_width : hint_range(0.02, 0.6) = 0.20;
// 沿刀軌的亮度脈動速度，讓核心不是一條死光。
uniform float flow_speed : hint_range(0.0, 8.0) = 3.0;
uniform float tile : hint_range(0.5, 12.0) = 2.6;
// 核心邊緣柔度。核心是熱源，比外焰邊緣軟一點才自然。
uniform float softness : hint_range(0.01, 0.4, 0.005) = 0.085;
uniform float layer_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float y = clamp(UV.y, 0.0, 1.0);
	float x = UV.x * tile - TIME * flow_speed;

	// 核心貼著刀身（y 小的一側），往外快速衰減。
	float core = 1.0 - smoothstep(0.0, core_width, y);
	// 起始處硬切，避免核心糊到刀身背面。
	core *= smoothstep(0.0, 0.012, y);

	// 沿刀軌的熱度脈動：局部更白更亮，讀起來像刃上的高溫點。
	float pulse = 0.72 + 0.28 * pow(max(0.0, sin(x * 1.6)), 2.0);
	core *= pulse;

	// 邊緣柔化（這層是熱源不是剪影，不需要尖銳輪廓）。
	core = smoothstep(0.0, softness + 0.001, core) * core;

	// 最內側近白、外側轉金。
	float t = clamp(y / max(core_width, 0.001), 0.0, 1.0);
	vec3 ink = mix(core_color.rgb, gold_color.rgb, smoothstep(0.25, 1.0, t));

	ALBEDO = ink;
	EMISSION = ink * emission_strength * core;
	// ADD 模式下 alpha 當作強度用。
	ALPHA = clamp(core, 0.0, 1.0) * COLOR.a * layer_alpha;
}
