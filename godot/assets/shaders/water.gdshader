// 河水 —— 雙層法線捲動（速度/方向不同才不會看出平舖）、
// 深淺兩色依視角混合、岸邊靠頂點色 R 做泡沫。
shader_type spatial;
render_mode cull_disabled, depth_draw_always;

uniform sampler2D wave_nor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_color : source_color = vec3(0.36, 0.52, 0.50);
uniform vec3 deep_color : source_color = vec3(0.10, 0.20, 0.26);
uniform float flow_speed = 0.05;
uniform float wave_scale = 0.25;
uniform float alpha = 0.86;
// 沒有頂點色的 mesh（CylinderMesh 池塘）COLOR 預設是白的 →
// bank=1 → 整片判定成岸邊泡沫 → 看起來像鐵板。這個係數設 0 就純深水。
uniform float bank_scale = 1.0;

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

	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 2.0);
	vec3 col = mix(deep_color, shallow_color, clamp(fres + bank * 0.6, 0.0, 1.0));
	// 岸邊泡沫：淺水處提亮
	float foam = smoothstep(0.82, 1.0, bank);
	ALBEDO = mix(col, vec3(0.86, 0.90, 0.88), foam * 0.7);
	ROUGHNESS = mix(0.06, 0.35, foam);
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ALPHA = mix(alpha, 0.97, foam);
}
