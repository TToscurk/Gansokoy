// 河水 —— 雙層法線捲動（速度/方向不同才不會看出平舖）、
// 深淺兩色依視角混合、岸邊靠頂點色 R 做泡沫。
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, blend_mix;

uniform sampler2D wave_nor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_color : source_color = vec3(0.36, 0.52, 0.50);
uniform vec3 deep_color : source_color = vec3(0.10, 0.20, 0.26);
uniform float flow_speed = 0.05;
uniform float wave_scale = 0.25;
uniform float alpha = 0.86;
// 沒有頂點色的 mesh（CylinderMesh 池塘）COLOR 預設是白的 →
// bank=1 → 整片判定成岸邊泡沫 → 看起來像鐵板。這個係數設 0 就純深水。
uniform float bank_scale = 1.0;
// 岸邊的清透帶寬度（頂點色 R = 靠岸程度）。
// ⚠ 別再拿 hint_depth_texture 算水深：這個材質是 depth_draw 的，
// 深度貼圖裡讀到的是水面自己，算出來的水深恆為 0 → 整片變成白泡沫。
uniform vec3 sky_tint : source_color = vec3(0.62, 0.74, 0.86);

varying float bank;      // 頂點色 R：1=岸邊、0=中央

void vertex() {
	bank = COLOR.r * bank_scale;
	// 水面微微起伏（河不是鏡子）
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(TIME * 0.9 + wp.x * 0.6 + wp.z * 0.4) * 0.025
		+ sin(TIME * 1.7 + wp.z * 1.1) * 0.015;
}

void fragment() {
	vec2 uv = (NODE_POSITION_WORLD.xz + VERTEX.xz) * wave_scale;
	vec3 n1 = texture(wave_nor, uv + vec2(0.0, TIME * flow_speed)).rgb;
	vec3 n2 = texture(wave_nor, uv * 1.7 + vec2(TIME * flow_speed * 0.6, TIME * flow_speed * 1.3)).rgb;
	NORMAL_MAP = normalize(n1 + n2 * 0.7);
	NORMAL_MAP_DEPTH = 0.55;

	// 「水深」用頂點色代替：bank=1 是岸、0 是中央。
	float dfac = clamp(1.0 - bank, 0.0, 1.0);
	dfac = dfac * dfac;                             // 岸邊那一小段才清透

	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 2.5);
	// 淺處偏清透、深處偏濃，再依視角疊一層天光反射 ——
	// 少了這層反射，水就是一塊固定顏色的色板（「像鐵板」）
	vec3 col = mix(shallow_color, deep_color, dfac);
	col = mix(col, sky_tint, fres * 0.45);
	// 岸邊泡沫只留很窄一條
	float foam = smoothstep(0.90, 1.0, bank);
	ALBEDO = mix(col, vec3(0.88, 0.92, 0.90), foam * 0.55);
	ROUGHNESS = mix(0.05, 0.30, foam);
	METALLIC = 0.0;
	SPECULAR = 0.75;
	// 岸邊半透（看得到淺灘），中央接近不透明
	ALPHA = clamp(mix(0.42, alpha, dfac) + foam * 0.35, 0.0, 1.0);
}
