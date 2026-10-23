// FIRE_RESEARCH_V2 共用：熱度 → 線性 HDR 色（黑體近似），以及「預乘 alpha」輸出。
// 原則（舊 FXR 原型的教訓）：
//   1. 顏色只由熱度決定，且一律是「亮」的；外緣變冷時先變透明，不是先變暗 → 疊再多層也不會疊成棕色。
//   2. blend_premul_alpha：ALBEDO＝已乘覆蓋量的發光色，ALPHA＝只決定「擋掉多少背景」。ALPHA＝0 就是純加法。
//   3. unshaded 模式 Godot 只輸出 ALBEDO（EMISSION 被忽略），所以 HDR 亮度直接寫進 ALBEDO。

vec3 fire_ramp(float h) {
	h = clamp(h, 0.0, 1.0);
	vec3 c0 = vec3(0.55, 0.035, 0.004);   // 暗紅（只在將熄、幾乎透明時出現）
	vec3 c1 = vec3(1.00, 0.17, 0.012);    // 橘紅
	vec3 c2 = vec3(1.00, 0.36, 0.035);    // 橘
	vec3 c3 = vec3(1.00, 0.62, 0.16);     // 金黃
	vec3 c4 = vec3(1.00, 0.93, 0.74);     // 白金
	vec3 c;
	if (h < 0.25) c = mix(c0, c1, h / 0.25);
	else if (h < 0.5) c = mix(c1, c2, (h - 0.25) / 0.25);
	else if (h < 0.75) c = mix(c2, c3, (h - 0.5) / 0.25);
	else c = mix(c3, c4, (h - 0.75) / 0.25);
	// 亮度隨溫度上升（越熱越亮，白金核心 HDR 才會進泛光；橘色外焰維持在泛光門檻附近）
	return c * mix(0.55, 3.2, pow(h, 2.6));               // 白天＋Filmic 下中溫段不能太亮，否則橘色被壓成淡黃白
}

// 深度柔化：火焰面穿過角色／木樁／地面時不出現硬切線
float soft_depth(sampler2D dtex, vec2 screen_uv, float frag_z_view, mat4 inv_proj, float dist) {
	float d = texture(dtex, screen_uv).r;
	vec4 ndc = vec4(screen_uv * 2.0 - 1.0, d, 1.0);
	vec4 v = inv_proj * ndc;
	float scene_z = v.z / v.w;
	return clamp((frag_z_view - scene_z) / dist, 0.0, 1.0);
}
