extends SceneTree
## Place water VFX around the real 水車 in waterway_art_review, using the
## wheel's measured geometry rather than eyeballed offsets.
##
## Facts this is built on (from probe_waterwheel.gd + the live scene):
##   - 水車.glb is unit-sized (1 x 1 x 0.331) and centred on its own origin.
##   - In the scene it sits at (-4.25, 2.80, 20.5), scaled 5.5, yawed 90 deg.
##   => wheel radius 2.75 m, axle at y = 2.80, so the rim bottom is y = 0.05
##      and the canal water is at y = -0.05 (canal_water.gd). The wheel dips
##      into the water — which is exactly where the splash belongs.
##   - The 90 deg yaw means the wheel's local Z axle points along world X, so
##      the wheel face spans world Z and Y.
##
## The emitters are placed as children of Waterworks (NOT of the wheel): a child
## of the wheel would be spun by the wheel's own rotation and fling the whole
## particle system around.
##
## Output: maps/slice/gen/waterwheel_vfx.tscn
## Run: godot --headless --path godot --script tools/gen_waterwheel_vfx.gd

const OUT := "res://maps/slice/gen/waterwheel_vfx.tscn"
const SHADER := "res://maps/slice/gen/foam_sheet.gdshader"

# Measured from the live scene.
const WHEEL_POS := Vector3(-4.25, 2.80, 20.5)
const WHEEL_SCALE := 5.5
const WHEEL_RADIUS := 0.5 * WHEEL_SCALE      # 2.75 m
const WHEEL_WIDTH := 0.331 * WHEEL_SCALE     # 1.82 m
const WATER_Y := -0.05


func _init() -> void:
	var root := Node3D.new()
	root.name = "水車水花"

	# Where the rim meets the water. The wheel is yawed 90 deg, so its face
	# spans Z; the downstream side is +Z (flow runs -Z to +Z past the wheel).
	var entry := Vector3(WHEEL_POS.x, WATER_Y, WHEEL_POS.z + WHEEL_RADIUS * 0.55)
	var exit_pt := Vector3(WHEEL_POS.x, WATER_Y + 0.15, WHEEL_POS.z - WHEEL_RADIUS * 0.55)

	root.add_child(_droplets(entry))
	root.add_child(_foam(entry))
	root.add_child(_nappe())
	root.add_child(_wake(exit_pt))

	for c in root.get_children():
		c.owner = root

	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack failed: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(ps, OUT)
	if err != OK:
		push_error("save failed: %d" % err)
		quit(1)
		return

	print("水車: 位置 %s  直徑 %.2fm  寬 %.2fm" % [WHEEL_POS, WHEEL_RADIUS * 2.0, WHEEL_WIDTH])
	print("  輪緣最低點 y=%.2f，水面 y=%.2f → 入水深 %.2fm" % [
		WHEEL_POS.y - WHEEL_RADIUS, WATER_Y, WATER_Y - (WHEEL_POS.y - WHEEL_RADIUS)])
	print("[done] %s" % OUT)
	quit(0)


## Droplets thrown off the paddles as they lift clear of the water.
func _droplets(at: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "葉片飛沫"
	p.position = at
	p.amount = 260
	p.lifetime = 1.3
	p.local_coords = false
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 8, 8))

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Spread across the paddle width (world X after the 90 deg yaw).
	m.emission_box_extents = Vector3(WHEEL_WIDTH * 0.45, 0.12, 0.35)
	m.direction = Vector3(0, 1, 0.55)
	m.spread = 30.0
	m.initial_velocity_min = 1.8
	m.initial_velocity_max = 4.2
	m.gravity = Vector3(0, -9.8, 0)
	m.damping_min = 0.2
	m.damping_max = 0.8
	m.scale_min = 0.4
	m.scale_max = 1.1

	var g := Gradient.new()
	g.set_color(0, Color(0.94, 0.98, 1.0, 0.95))
	g.set_color(1, Color(0.86, 0.93, 0.97, 0.0))
	g.add_point(0.3, Color(1, 1, 1, 0.8))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m

	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.95, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.12
	mesh.material = mat
	p.draw_pass_1 = mesh
	return p


## Churned foam at the entry point.
func _foam(at: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "入水泡沫"
	p.position = at + Vector3(0, 0.05, 0)
	p.amount = 110
	p.lifetime = 2.4
	p.local_coords = false
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.visibility_aabb = AABB(Vector3(-3, -1, -4), Vector3(6, 3, 8))

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(WHEEL_WIDTH * 0.5, 0.04, 0.5)
	m.direction = Vector3(0, 0.3, 1.0)
	m.spread = 28.0
	m.initial_velocity_min = 0.3
	m.initial_velocity_max = 1.1
	m.gravity = Vector3(0, -0.35, 0)
	m.damping_min = 1.4
	m.damping_max = 2.6
	m.scale_min = 0.9
	m.scale_max = 2.4
	m.angle_min = -180.0
	m.angle_max = 180.0

	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(0.93, 0.97, 1.0, 0.0))
	g.add_point(0.18, Color(1, 1, 1, 0.6))
	g.add_point(0.65, Color(0.96, 0.99, 1.0, 0.3))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt

	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.45))
	c.add_point(Vector2(0.5, 1.0))
	c.add_point(Vector2(1.0, 1.7))
	var ct := CurveTexture.new()
	ct.curve = c
	m.scale_curve = ct
	p.process_material = m

	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = mat
	p.draw_pass_1 = quad
	return p


## The sheet of water pouring off the paddles on the descending side. A shader
## quad, not particles: this is a continuous film, and particles would render it
## as separated droplets.
func _nappe() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "葉片洩水簾"
	# Hangs on the downstream face, from axle height down toward the water.
	var drop_top := WHEEL_POS.y + WHEEL_RADIUS * 0.25
	var h: float = drop_top - WATER_Y
	mi.position = Vector3(
		WHEEL_POS.x,
		WATER_Y + h * 0.5,
		WHEEL_POS.z + WHEEL_RADIUS * 0.82
	)
	var quad := QuadMesh.new()
	quad.size = Vector2(WHEEL_WIDTH * 0.9, h)
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER)
	mat.set_shader_parameter("flow_speed", 1.9)
	mat.set_shader_parameter("opacity", 0.5)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Slow drifting foam downstream of the wheel — the tail water.
func _wake(at: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "尾水白沫"
	p.position = at
	p.amount = 60
	p.lifetime = 4.0
	p.local_coords = false
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.visibility_aabb = AABB(Vector3(-3, -1, -8), Vector3(6, 3, 16))

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(WHEEL_WIDTH * 0.55, 0.02, 0.3)
	m.direction = Vector3(0, 0, -1)
	m.spread = 12.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 1.2
	m.gravity = Vector3.ZERO   # foam floats downstream, it does not fall
	m.damping_min = 0.1
	m.damping_max = 0.4
	m.scale_min = 1.0
	m.scale_max = 2.8
	m.angle_min = -180.0
	m.angle_max = 180.0

	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(0.95, 0.98, 1.0, 0.0))
	g.add_point(0.2, Color(1, 1, 1, 0.35))
	g.add_point(0.7, Color(0.97, 0.99, 1.0, 0.16))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m

	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Lies flat on the water surface rather than facing camera: this is surface
	# scum, not airborne spray.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = mat
	p.draw_pass_1 = quad
	# Lay the quads flat.
	p.rotation_degrees = Vector3(-90, 0, 0)
	return p
