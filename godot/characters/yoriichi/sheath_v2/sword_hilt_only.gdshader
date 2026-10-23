shader_type spatial;
render_mode cull_disabled;

// 鞘中刀：模型空間 y > clip_y（刀身）不畫。
uniform float clip_y = 0.135;
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D normal_tex : hint_normal;
uniform bool use_normal = false;
// glTF metallicRoughness：G = roughness、B = metallic
uniform sampler2D orm_tex : hint_default_white;
uniform float roughness = 1.0;
uniform float metallic = 0.0;

varying float model_y;

void vertex() {
	model_y = VERTEX.y;
}

void fragment() {
	if (model_y > clip_y) {
		discard;
	}
	ALBEDO = texture(albedo_tex, UV).rgb * albedo_color.rgb;
	vec4 orm = texture(orm_tex, UV);
	ROUGHNESS = orm.g * roughness;
	METALLIC = orm.b * metallic;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
