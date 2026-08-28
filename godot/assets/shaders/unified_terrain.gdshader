shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_roughness : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_roughness : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 dirt_tint : source_color = vec3(0.68, 0.52, 0.26);
uniform vec3 grass_tint : source_color = vec3(0.42, 0.52, 0.30);
uniform vec3 stone_tint : source_color = vec3(0.34, 0.34, 0.32);
uniform vec3 wet_stone_tint : source_color = vec3(0.18, 0.23, 0.22);
uniform float texture_scale = 0.18;
uniform float stone_texture_scale = 0.40;

varying vec3 terrain_world_position;
varying vec3 terrain_world_normal;
varying float terrain_grass_weight;
varying float terrain_aerial_fade;
varying float terrain_stone_weight;
varying float terrain_wet_weight;

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
	vec3 dirt = triplanar_sample(dirt_albedo, sample_position, blend).rgb * dirt_tint;
	vec3 grass = triplanar_sample(grass_albedo, sample_position, blend).rgb * grass_tint;
	vec3 stone_sample = triplanar_sample(stone_albedo, terrain_world_position * stone_texture_scale, blend).rgb;
	float wet_weight = smoothstep(0.05, 0.95, terrain_wet_weight);
	vec3 stone = stone_sample * mix(stone_tint, wet_stone_tint, wet_weight);
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
}
