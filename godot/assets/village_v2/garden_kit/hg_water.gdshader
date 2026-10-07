// 人間之里 V2 P9 R4 稗田邸庭園：池／曲水の水面（R4 r2 targeted polish）。
// 水面は岸坡（hg_ground overlay）と交差させる → 水際＝地面の等高線。ここでは深度差で淺瀬を透かし、水際をグラデーションにする
// （硬い多角形の縁を見せない）。淺瀬＝濕った土色を透過、深み＝暗い緑。微細な漣（noise 2 層スクロール）。
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 deep_col : source_color = vec3(0.045, 0.07, 0.06);
uniform vec3 shallow_col : source_color = vec3(0.16, 0.15, 0.11);
uniform float shallow_depth = 0.05;
uniform float edge_alpha = 0.08;
uniform float deep_alpha = 0.93;
uniform float ripple = 0.012;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float zb = texture(depth_tex, SCREEN_UV).r;
	vec4 vb = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, zb, 1.0);
	vb.xyz /= vb.w;
	// 視線方向の水中距離 → 鉛直深さの近似（斜め視線で過大評価しないよう 0.5 倍）
	float d = max(length(vb.xyz) - length(VERTEX), 0.0) * 0.5 * mix(6.0, 1.0, COLOR.g);
	float t = smoothstep(0.0, shallow_depth, d);
	vec2 uv = wpos.xz;
	float n1 = texture(noise_tex, uv * 1.3 + vec2(TIME * 0.02, TIME * 0.013)).g;
	float n2 = texture(noise_tex, uv * 1.3 + vec2(0.017 + TIME * 0.02, TIME * 0.013)).g;
	float n3 = texture(noise_tex, uv * 1.3 + vec2(TIME * 0.02, 0.017 + TIME * 0.013)).g;
	vec2 nn = vec2(n2 - n1, n3 - n1) * ripple * 8.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(nn.x, 1.0, nn.y, 0.0)).xyz);
	ALBEDO = mix(shallow_col, deep_col, t);
	ALPHA = mix(mix(0.4, edge_alpha, COLOR.g), deep_alpha, smoothstep(0.0, 1.0, t));
	ROUGHNESS = mix(0.24, 0.12, t);
	SPECULAR = 0.42;
}
