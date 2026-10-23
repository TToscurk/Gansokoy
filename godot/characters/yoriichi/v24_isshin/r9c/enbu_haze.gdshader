shader_type spatial;
// R9-C3 命中熱浪（L2 實驗）：只扭曲「比這片熱浪遠 margin 公尺以上」的背景；人物、刀與木樁（比熱浪近或貼著）不扭曲，保持清晰。
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix, shadows_disabled, fog_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float strength = 0.0;        // 0..1（場景每幀給，真實時間衰減）
uniform float amount = 0.006;        // 最大 UV 位移
uniform float margin = 0.35;         // 公尺：背景要比熱浪遠這麼多才扭曲
uniform float flow_t = 0.0;

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float mask = smoothstep(1.0, 0.25, length(q)) * strength;
	// 往上流動的熱浪：兩層正弦（不需要額外貼圖）
	vec2 w = vec2(sin(UV.y * 23.0 - flow_t * 9.0 + UV.x * 5.0), cos(UV.x * 19.0 + flow_t * 7.0 - UV.y * 11.0));
	vec2 off = w * amount * mask;
	vec2 suv = SCREEN_UV + off;
	float here = -VERTEX.z;
	float bg = lin_depth(suv, INV_PROJECTION_MATRIX);
	float bg0 = lin_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float k = smoothstep(here + margin, here + margin + 0.4, min(bg, bg0));
	vec3 c = textureLod(screen_tex, mix(SCREEN_UV, suv, k), 0.0).rgb;
	ALBEDO = c;
	ALPHA = clamp(mask * 4.0, 0.0, 1.0) * k;
}
