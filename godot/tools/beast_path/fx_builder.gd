extends RefCounted
## 獸道 S04 特效（V1.1）：瀑布落水的水霧與飛濺（GPUParticles3D）。
## 設計取捨：水霧「很淡」——是潭面上方一層緩慢上升的薄霧（峰值 alpha ≈ 0.16），不是一堵白牆；
## 飛濺是撞擊瞬間的小水珠。兩者都不建碰撞、不投影、80 m 外不畫（GTX 1070 的預算）。


static func _soft_sprite(radial_to: float = 1.0) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.5 + 0.5 * radial_to)
	t.width = 128
	t.height = 128
	return t


static func _quad_mat(fade_dist: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_sprite()
	if fade_dist > 0.0:
		m.proximity_fade_enabled = true
		m.proximity_fade_distance = fade_dist
	return m


static func _ramp(a: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for e: Array in a:
		offs.append(float(e[0]))
		cols.append(e[1] as Color)
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	return t


static func _curve(a: Array) -> CurveTexture:
	var c := Curve.new()
	for e: Array in a:
		c.add_point(Vector2(float(e[0]), float(e[1])))
	var t := CurveTexture.new()
	t.curve = c
	return t


## 落水點上方緩慢升起的薄霧。imp＝落水點（世界座標）、width＝水幕底寬。
static func waterfall_mist(imp: Vector3, width: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "WaterfallMist"
	p.amount = 18
	p.lifetime = 4.0
	p.preprocess = 4.4
	p.randomness = 0.6
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_range_end = 80.0
	p.visibility_aabb = AABB(Vector3(-10, -3, -10), Vector3(20, 14, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.20, 0.10, 0.6)
	pm.direction = Vector3(0.0, 1.0, 0.35)                # 往上、略往南（離開崖面朝戰場）
	pm.spread = 30.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0.0, 0.10, 0.04)
	pm.damping_min = 0.2
	pm.damping_max = 0.5
	pm.scale_min = 0.9
	pm.scale_max = 1.8
	pm.scale_curve = _curve([[0.0, 0.4], [0.5, 0.9], [1.0, 1.2]])
	pm.color_ramp = _ramp([[0.0, Color(0.92, 0.96, 0.97, 0.0)], [0.22, Color(0.92, 0.96, 0.97, 0.042)], [0.6, Color(0.9, 0.95, 0.96, 0.024)], [1.0, Color(0.9, 0.95, 0.96, 0.0)]])
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = _quad_mat(0.9)
	p.draw_pass_1 = q
	p.position = imp + Vector3(0.0, 0.9, 0.0)
	return p


## 撞擊瞬間的小水珠（短命、向上噴、受重力落回潭面）。
static func waterfall_spray(imp: Vector3, width: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "WaterfallSpray"
	p.amount = 30
	p.lifetime = 0.95
	p.preprocess = 1.0
	p.randomness = 0.8
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_range_end = 55.0
	p.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 8, 16))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.36, 0.05, 0.7)
	pm.direction = Vector3(0.0, 1.0, 0.25)
	pm.spread = 52.0
	pm.initial_velocity_min = 1.6
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0.0, -9.0, 0.0)
	pm.scale_min = 0.045
	pm.scale_max = 0.11
	pm.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0.0)], [0.12, Color(1, 1, 1, 0.6)], [1.0, Color(1, 1, 1, 0.0)]])
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = _quad_mat(0.0)
	p.draw_pass_1 = q
	p.position = imp + Vector3(0.0, 0.1, 0.0)
	return p
