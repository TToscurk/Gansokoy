// FIRE_RESEARCH_V2 火星（加法混合、沿速度拉長）。只負責細節，數量少、很小。
// INSTANCE_CUSTOM：x＝年齡，y＝壽命，z＝種子。粒子 Y 軸＝速度方向×長度（process 每幀寫入），X 軸長度＝寬度。
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_common.gdshaderinc"

uniform float brightness = 1.0;
varying float v_age;
varying float v_seed;
varying float v_int;

void vertex() {
	v_age = clamp(INSTANCE_CUSTOM.x / max(INSTANCE_CUSTOM.y, 0.01), 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.z;
	v_int = COLOR.a;
	vec3 ax = (VIEW_MATRIX * vec4(MODEL_MATRIX[1].xyz, 0.0)).xyz;
	vec2 up = length(ax.xy) > 1e-5 ? normalize(ax.xy) : vec2(0.0, 1.0);
	vec2 side = vec2(up.y, -up.x);
	float w = length(MODEL_MATRIX[0].xyz);
	float h = max(length(ax.xy), w);            // 正對相機飛的火星不會縮成一條線，最小＝圓點
	VERTEX = vec3(side * VERTEX.x * w + up * VERTEX.y * h, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 c = (UV - 0.5) * 2.0;
	float m = clamp(1.0 - dot(c, c), 0.0, 1.0);
	m *= m;
	float flick = 0.75 + 0.25 * sin(v_seed * 91.0 + v_age * 40.0);
	float heat = mix(1.0, 0.35, v_age) * flick;
	float fade = 1.0 - smoothstep(0.7, 1.0, v_age);
	ALBEDO = fire_ramp(heat) * m * fade * brightness * v_int;
}
