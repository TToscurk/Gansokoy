shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_roughness : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_roughness : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float stone_normal_strength = 1.0;
uniform vec3 dirt_tint : source_color = vec3(0.68, 0.52, 0.26);
uniform vec3 grass_tint : source_color = vec3(0.42, 0.52, 0.30);
uniform vec3 stone_tint : source_color = vec3(0.34, 0.34, 0.32);
uniform vec3 wet_stone_tint : source_color = vec3(0.18, 0.23, 0.22);
uniform float texture_scale = 0.18;
// 去平鋪：第二層取樣的比例，與主層互質才不會同步重複
uniform float detile_ratio = 0.37;
uniform float detile_blend_scale = 0.031;  // 混合遮罩的世界尺度（約 32 m）
uniform float macro_amount = 1.0;          // 大尺度明暗變化強度
uniform float stone_texture_scale = 0.40;

varying vec3 terrain_world_position;
varying vec3 terrain_world_normal;
varying float terrain_grass_weight;
varying float terrain_aerial_fade;
varying float terrain_stone_weight;
varying float terrain_wet_weight;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec4 triplanar_sample(sampler2D tex, vec3 p, vec3 blend) {
	vec4 x_axis = texture(tex, p.zy);
	vec4 y_axis = texture(tex, p.xz);
	vec4 z_axis = texture(tex, p.xy);
	return x_axis * blend.x + y_axis * blend.y + z_axis * blend.z;
}

void vertex() {
	terrain_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	terrain_world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	terrain_grass_weight = COLOR.r;
	terrain_aerial_fade = COLOR.g;
	terrain_stone_weight = COLOR.b;
	terrain_wet_weight = COLOR.a;
}

void fragment() {
	vec3 blend = pow(abs(terrain_world_normal), vec3(4.0));
	blend /= max(blend.x + blend.y + blend.z, 0.0001);
	vec3 sample_position = terrain_world_position * texture_scale;
	// 同一張貼圖以兩個互質比例各取樣一次，用低頻遮罩混合：5.5 m 的規則
	// 網格在 50 m 俯視下原本一眼看穿，這是最便宜的破除方式。
	vec3 sample_position_b = terrain_world_position * (texture_scale * detile_ratio);
	float detile = smoothstep(0.35, 0.65,
		vnoise(terrain_world_position.xz * detile_blend_scale));
	vec3 dirt = mix(
		triplanar_sample(dirt_albedo, sample_position, blend).rgb,
		triplanar_sample(dirt_albedo, sample_position_b, blend).rgb, detile) * dirt_tint;
	vec3 grass = mix(
		triplanar_sample(grass_albedo, sample_position, blend).rgb,
		triplanar_sample(grass_albedo, sample_position_b, blend).rgb, detile) * grass_tint;
	// 大尺度明暗：草地不再是一片死平的同一個值
	float macro = vnoise(terrain_world_position.xz * 0.011) * 0.6
		+ vnoise(terrain_world_position.xz * 0.0038) * 0.4;
	grass *= mix(1.0, mix(0.80, 1.18, macro), macro_amount);
	dirt *= mix(1.0, mix(0.87, 1.11, macro), macro_amount);
	vec3 stone_uvw = terrain_world_position * stone_texture_scale;
	vec3 stone_sample = triplanar_sample(stone_albedo, stone_uvw, blend).rgb;
	float stone_ao_sample = triplanar_sample(stone_ao, stone_uvw, blend).r;
	float wet_weight = smoothstep(0.05, 0.95, terrain_wet_weight);
	vec3 stone = stone_sample * stone_ao_sample * mix(stone_tint, wet_stone_tint, wet_weight);
	float grass_weight = smoothstep(0.05, 0.95, terrain_grass_weight);
	vec3 terrain_color = mix(dirt, grass, grass_weight);
	float stone_weight = smoothstep(0.05, 0.95, terrain_stone_weight);
	terrain_color = mix(terrain_color, stone, stone_weight);
	vec3 far_tint = vec3(0.72, 0.76, 0.72);
	ALBEDO = mix(terrain_color, terrain_color * far_tint, terrain_aerial_fade * 0.18);
	float terrain_roughness = mix(triplanar_sample(dirt_roughness, sample_position, blend).r, 0.92, grass_weight);
	float stone_r = triplanar_sample(stone_roughness, terrain_world_position * stone_texture_scale, blend).r;
	stone_r = mix(stone_r, min(stone_r, 0.48), wet_weight);
	ROUGHNESS = mix(terrain_roughness, stone_r, stone_weight);

	// Triplanar normal mapping (whiteout blend) for the masonry only. The
	// geometry mesh has no UVs, so tangent-space NORMAL_MAP is unavailable;
	// build the perturbed normal in world space and hand it to view space.
	if (stone_weight > 0.001) {
		vec3 wn = terrain_world_normal;
		vec3 tnx = texture(stone_normal, stone_uvw.zy).xyz * 2.0 - 1.0;
		vec3 tny = texture(stone_normal, stone_uvw.xz).xyz * 2.0 - 1.0;
		vec3 tnz = texture(stone_normal, stone_uvw.xy).xyz * 2.0 - 1.0;
		tnx = vec3(tnx.xy + wn.zy, abs(tnx.z) * wn.x);
		tny = vec3(tny.xy + wn.xz, abs(tny.z) * wn.y);
		tnz = vec3(tnz.xy + wn.xy, abs(tnz.z) * wn.z);
		vec3 world_bumped = normalize(
				tnx.zyx * blend.x + tny.xzy * blend.y + tnz.xyz * blend.z);
		vec3 final_world = normalize(mix(wn, world_bumped,
				stone_weight * stone_normal_strength));
		NORMAL = normalize((VIEW_MATRIX * vec4(final_world, 0.0)).xyz);
	}
}
