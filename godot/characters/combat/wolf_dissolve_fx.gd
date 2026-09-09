extends Node
class_name WolfDissolveFX
## 山犬化光死亡特效：溶解 shader + 上飄光點粒子。
##
## 逐幀曲線讀 assets/enemies/wolf/dissolve_fx.json（Blender 端逐幀量測後匯出），
## 不是在這裡硬猜參數 —— 那份 JSON 才是動畫的實況權威。
##
## JSON 欄位：
##   dissolve  0→1  溶解門檻（f20 起、f88 全消）
##   emit_rate 0→1  光點粒子發射量（f40–60 最強）
##   zmin/zmax      該幀身體上下界（模型空間 z 軸 = Godot 的 y）
##   cx/cy/cz       體心，粒子發射器跟隨
##
## ⚠ JSON 是 Blender 座標（z-up）。Godot 是 y-up，兩邊軸要換：
##   Blender z（高度）→ Godot y；Blender y → Godot -z。

const FX_PATH := "res://assets/enemies/wolf/dissolve_fx.json"
const SHADER := preload("res://characters/combat/wolf_dissolve.gdshader")

static var _curve: Dictionary = {}


static func _load_curve() -> Dictionary:
	if not _curve.is_empty():
		return _curve
	var txt := FileAccess.get_file_as_string(FX_PATH)
	if txt.is_empty():
		push_warning("[狼溶解] 讀不到 %s" % FX_PATH)
		return {}
	var d: Variant = JSON.parse_string(txt)
	if not (d is Dictionary):
		push_warning("[狼溶解] %s 格式不對" % FX_PATH)
		return {}
	_curve = d
	return _curve


## 在 t 秒時的曲線值（線性內插）。回傳 {dissolve, emit_rate, ymin, ymax, centre}
static func sample(t: float) -> Dictionary:
	var c := _load_curve()
	if c.is_empty():
		return {"dissolve": clampf(t / 4.0, 0.0, 1.0), "emit_rate": 0.0,
			"ymin": 0.0, "ymax": 1.2, "centre": Vector3(0, 0.6, 0)}
	var fps := float(c.get("fps", 24.0))
	var rows: Array = c.get("frames_data", [])
	if rows.is_empty():
		return {"dissolve": 0.0, "emit_rate": 0.0, "ymin": 0.0, "ymax": 1.2,
			"centre": Vector3(0, 0.6, 0)}
	var fpos := clampf(t * fps, 0.0, float(rows.size() - 1))
	var i0 := int(floor(fpos))
	var i1 := mini(i0 + 1, rows.size() - 1)
	var w := fpos - float(i0)
	var a: Dictionary = rows[i0]
	var b: Dictionary = rows[i1]
	# Blender z-up → Godot y-up
	return {
		"dissolve": lerpf(float(a.get("dissolve", 0.0)), float(b.get("dissolve", 0.0)), w),
		"emit_rate": lerpf(float(a.get("emit_rate", 0.0)), float(b.get("emit_rate", 0.0)), w),
		"ymin": lerpf(float(a.get("zmin", 0.0)), float(b.get("zmin", 0.0)), w),
		"ymax": lerpf(float(a.get("zmax", 1.2)), float(b.get("zmax", 1.2)), w),
		"centre": Vector3(
			lerpf(float(a.get("cx", 0.0)), float(b.get("cx", 0.0)), w),
			lerpf(float(a.get("cz", 0.6)), float(b.get("cz", 0.6)), w),
			-lerpf(float(a.get("cy", 0.0)), float(b.get("cy", 0.0)), w)),
	}


static func duration() -> float:
	var c := _load_curve()
	if c.is_empty():
		return 4.0
	return float(c.get("frames", 96)) / float(c.get("fps", 24.0))


## 把狼身上的材質換成溶解 shader，貼圖從原材質搬過來。
## 回傳換好的 ShaderMaterial 陣列（之後逐幀餵參數用）。
static func install(visual_root: Node) -> Array:
	var mats: Array = []
	var stack: Array[Node] = [visual_root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		# 鑽體與提示環不是狼的身體，不換材質
		if String(mi.name) in ["GatsugaDrill", "Tell"]:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			var sm := ShaderMaterial.new()
			sm.shader = SHADER
			if src is BaseMaterial3D:
				var bm := src as BaseMaterial3D
				sm.set_shader_parameter("albedo_tex", bm.albedo_texture)
				sm.set_shader_parameter("normal_tex", bm.normal_texture)
				sm.set_shader_parameter("use_normal_map", bm.normal_texture != null)
				# GLB 的 ORM 通常掛在 roughness/metallic 的同一張圖
				var orm: Texture2D = bm.roughness_texture
				if orm == null:
					orm = bm.metallic_texture
				sm.set_shader_parameter("orm_tex", orm)
				sm.set_shader_parameter("use_orm", orm != null)
			sm.set_shader_parameter("dissolve", 0.0)
			mi.set_surface_override_material(s, sm)
			mats.append(sm)
	return mats


## 光點粒子：由下往上飄的藍白光屑。
static func make_particles(parent: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "DissolveMotes"
	p.amount = 220
	p.lifetime = 1.6
	p.explosiveness = 0.0
	p.emitting = false
	p.local_coords = false
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(0.35, 0.5, 0.7)
	m.direction = Vector3(0, 1, 0)
	m.spread = 22.0
	m.initial_velocity_min = 0.35
	m.initial_velocity_max = 1.1
	# 微弱上浮，不受重力
	m.gravity = Vector3(0, 0.45, 0)
	m.damping_min = 0.2
	m.damping_max = 0.6
	m.scale_min = 0.4
	m.scale_max = 1.0
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.15))
	scale_curve.add_point(Vector2(0.25, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var sct := CurveTexture.new()
	sct.curve = scale_curve
	m.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.75, 0.93, 1.0, 1.0))
	grad.set_color(1, Color(0.35, 0.6, 1.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	p.process_material = m

	var qm := QuadMesh.new()
	qm.size = Vector2(0.085, 0.085)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _mote_texture()
	mat.disable_receive_shadows = true
	qm.material = mat
	p.draw_pass_1 = qm
	parent.add_child(p)
	return p


static var _mote_tex: ImageTexture = null


static func _mote_texture() -> ImageTexture:
	if _mote_tex != null:
		return _mote_tex
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	var c := Vector2(11.5, 11.5)
	for y in 24:
		for x in 24:
			var d := Vector2(x, y).distance_to(c) / 11.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_mote_tex = ImageTexture.create_from_image(img)
	return _mote_tex
