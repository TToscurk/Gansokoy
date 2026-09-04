extends SceneTree
## Build a water-VFX comparison scene: three ways to make splash in Godot 4.
##
## Why three: "how do I make water spray" has no single answer — the right tool
## depends on whether the effect is a continuous sheet, discrete droplets, or a
## surface treatment, and they cost very different amounts. Rather than pick one
## blind, author all three side by side so the user can look and choose.
##
##   A. GPUParticles3D  — discrete droplets thrown off the wheel paddles.
##   B. GPUParticles3D + mesh quads — the churned foam bed where the wheel
##      re-enters the water; many overlapping soft sprites, not points.
##   C. Shader on a mesh — the falling sheet (nappe) off the paddles, which is
##      continuous and should NOT be particles at all.
##
## All three are authored from code so the settings are reviewable in the diff
## rather than buried in a .tscn binary blob.
##
## Output: maps/slice/gen/water_vfx_demo.tscn
## Run: godot --headless --path godot --script tools/gen_water_vfx.gd

const OUT := "res://maps/slice/gen/water_vfx_demo.tscn"
const FOAM_SHADER := "res://maps/slice/gen/foam_sheet.gdshader"

const FOAM_SRC := """shader_type spatial;
// Falling water sheet (nappe). A continuous curtain of water is the WRONG job
// for particles: particles give you separated droplets, but a nappe is a
// coherent film. Scroll two noise layers at different speeds down a quad and
// the eye reads flow without any simulation cost.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, unshaded;

uniform vec3 water_tint : source_color = vec3(0.72, 0.82, 0.86);
uniform vec3 foam_tint : source_color = vec3(0.97, 0.99, 1.0);
uniform float flow_speed = 1.6;
uniform float streak_density = 7.0;
uniform float opacity = 0.62;
// Fades the top edge so the sheet emerges from the paddle instead of starting
// with a hard line.
uniform float top_fade = 0.18;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * flow_speed;
	// Two layers at different rates: one alone looks like a sliding texture.
	float n1 = noise(vec2(uv.x * streak_density, uv.y * streak_density * 0.5 - t));
	float n2 = noise(vec2(uv.x * streak_density * 2.1 + 3.7, uv.y * streak_density - t * 1.7));
	float streak = n1 * 0.6 + n2 * 0.4;

	// Foam concentrates at the bottom where the sheet breaks up.
	float lower = smoothstep(0.35, 1.0, uv.y);
	float foam = smoothstep(0.45, 0.85, streak) * lower;

	vec3 col = mix(water_tint, foam_tint, foam);
	float a = opacity * mix(0.55, 1.0, streak);
	a *= smoothstep(0.0, top_fade, uv.y);

	ALBEDO = col;
	ALPHA = a;
}
"""


func _init() -> void:
	_write_shader()

	var root := Node3D.new()
	root.name = "水花示範"

	root.add_child(_make_droplets())
	root.add_child(_make_foam_bed())
	root.add_child(_make_nappe())

	for c in root.get_children():
		c.owner = root
		for g in c.get_children():
			g.owner = root

	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack failed: %d" % err)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	err = ResourceSaver.save(ps, OUT)
	if err != OK:
		push_error("save failed: %d" % err)
		quit(1)
		return

	print("[done] %s" % OUT)
	print("  A_水滴噴濺   GPUParticles3D — 葉片甩出的水珠")
	print("  B_攪動泡沫   GPUParticles3D + 四邊形 — 入水處的翻騰白沫")
	print("  C_落水簾幕   ShaderMaterial — 葉片洩下的連續水幕")
	quit(0)


func _write_shader() -> void:
	DirAccess.make_dir_recursive_absolute(FOAM_SHADER.get_base_dir())
	var f := FileAccess.open(FOAM_SHADER, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % FOAM_SHADER)
		return
	f.store_string(FOAM_SRC)
	f.close()
	print("[ok] %s" % FOAM_SHADER)


## A. Droplets flung off the paddles. Small, fast, gravity-driven, short-lived.
func _make_droplets() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "A_水滴噴濺"
	p.amount = 220
	p.lifetime = 1.1
	p.explosiveness = 0.0
	# Global space: droplets must be left behind in the world, not dragged along
	# if the emitter node ever moves with the wheel.
	p.local_coords = false
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	# Without an explicit AABB the system gets frustum-culled the moment the
	# emitter leaves view, and the spray pops out mid-air.
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))

	var m := ParticleProcessMaterial.new()
	# A box, not a point: spray comes off the whole width of the paddle.
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(0.15, 0.25, 0.9)
	m.direction = Vector3(0.4, 1.0, 0.0)
	m.spread = 32.0
	m.initial_velocity_min = 1.6
	m.initial_velocity_max = 3.4
	m.gravity = Vector3(0, -9.8, 0)
	m.damping_min = 0.2
	m.damping_max = 0.6
	m.scale_min = 0.35
	m.scale_max = 1.0

	# Alpha must reach 0 at the end or droplets vanish with a hard pop.
	var grad := Gradient.new()
	grad.set_color(0, Color(0.93, 0.97, 1.0, 0.95))
	grad.set_color(1, Color(0.85, 0.92, 0.96, 0.0))
	grad.add_point(0.25, Color(0.98, 1.0, 1.0, 0.85))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt

	# Shrink as they fall, so the tail thins out instead of ending abruptly.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.55))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 0.15))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct

	p.process_material = m

	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.95, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.15
	mat.metallic = 0.0
	mesh.material = mat
	p.draw_pass_1 = mesh
	return p


## B. The churned foam where the wheel re-enters the canal. Soft overlapping
## quads, billboarded — droplets would read as hail here.
func _make_foam_bed() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "B_攪動泡沫"
	p.position = Vector3(0, -1.2, 0)
	p.amount = 90
	p.lifetime = 2.2
	p.local_coords = false
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.visibility_aabb = AABB(Vector3(-3, -2, -3), Vector3(6, 4, 6))

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(0.5, 0.06, 1.0)
	m.direction = Vector3(0.6, 0.35, 0.0)
	m.spread = 25.0
	m.initial_velocity_min = 0.25
	m.initial_velocity_max = 0.9
	m.gravity = Vector3(0, -0.4, 0)   # foam drifts, it does not fall like rock
	m.damping_min = 1.2
	m.damping_max = 2.4
	m.scale_min = 0.8
	m.scale_max = 2.1
	m.angle_min = -180.0
	m.angle_max = 180.0

	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.set_color(1, Color(0.92, 0.96, 0.99, 0.0))
	grad.add_point(0.15, Color(1, 1, 1, 0.55))
	grad.add_point(0.6, Color(0.96, 0.98, 1.0, 0.32))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt

	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1.0, 1.6))  # foam spreads as it dissipates
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct

	p.process_material = m

	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	# Foam sits on water; writing depth makes the sprites clip each other.
	mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = mat
	p.draw_pass_1 = quad
	return p


## C. The falling sheet. A shader on a plain quad — no particles involved.
func _make_nappe() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "C_落水簾幕"
	mi.position = Vector3(0.55, -0.6, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 1.4)
	mi.mesh = quad

	var sh: Shader = load(FOAM_SHADER)
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
