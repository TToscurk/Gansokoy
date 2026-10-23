// FIRE_RESEARCH_V2 命中高溫核心：沿刀的行進方向拉長的「熱裂口」（不是白色光球）。
// 面片 Y 軸＝斬擊方向（長度＝長），X 軸長度＝寬；朝相機展開。age 0→1：0.0–0.25 白金爆亮、之後縮短退成金橘並撕開。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
#include "res://characters/yoriichi/v24_isshin/fire_research_v2/fire_v2_common.gdshaderinc"

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float age = 1.0;
uniform float seed = 0.0;
uniform float brightness = 1.0;

void vertex() {
	vec3 ax = (VIEW_MATRIX * vec4(MODEL_MATRIX[1].xyz, 0.0)).xyz;
	vec2 up = length(ax.xy) > 1e-5 ? normalize(ax.xy) : vec2(0.0, 1.0);
	vec2 side = vec2(up.y, -up.x);
	float w = length(MODEL_MATRIX[0].xyz);
	float h = length(MODEL_MATRIX[1].xyz) * mix(0.7, 1.15, smoothstep(0.0, 0.3, age));
	VERTEX = vec3(side * VERTEX.x * w + up * VERTEX.y * h, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 c = (UV - 0.5) * 2.0;
	float n = texture(noise_tex, vec2(UV.x * 0.6 + seed, UV.y * 0.35 + age * 0.4)).r;
	float nb = texture(noise_tex, vec2(UV.x * 1.4 - seed, UV.y * 0.9 - age * 0.8)).g;
	float r = length(vec2(c.x * mix(1.0, 1.6, age), c.y));
	float shape = 1.0 - r + (n - 0.5) * 0.55 * (0.4 + age) - (1.0 - nb) * 0.25 * age;
	float dens = smoothstep(0.0, 0.35, shape);
	float life = 1.0 - smoothstep(0.25, 1.0, age);
	float heat = clamp(dens * (1.0 - r * 0.6) * mix(1.15, 0.45, age), 0.0, 1.0);
	float cov = dens * life;
	ALBEDO = fire_ramp(heat) * cov * brightness * 0.6;
	ALPHA = cov * 0.25 * smoothstep(0.3, 0.7, heat);
}
