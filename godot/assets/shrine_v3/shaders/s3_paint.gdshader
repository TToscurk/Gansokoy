// 博麗神社 v3：褪色朱漆／黑漆（鳥居）。木紋取自木材貼圖亮度；剝落處露出木頭；下緣與雨痕偏暗。
// UV＝公尺（s3b 建構器）。頂點色＝構件色差×近地汙損。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 paint_col : source_color = vec3(0.60, 0.16, 0.09);
uniform sampler2D wood_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wood_tile = 1.6;
uniform float wear = 0.22;        // 剝落面積（0..1）
uniform float fade = 0.30;        // 日曬褪色
uniform float streak = 0.35;      // 雨痕
uniform float paint_rough = 0.62;

varying vec3 v_lpos;

void vertex() {
	v_lpos = VERTEX;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	return 0.5 * vn(p) + 0.27 * vn(p * 2.1 + 3.1) + 0.15 * vn(p * 4.3 + 7.7) + 0.08 * vn(p * 8.7 + 1.3);
}

void fragment() {
	vec2 uv = UV / wood_tile;
	vec3 wd = texture(wood_d, uv).rgb;
	float lum = dot(wd, vec3(0.333));
	vec3 pc = paint_col * (0.82 + 0.36 * lum);
	// 褪色：偏淡、略橘
	pc = mix(pc, pc * vec3(1.18, 1.08, 1.0) + vec3(0.06, 0.04, 0.03), fade);
	// 剝落（以物件座標的雜訊；邊緣略暗＝漆膜斷面）
	float n = fbm(vec2(v_lpos.x * 3.1 + v_lpos.z * 2.3, v_lpos.y * 5.0));
	float chip = smoothstep(1.0 - wear, 1.0 - wear + 0.04, n);
	float rim = smoothstep(1.0 - wear - 0.05, 1.0 - wear, n) * (1.0 - chip);
	vec3 col = mix(pc * (1.0 - 0.35 * rim), wd * 0.55, chip);
	// 雨痕：沿 y 的細長暗條紋
	float st = smoothstep(0.55, 0.9, vn(vec2(v_lpos.x * 9.0 + v_lpos.z * 7.0, v_lpos.y * 0.6))) * streak;
	col *= 1.0 - 0.35 * st;
	col *= COLOR.rgb;
	ALBEDO = col;
	ROUGHNESS = mix(paint_rough, 0.88, chip);
	vec3 tn = texture(wood_n, uv).xyz * 2.0 - 1.0;
	NORMAL_MAP = vec3(tn.xy * mix(0.25, 1.0, chip) * 0.5 + 0.5, 1.0);
}
