// 人間之里 V2 P9 R4 稗田邸庭園：滝の落水簾＋滝壺の白泡（R4 r2）。
// 簾：UV.x 幅 0..1、UV.y 落下 0..1；縦筋ノイズを下へスクロール、左右の縁と落ち口・落ち際をフェード（カードの矩形を見せない）。
// 泡：UV＝放射座標（−1..1）；中心ほど白く、縁へ放射フェード＋ノイズで破る。COLOR.r＝1 簾、0 泡。
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 water_col : source_color = vec3(0.74, 0.8, 0.8);
uniform float speed = 0.9;

void fragment() {
	float a;
	if (COLOR.r > 0.5) {
		float sx = UV.x;
		float st = texture(noise_tex, vec2(sx * 1.7, UV.y * 0.35 - TIME * speed * 0.35)).g;
		float st2 = texture(noise_tex, vec2(sx * 4.1 + 0.3, UV.y * 0.6 - TIME * speed * 0.55)).b;
		float streak = smoothstep(0.32, 0.72, st * 0.6 + st2 * 0.55);
		float wob = (texture(noise_tex, vec2(UV.y * 0.8 - TIME * 0.2, 0.5)).g - 0.5) * 0.25;
		float edge = smoothstep(0.0, 0.3, sx + wob) * smoothstep(1.0, 0.7, sx + wob);
		float top = smoothstep(0.0, 0.08, UV.y);
		a = edge * top * mix(0.12, 0.62, streak) * mix(1.0, 0.7, UV.y);
		ALBEDO = water_col * mix(0.82, 1.05, streak);
	} else {
		float r = length(UV);
		float nz = texture(noise_tex, UV * 0.6 + vec2(TIME * 0.05, -TIME * 0.04)).g;
		a = (1.0 - smoothstep(0.15, 1.0, r + (nz - 0.5) * 0.35)) * 0.8;
		ALBEDO = water_col;
	}
	ALPHA = a;
	ROUGHNESS = 0.35;
	SPECULAR = 0.4;
}
