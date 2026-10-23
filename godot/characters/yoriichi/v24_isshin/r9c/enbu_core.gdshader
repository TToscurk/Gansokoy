shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
// v4：改成 blend_mix（疊加模式在亮背景與泛光下整條變白，看不出金黃；審圖第 3 輪）
// R9-C 日之呼吸・圓舞：刀刃斬擊核心（金黃刀光）。Blender 沿真實刀路建的帶狀網格（起始細、中段爆發、末端收窄）；
//   UV ＝ r9c_core.png（x 沿斬擊、y 橫跨刀身：R 熱度、B 長條紋），UV2.x＝刀經過的技能時間，UV2.y＝橫跨位置
// 最新的 head_fade 秒由透明淡入：刀身本體在刀光前緣看得見；壽命後段沿長條紋撕裂成絲。
uniform float skill_t = 0.0;
uniform float life = 0.14;
uniform float head_fade = 0.018;
uniform float hold = 0.25;
uniform float intensity = 1.0;
uniform float flare = 0.0;
uniform float emission = 3.0;
uniform vec4 col_hot : source_color = vec4(1.0, 0.97, 0.82, 1.0);
uniform vec4 col_gold : source_color = vec4(1.0, 0.72, 0.18, 1.0);
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;

varying float v_t0;

void vertex() {
	v_t0 = UV2.x;
}

void fragment() {
	float age = skill_t - v_t0;
	if (age < 0.0) {
		discard;
	}
	float k = clamp(age / life, 0.0, 1.0);
	vec4 tx = texture(tex, UV);
	float tear = smoothstep(hold, 1.0, k);
	float keep = smoothstep(tear - 0.08, tear + 0.02, tx.b * 0.8 + tx.r * 0.25);
	float a = tx.a * keep * smoothstep(0.0, head_fade, age) * (1.0 - smoothstep(0.85, 1.0, k)) * intensity;
	if (a < 0.01) {
		discard;
	}
	vec3 c = mix(col_gold.rgb, col_hot.rgb, smoothstep(0.45, 0.95, tx.r * (1.0 - 0.5 * k)));
	ALBEDO = c;
	EMISSION = c * emission * a * (1.0 + 1.5 * flare);
	ALPHA = clamp(a, 0.0, 1.0);
}
