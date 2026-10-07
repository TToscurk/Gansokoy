// P8 Farmland pilot r4：秧苗／田埂雜草（頂點色＝sRGB；UV.y＝葉片高度比例 0 基部 → 1 葉尖）。
// MultiMesh 秧苗叢：頂點色＝灰階＋葉尖偏黃漸層，每株葉色由 instance color 給（引擎相乘進 COLOR）。
// 法線自己給（世界空間、偏上；MODEL_MATRIX 已含 instance 變換），雙面渲染時背面不會被翻黑；
// 基部壓暗＝水中陰影；葉尖輕微隨風擺動（世界公尺，換回 local 以免被叢的縮放放大）。
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float sway = 0.035;

varying vec3 wn;

vec3 s2l(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

vec3 l2s(vec3 c) {
	return mix(vec3(1.055) * pow(c, vec3(1.0 / 2.4)) - vec3(0.055), c * 12.92, lessThan(c, vec3(0.0031308)));
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = UV.y * UV.y;
	vec3 o = vec3(sin(TIME * 1.3 + w.x * 0.37 + w.z * 0.21), 0.0, cos(TIME * 1.1 + w.z * 0.33) * 0.6) * sway * k;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(o, 0.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = s2l(clamp(COLOR.rgb, vec3(0.0), vec3(1.0))) * mix(0.45, 1.0, smoothstep(0.0, 0.35, UV.y));
	ALBEDO = OUTPUT_IS_SRGB ? l2s(c) : c;
	ROUGHNESS = 0.72;
	SPECULAR = 0.35;
	BACKLIGHT = c * 0.25;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
