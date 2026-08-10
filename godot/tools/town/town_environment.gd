extends RefCounted


static func build(lib, root: Node3D) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ShaderMaterial.new()
	if ResourceLoader.exists("res://assets/shaders/sky_cumulus.gdshader"):
		sky_material.shader = load("res://assets/shaders/sky_cumulus.gdshader")
		sky.sky_material = sky_material
	else:
		sky.sky_material = ProceduralSkyMaterial.new()
	environment.sky = sky
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.02
	environment.glow_enabled = true
	environment.glow_intensity = 0.72
	environment.glow_hdr_threshold = 1.25
	environment.ssao_enabled = true
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.08
	environment.adjustment_saturation = 1.24
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.55
	environment.ambient_light_energy = 0.72
	environment.fog_enabled = true
	environment.fog_density = 0.0016
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.012
	environment.sdfgi_enabled = false
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	lib.add(root, world_environment, "WorldEnvironment")


static func apply_performance_pass(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var node_name := String(node.name)
		if not (node_name.contains("Terrain") or node_name.contains("Water")
				or node_name.contains("水面")):
			var bounds: AABB = node.mesh.get_aabb()
			var scale: Vector3 = node.scale.abs()
			var maximum: float = maxf(maxf(bounds.size.x * scale.x,
				bounds.size.y * scale.y), bounds.size.z * scale.z)
			if maximum < 1.35:
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if maximum < 0.9:
				node.visibility_range_end = 55.0
				node.visibility_range_end_margin = 8.0
				node.visibility_range_fade_mode = \
					GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			elif maximum < 2.8:
				node.visibility_range_end = 100.0
				node.visibility_range_end_margin = 10.0
				node.visibility_range_fade_mode = \
					GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for child in node.get_children():
		apply_performance_pass(child)
