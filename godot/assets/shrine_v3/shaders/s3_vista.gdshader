// 博麗神社 v3 中景／遠景地形：程序林冠（無貼圖；函式在 s3_canopy.gdshaderinc，近景外圍也用同一個）。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

#include "res://assets/shrine_v3/shaders/s3_canopy.gdshaderinc"

uniform vec4 inner_rect = vec4(0.0);  // 內層網格範圍（x0, z0, x1, z1）；保留給除錯
uniform float haze_k = 0.00010;

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float dist = length(v_wpos - CAMERA_POSITION_WORLD);
	vec3 col;
	vec3 nofs;
	float rough;
	s3_canopy(v_wpos.xz, v_wnrm, dist, v_wpos.y, col, nofs, rough);
	ALBEDO = s3_haze(col, dist, haze_k);
	ROUGHNESS = rough;
	vec3 n = normalize(v_wnrm + nofs);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
