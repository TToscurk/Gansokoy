shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;

// 街道鋪面：石板 + 石縫苔痕 + 局部草覆蓋。
// 苔的位置不是隨機撒的——由法線貼圖的藍通道推導「凹陷度」，
// 石頭頂面藍值高（朝上）、石縫藍值低（側向），所以 1-blue 就是石縫遮罩。
// 另加一層低頻雜訊做「整塊被草吃掉」的區域。

uniform sampler2D stone_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float moss_uv_scale = 3.2;
uniform vec3 moss_tint : source_color = vec3(0.34, 0.42, 0.20);
uniform vec3 stone_tint : source_color = vec3(0.60, 0.62, 0.64);

uniform float joint_low = 0.10;      // 石縫遮罩起點
uniform float joint_high = 0.55;     // 石縫遮罩終點
uniform float joint_moss = 0.85;     // 石縫苔量
uniform float patch_moss = 0.80;     // 草塊覆蓋量
uniform float patch_scale = 0.055;   // 草塊尺度（越小塊越大）
uniform float patch_low = 0.52;
uniform float patch_high = 0.78;
uniform float normal_strength = 0.8;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	vec3 stone = texture(stone_albedo, uv).rgb * stone_tint;
	vec3 nrm = texture(stone_normal, uv).rgb;
	float rough = texture(stone_rough, uv).r;

	// 石縫：法線貼圖被 RGTC 壓縮後藍通道不可用，改用 albedo 亮度——
	// 石縫在 diffuse 上本來就是暗的，這個訊號最可靠。
	float lum = dot(texture(stone_albedo, uv).rgb, vec3(0.299, 0.587, 0.114));
	float joint = 1.0 - smoothstep(joint_low, joint_high, lum);

	// 草塊：低頻 fbm，讓某幾塊石頭整片被吃掉
	float p = fbm(uv * (1.0 / max(patch_scale, 0.001)) * 0.02);
	float patch = smoothstep(patch_low, patch_high, p);

	float moss_mask = clamp(joint * joint_moss + patch * patch_moss, 0.0, 1.0);

	vec3 moss = texture(moss_albedo, uv * moss_uv_scale).rgb * moss_tint * 1.9;

	vec3 col = mix(stone, moss, moss_mask);

	// 頂點色：RGB 帶冷暖石調變化，A 是邊緣化入夯土的遮罩
	ALBEDO = col * COLOR.rgb * 1.05;
	ALPHA = COLOR.a;
	ROUGHNESS = mix(rough, 0.98, moss_mask);
	SPECULAR = mix(0.35, 0.10, moss_mask);
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = normal_strength * (1.0 - 0.55 * moss_mask);
}
