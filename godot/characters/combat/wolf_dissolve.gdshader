shader_type spatial;
// 妖怪化光溶解 —— 山犬（雙尾狼）的死亡表現。
//
// 由下往上掃：腳先化、頭最後。門檻由 dissolve_fx.json 的 `dissolve` 欄位逐幀驅動，
// 掃描範圍由該幀的 zmin/zmax 給（在 Godot 是世界 y）。
//
// 為什麼掃描邊界要由外部餵、不在 shader 裡用模型 AABB 算：
// Dissolve 動畫會讓身體上浮 40 cm，模型空間的 AABB 是靜止姿態的，
// 用它會讓溶解線跟不上身體，頭已經飄上去了溶解線還停在原地。
//
// 純程序化噪聲，無外部貼圖。
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform bool use_normal_map = true;
uniform bool use_orm = true;

// 0 = 完好，1 = 完全消失
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
// 這一幀身體的上下界（世界座標 y）
uniform float sweep_min = 0.0;
uniform float sweep_max = 1.2;
// 溶解邊緣的發光帶寬度（世界公尺）
uniform float edge_width : hint_range(0.005, 0.4) = 0.09;
uniform vec4 edge_color : source_color = vec4(0.62, 0.86, 1.0, 1.0);
uniform float edge_energy : hint_range(0.0, 12.0) = 5.0;
// 噪聲讓溶解線不是一條水平直線
uniform float noise_scale : hint_range(1.0, 40.0) = 11.0;
uniform float noise_amount : hint_range(0.0, 0.5) = 0.16;

varying vec3 world_pos;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 這個片元在身體上的相對高度（0 = 腳底，1 = 頭頂）
	float span = max(sweep_max - sweep_min, 0.001);
	float h = clamp((world_pos.y - sweep_min) / span, 0.0, 1.0);
	// 噪聲擾動，讓溶解線碎裂成不規則邊緣。
	// ⚠ 不要把噪聲加進 h 之後又 clamp h —— 那會讓身體頂端的片元
	//   被推過 1.0 再夾回來，整批同時消失（實測 dissolve=0.73 時全身已不見）。
	//   噪聲要加在「線」上，且 h 保持乾淨的 0–1。
	float n = (vnoise(world_pos * noise_scale) - 0.5) * noise_amount;

	// 溶解線位置：dissolve=0 → 線在 0 以下（全在）；=1 → 線在 1 以上（全消失）。
	float line = dissolve * (1.0 + noise_amount) - noise_amount * 0.5 + n;
	float edge_h = edge_width / span;

	// dissolve=0 時一律不裁（活著的狼不能因為噪聲缺角）
	if (dissolve > 0.001 && h < line) {
		discard;
	}

	vec4 alb = texture(albedo_tex, UV);
	ALBEDO = alb.rgb;
	if (use_orm) {
		vec3 orm = texture(orm_tex, UV).rgb;
		ROUGHNESS = orm.g;
		METALLIC = orm.b;
		AO = orm.r;
		AO_LIGHT_AFFECT = 1.0;
	} else {
		ROUGHNESS = 0.85;
		METALLIC = 0.0;
	}
	if (use_normal_map) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}

	// 溶解邊緣的發光帶：越靠近溶解線越亮
	float d = h - line;
	float glow = 1.0 - smoothstep(0.0, edge_h, d);
	// dissolve 為 0 時完全不發光（活著的狼不該有藍邊）
	glow *= step(0.001, dissolve);
	EMISSION = edge_color.rgb * glow * edge_energy;
}
