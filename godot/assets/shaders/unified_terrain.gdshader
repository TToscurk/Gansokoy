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
uniform float stone_texture_scale = 0.40;
// South entrance maintenance patch; opt-in per material, no mesh/collision change.
uniform float entry_strength : hint_range(0.0, 1.0) = 0.0;
// Main-street zoning (B1 street x=235, z -60..92): compacted centre, gravel under
// eaves, damp gutter between. Opt-in per material, no mesh/collision change.
uniform float street_strength : hint_range(0.0, 1.0) = 0.0;

float entry_band(float v, float lo, float hi, float feather) {
	return smoothstep(lo, lo + feather, v) * (1.0 - smoothstep(hi - feather, hi, v));
}

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
	vec3 stone_uvw = terrain_world_position * stone_texture_scale;
	vec3 stone_sample = triplanar_sample(stone_albedo, stone_uvw, blend).rgb;
	float stone_ao_sample = triplanar_sample(stone_ao, stone_uvw, blend).r;
	float wet_weight = smoothstep(0.05, 0.95, terrain_wet_weight);
	vec3 stone = stone_sample * stone_ao_sample * mix(stone_tint, wet_stone_tint, wet_weight);
	float grass_weight = smoothstep(0.05, 0.95, terrain_grass_weight);
	vec3 terrain_color = mix(dirt, grass, grass_weight);
	float stone_weight = smoothstep(0.05, 0.95, terrain_stone_weight);
	terrain_color = mix(terrain_color, stone, stone_weight);
	// Faded earth through the gate, fine stone beneath the wall wings.
	vec2 ep = terrain_world_position.xz;
	float flat_ground = smoothstep(0.80, 0.96, terrain_world_normal.y);
	float approach = entry_band(ep.y, 96.0, 131.0, 3.0)
		* entry_band(ep.x + sin(ep.y * 0.7) * 0.10, 230.7, 240.3, 0.8)
		* entry_strength * flat_ground;
	float wings = max(entry_band(ep.x, 212.3, 231.0, 0.7), entry_band(ep.x, 240.0, 260.1, 0.7));
	float apron = entry_band(ep.y, 97.5, 100.8, 0.65) * wings * entry_strength * flat_ground;
	vec3 fine_stone = triplanar_sample(stone_albedo, terrain_world_position * 1.8, blend).rgb;
	vec3 compacted = mix(dirt * vec3(2.8, 2.65, 2.3), fine_stone * vec3(0.46, 0.40, 0.30), 0.20);
	terrain_color = mix(terrain_color, compacted, approach);
	terrain_color = mix(terrain_color, fine_stone * vec3(0.43, 0.42, 0.37), apron * 0.85);
	// Main street: |dx| from x=235. Centre 0-2.2 m trodden, 2.8-3.4 m damp gutter,
	// 3.4-4.8 m eave gravel. West plaza (z 6-44) keeps bare earth instead.
	float sdx = abs(ep.x - 235.0 + sin(ep.y * 0.23) * 0.25);
	float along = entry_band(ep.y, -62.0, 97.5, 4.0) * street_strength * flat_ground;
	float centre = (1.0 - smoothstep(1.6, 2.6, sdx)) * along;
	float gutter = entry_band(sdx, 2.45, 3.1, 0.25) * along;
	float eave = entry_band(sdx, 3.0, 4.9, 0.35) * along;
	float plaza_side = step(ep.x, 235.0) * entry_band(ep.y, 6.0, 44.0, 1.5);
	gutter *= 1.0 - plaza_side;
	eave *= 1.0 - plaza_side;
	float wear = 0.5 + 0.5 * sin(ep.x * 1.9 + ep.y * 0.7) * sin(ep.y * 2.3 - ep.x * 0.4);
	terrain_color = mix(terrain_color, dirt * vec3(1.9, 1.8, 1.55), centre * (0.55 + 0.35 * wear));
	terrain_color = mix(terrain_color, dirt * vec3(0.75, 0.74, 0.72), gutter * 0.7);
	terrain_color = mix(terrain_color, fine_stone * vec3(1.25, 1.22, 1.12), eave * 0.8);
	vec3 far_tint = vec3(0.72, 0.76, 0.72);
	ALBEDO = mix(terrain_color, terrain_color * far_tint, terrain_aerial_fade * 0.18);
	float terrain_roughness = mix(triplanar_sample(dirt_roughness, sample_position, blend).r, 0.92, grass_weight);
	float stone_r = triplanar_sample(stone_roughness, terrain_world_position * stone_texture_scale, blend).r;
	stone_r = mix(stone_r, min(stone_r, 0.48), wet_weight);
	ROUGHNESS = mix(terrain_roughness, stone_r, stone_weight);
	ROUGHNESS = mix(ROUGHNESS, 0.55, gutter * 0.8);
	ROUGHNESS = mix(ROUGHNESS, 0.95, centre * 0.6);

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
