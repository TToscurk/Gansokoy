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


## 忍殺的爆發。與 spawn_hit_spark 同一條管線（不新增資產），差別只在
## 白金色、量多、更亮 —— 處決必須在 0.1 秒內被認出來，不能和普通命中一樣。
static func spawn_deathblow_burst(parent: Node, hit_pos: Vector3, normal: Vector3 = Vector3.UP) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := parent.get_tree().root

	var particles := GPUParticles3D.new()
	particles.top_level = true
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.lifetime = 0.55
	particles.amount = 48

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.15
	mat.direction = normal
	mat.spread = 90.0
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 11.0
	mat.gravity = Vector3(0, -7.0, 0)
	mat.scale_min = 0.10
	mat.scale_max = 0.26
	mat.color = Color(1.0, 0.98, 0.85, 1.0)

	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.albedo_texture = _get_spark_texture()
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES

	var quad := QuadMesh.new()
	quad.size = Vector2(0.42, 0.42)
	quad.material = draw_mat
	particles.draw_pass_1 = quad
	particles.process_material = mat

	root.add_child(particles)
	particles.global_position = hit_pos
	particles.restart()
	particles.emitting = true

	var timer := root.create_tween()
	timer.tween_interval(particles.lifetime + 0.1)
	timer.tween_callback(particles.queue_free)


## 日之呼吸起手火光：型發動的瞬間，刀根爆出一圈金紅火焰（環狀往外＋往上），
## 加一盞 0.18 s 的暖色點光，讓角色與地面被火照亮。同一條粒子管線，不新增貼圖。
## 這是「型」與「普通斬」的視覺分野 —— 玩家在 0.1 s 內要認得出自己剛按出型。
static func spawn_form_ignite(parent: Node, origin: Vector3, forward: Vector3 = Vector3.FORWARD) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := parent.get_tree().root

	# 1. 火焰環（往外炸、緩升）
	var ring := GPUParticles3D.new()
	ring.top_level = true
	ring.emitting = false
	ring.one_shot = true
	ring.explosiveness = 1.0
	ring.lifetime = 0.38
	ring.amount = 30
	var rm := ParticleProcessMaterial.new()
	rm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	rm.emission_ring_radius = 0.22
	rm.emission_ring_inner_radius = 0.10
	rm.emission_ring_axis = Vector3.UP
	rm.direction = Vector3(0, 1, 0)
	rm.spread = 70.0
	rm.initial_velocity_min = 2.5
	rm.initial_velocity_max = 5.5
	rm.gravity = Vector3(0, 3.0, 0)   # 火往上飄
	rm.damping_min = 4.0
	rm.damping_max = 7.0
	rm.scale_min = 0.07
	rm.scale_max = 0.16
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.55, 1.0))
	grad.set_color(1, Color(1.0, 0.25, 0.05, 0.0))
	grad.add_point(0.35, Color(1.0, 0.55, 0.12, 0.9))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	rm.color_ramp = gt
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.vertex_color_use_as_albedo = true
	dm.albedo_texture = _get_smoke_texture()
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	quad.material = dm
	ring.draw_pass_1 = quad
	ring.process_material = rm
	root.add_child(ring)
	ring.global_position = origin
	ring.restart()
	ring.emitting = true

	# 2. 前方火星噴流（沿刀向）
	var jet := GPUParticles3D.new()
	jet.top_level = true
	jet.emitting = false
	jet.one_shot = true
	jet.explosiveness = 0.9
	jet.lifetime = 0.35
	jet.amount = 18
	var jm := ParticleProcessMaterial.new()
	jm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	jm.emission_sphere_radius = 0.08
	jm.direction = (forward + Vector3(0, 0.35, 0)).normalized()
	jm.spread = 28.0
	jm.initial_velocity_min = 5.0
	jm.initial_velocity_max = 9.0
	jm.gravity = Vector3(0, -6.0, 0)
	jm.scale_min = 0.05
	jm.scale_max = 0.12
	jm.color = Color(1.0, 0.85, 0.35, 1.0)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = _get_spark_texture()
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var sq := QuadMesh.new()
	sq.size = Vector2(0.22, 0.22)
	sq.material = sm
	jet.draw_pass_1 = sq
	jet.process_material = jm
	root.add_child(jet)
	jet.global_position = origin
	jet.restart()
	jet.emitting = true

	# 3. 暖色閃光燈
	var light := OmniLight3D.new()
	light.top_level = true
	light.light_color = Color(1.0, 0.55, 0.18)
	light.light_energy = 6.0
	light.omni_range = 4.5
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	root.add_child(light)
	light.global_position = origin + Vector3(0, 0.3, 0)
	var lt := root.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	lt.tween_callback(light.queue_free)

	var cleanup := root.create_tween()
	cleanup.tween_interval(ring.lifetime + 0.15)
	cleanup.tween_callback(ring.queue_free)
	cleanup.tween_callback(jet.queue_free)


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
