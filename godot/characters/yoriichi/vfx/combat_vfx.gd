extends Node
class_name CombatVFX
## Central VFX factory for Yoriichi's combat, jumps, and impacts.
## Generates lightweight GPU particle bursts with procedural textures and materials.

static var _spark_tex: ImageTexture = null
static var _smoke_tex: ImageTexture = null


static func _get_spark_texture() -> ImageTexture:
	if _spark_tex != null:
		return _spark_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var center := Vector2(15.5, 15.5)
	for y in range(32):
		for x in range(32):
			var d := Vector2(x, y).distance_to(center) / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * a # Sharp glowing center
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_spark_tex = ImageTexture.create_from_image(img)
	return _spark_tex


static func _get_smoke_texture() -> ImageTexture:
	if _smoke_tex != null:
		return _smoke_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var center := Vector2(15.5, 15.5)
	for y in range(32):
		for x in range(32):
			var d := Vector2(x, y).distance_to(center) / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a # Soft puff
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_smoke_tex = ImageTexture.create_from_image(img)
	return _smoke_tex


static func spawn_hit_spark(parent: Node, hit_pos: Vector3, normal: Vector3 = Vector3.UP, heavy := false) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := parent.get_tree().root

	var particles := GPUParticles3D.new()
	particles.top_level = true
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.lifetime = 0.35 if heavy else 0.25
	particles.amount = 32 if heavy else 20

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.08
	mat.direction = normal + Vector3(randf_range(-0.5, 0.5), randf_range(0.2, 0.8), randf_range(-0.5, 0.5)).normalized()
	mat.spread = 75.0
	mat.initial_velocity_min = 4.0 if heavy else 3.0
	mat.initial_velocity_max = 8.0 if heavy else 6.0
	mat.gravity = Vector3(0, -9.8, 0)
	mat.scale_min = 0.06
	mat.scale_max = 0.16 if heavy else 0.12
	# Sun Breathing gold-crimson gradient
	mat.color = Color(1.0, 0.9, 0.3, 1.0)

	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.albedo_texture = _get_spark_texture()
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES

	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	quad.material = draw_mat
	particles.draw_pass_1 = quad
	particles.process_material = mat

	root.add_child(particles)
	particles.global_position = hit_pos
	particles.restart()
	particles.emitting = true

	var timer := root.get_tree().create_timer(particles.lifetime + 0.1)
	timer.timeout.connect(particles.queue_free)


static func spawn_jump_dust(parent: Node, foot_pos: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := parent.get_tree().root

	var particles := GPUParticles3D.new()
	particles.top_level = true
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.90
	particles.lifetime = 0.40
	particles.amount = 16

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_radius = 0.35
	mat.emission_ring_inner_radius = 0.15
	mat.emission_ring_axis = Vector3.UP
	mat.direction = Vector3(0, 0.4, 0)
	mat.spread = 90.0
	mat.initial_velocity_min = 1.2
	mat.initial_velocity_max = 2.4
	mat.gravity = Vector3(0, -1.0, 0)
	mat.scale_min = 0.25
	mat.scale_max = 0.55
	mat.color = Color(0.92, 0.88, 0.80, 0.45)

	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.albedo_texture = _get_smoke_texture()
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES

	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	quad.material = draw_mat
	particles.draw_pass_1 = quad
	particles.process_material = mat

	root.add_child(particles)
	particles.global_position = foot_pos + Vector3(0, 0.05, 0)
	particles.restart()
	particles.emitting = true

	var timer := root.get_tree().create_timer(particles.lifetime + 0.1)
	timer.timeout.connect(particles.queue_free)


static func spawn_land_dust(parent: Node, foot_pos: Vector3, heavy := false) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := parent.get_tree().root

	var particles := GPUParticles3D.new()
	particles.top_level = true
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.lifetime = 0.50
	particles.amount = 24 if heavy else 18

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_radius = 0.5 if heavy else 0.35
	mat.emission_ring_inner_radius = 0.2
	mat.emission_ring_axis = Vector3.UP
	mat.direction = Vector3(0, 0.2, 0)
	mat.spread = 100.0
	mat.initial_velocity_min = 2.0 if heavy else 1.5
	mat.initial_velocity_max = 3.5 if heavy else 2.5
	mat.gravity = Vector3(0, -1.2, 0)
	mat.scale_min = 0.3
	mat.scale_max = 0.7 if heavy else 0.5
	mat.color = Color(0.90, 0.86, 0.78, 0.55 if heavy else 0.40)

	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.albedo_texture = _get_smoke_texture()
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES

	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	quad.material = draw_mat
	particles.draw_pass_1 = quad
	particles.process_material = mat

	root.add_child(particles)
	particles.global_position = foot_pos + Vector3(0, 0.05, 0)
	particles.restart()
	particles.emitting = true

	var timer := root.get_tree().create_timer(particles.lifetime + 0.1)
	timer.timeout.connect(particles.queue_free)


static func spawn_roll_dust(parent: Node, foot_pos: Vector3, dir: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := parent.get_tree().root

	var particles := GPUParticles3D.new()
	particles.top_level = true
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.8
	particles.lifetime = 0.35
	particles.amount = 12

	var mat := ParticleProcessMaterial.new()
	mat.direction = -dir + Vector3(0, 0.3, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 2.5
	mat.gravity = Vector3(0, -0.5, 0)
	mat.scale_min = 0.2
	mat.scale_max = 0.45
	mat.color = Color(0.92, 0.88, 0.82, 0.35)

	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.albedo_texture = _get_smoke_texture()
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES

	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	quad.material = draw_mat
	particles.draw_pass_1 = quad
	particles.process_material = mat

	root.add_child(particles)
	particles.global_position = foot_pos + Vector3(0, 0.05, 0)
	particles.restart()
	particles.emitting = true

	var timer := root.get_tree().create_timer(particles.lifetime + 0.1)
	timer.timeout.connect(particles.queue_free)
