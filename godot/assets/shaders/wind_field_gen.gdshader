// Wind V2 效能版：共用風場貼圖生成器（WIND_V2_PERF_REVIEW）。
// Wind autoload 的 SubViewport（RGBA16F、6N×N）每幀跑一次；每個 texel＝世界上一個格點，
// 用 wind_field.gdshaderinc 的同一份 wf_field／wf_drive／wf_force 算「逐根部」的場量。
// 方塊配置與取樣見 wind_field.gdshaderinc 的 gw_field 說明。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

#define WF_FIELD_GENERATOR
#include "res://assets/shaders/wind_field.gdshaderinc"

// 草浪 noise（與 V1.2 meadow_grass 的 hash2／vnoise 同式 → 波頭扭曲與強弱分佈不變）
float gen_hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float gen_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(gen_hash2(i), gen_hash2(i + vec2(1.0, 0.0)), u.x),
		mix(gen_hash2(i + vec2(0.0, 1.0)), gen_hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec2 gen_tree(int sp, vec2 p, vec2 wd, float m) {
	vec4 r0;
	vec4 r1;
	vec4 r2;
	wf_species(sp, r0, r1, r2);
	float trunk;
	float crown;
	wf_drive(p, wd, m, 1.0, gw_time, sp, r0.w, r2, trunk, crown);
	return vec2(trunk, crown);
}

void fragment() {
	float tu = SCREEN_UV.x * WF_FIELD_TILES;
	float tile = floor(tu);
	vec2 p = gw_field_rect.xy + vec2(fract(tu), SCREEN_UV.y) / gw_field_rect.z;
	vec2 dm = wf_field_dm(p);
	vec2 wd = wf_dir_rot(dm.x);
	float m = dm.y;
	vec4 o;
	if (tile < 7.5) {
		// 物種方塊：(aoff, m, trunk, crown)
		o = vec4(dm, gen_tree(int(tile + 0.5), p, wd, m));
	} else if (tile < 8.5) {
		// 草：(aoff, warp, force6, gmod)
		vec4 a0;
		vec4 a1;
		vec4 a2;
		wf_species(WF_SP_GRASS, a0, a1, a2);
		o = vec4(dm.x, 9.0 * gen_vnoise(p * 0.035 + vec2(3.1, 7.7)) + 4.0 * gen_vnoise(p * 0.09),
			wf_force(p, wd, m, 1.0, gw_time, a0.w), 0.55 + 0.9 * gen_vnoise(p * 0.17 - wd * gw_time * 0.35));
	} else {
		// 秧苗：(aoff, m, force7, 0)
		vec4 b0;
		vec4 b1;
		vec4 b2;
		wf_species(WF_SP_PADDY, b0, b1, b2);
		o = vec4(dm, wf_force(p, wd, m, 1.0, gw_time, b0.w), 0.0);
	}
	COLOR = o;
}
