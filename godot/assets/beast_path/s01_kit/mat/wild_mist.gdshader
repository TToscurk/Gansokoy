// 獸道 荒野化 R2：局部薄霧（窪地、溪谷、倒木後方）。兩片交叉的軟邊薄片——取代全區的灰白霧。
// 深度柔化（與地面、樹幹交界不出硬邊）、近相機淡出（走進去不會糊滿鏡頭）、側視淡出（看不到薄片的邊）、緩慢飄動。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec3 mist_col : source_color = vec3(0.52, 0.57, 0.55);
uniform float density = 0.32;
uniform float soft_dist = 3.0;
uniform vec2 near_fade = vec2(2.5, 7.0);
uniform float drift = 0.012;

void fragment() {
	vec2 q = UV - vec2(0.5, 0.62);
	vec3 wp0 = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float edge_n = texture(noise_tex, wp0.xz * 0.11 + vec2(wp0.y * 0.07, 0.3)).b - 0.5;
	float body = 1.0 - smoothstep(0.0, 0.95, length(q * vec2(2.0, 2.6)) + edge_n * 0.55);   // 輪廓用噪聲打散（不是卡片邊）
	float top = 1.0 - smoothstep(0.05, 0.7, 1.0 - UV.y);          // 上緣更薄：霧貼著地面
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n1 = texture(noise_tex, wp.xz * 0.045 + vec2(TIME * drift, TIME * drift * 0.6)).r;
	float n2 = texture(noise_tex, vec2(wp.x + wp.z, wp.y) * 0.09 - vec2(TIME * drift * 1.7, 0.0)).g;
	float wisps = smoothstep(0.22, 0.78, n1 * 0.65 + n2 * 0.55);
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec3 scene_pos = upos.xyz / upos.w;
	float soft = clamp((VERTEX.z - scene_pos.z) / soft_dist, 0.0, 1.0);
	float dist = length(VERTEX);
	float nearf = smoothstep(near_fade.x, near_fade.y, dist);
	float side = smoothstep(0.08, 0.45, abs(dot(normalize(NORMAL), normalize(VIEW))));
	ALBEDO = mist_col;
	ALPHA = clamp(density * body * top * wisps * soft * nearf * side, 0.0, 1.0);
}
