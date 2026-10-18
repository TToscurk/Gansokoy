// 暖簾（noren）風擺 V1 —— 給 village_v2 的 50 片 nr_noren_* 用。
//
// 為什麼不是 cloth simulation：暖簾是一張 1.64 × 0.70 m 的 0.001 m 薄片，掛在固定吊竿上，
// 玩家永遠從正面看。用頂點著色器做「上緣釘死、下襬隨風」就夠，成本是 0 個 CPU 骨骼。
// 形狀：
//   hang＝0 在吊竿、1 在下襬；權重再乘 smoothstep 讓上緣多留 12 % 完全不動（吊竿處不會撕開）。
//   主擺＝沿全域風向；側擺＋上抬＝布面被風撐起的二次運動；相位吃世界座標 → 不同店面不同步。
// 材質參數由 Wind autoload 從 V2_MachiyaKit.tres 複製（atlas／vertex color／發光），外觀與相鄰 kit 一致。
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D emit_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 albedo_color = vec3(0.42, 0.42, 0.42);
uniform float emit_energy = 0.4;
uniform float wind_gain = 1.0;
uniform float roughness = 0.9;
uniform float specular = 0.2;

// 逐節點：吊竿高度、布長（mesh 局部座標；Wind._attach_cloth 從 mesh AABB 算）
instance uniform float cloth_top = 1.9;
instance uniform float cloth_len = 0.7;
// 逐節點風場樣本（dir.x, dir.z, strength, 0）：由 Wind 每 0.2 s 依世界座標＋遮蔽取樣。
// 沒有這個值時退回全域場，材質在其他場景也能單獨預覽。
instance uniform vec4 obj_wind = vec4(0.0);

global uniform vec3 gw_dir;
global uniform float gw_strength;
global uniform float gw_gust;
global uniform float gw_time;
global uniform float gw_flutter;

// 世界向量→局部（等比縮放＋旋轉）
vec3 to_local(vec3 v, mat4 m) {
	return vec3(dot(v, m[0].xyz), dot(v, m[1].xyz), dot(v, m[2].xyz));
}

void vertex() {
	vec2 wd2;
	float ls;
	if (obj_wind.z > 0.001) {
		wd2 = normalize(obj_wind.xy + vec2(1e-4, 0.0));
		ls = obj_wind.z;
	} else {
		wd2 = normalize(gw_dir.xz + vec2(1e-4, 0.0));
		ls = gw_strength;
	}
	float hang = clamp((cloth_top - VERTEX.y) / max(cloth_len, 0.05), 0.0, 1.0);
	float w = hang * hang * smoothstep(0.0, 0.12, hang);
	if (ls > 0.0 && w > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float t = gw_time;
		float ph = wp.x * 1.7 + wp.z * 1.3;
		float billow = sin(t * 2.1 + ph + hang * 3.0) * 0.55
			+ sin(t * 4.7 + ph * 1.7 + hang * 5.0) * 0.2;
		float amp = 0.055 * wind_gain * ls * (1.0 + 0.5 * gw_gust) * gw_flutter;
		vec3 o = vec3(wd2.x, 0.0, wd2.y) * amp * w * (0.65 + 0.5 * billow);
		o += vec3(-wd2.y, 0.0, wd2.x) * amp * 0.45 * w * sin(t * 3.3 + ph + hang * 4.0);
		o.y += amp * 0.22 * w * (0.5 + 0.5 * sin(t * 2.7 + ph));
		VERTEX += to_local(o, MODEL_MATRIX);
	}
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	ALBEDO = a.rgb * albedo_color * COLOR.rgb;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	EMISSION = texture(emit_tex, UV).rgb * emit_energy;
}
