extends RefCounted
## shrine_v3 材質庫：建出並存成 assets/shrine_v3/mat/*.tres（場景只引用，不內嵌）。
## 貼圖一律 Poly Haven CC0（assets/shrine_v3/tex/ph/SOURCES.json）。

const PH := "res://assets/shrine_v3/tex/ph/"
const GEN_TEX := "res://assets/shrine_v3/tex/gen/"
const MAT := "res://assets/shrine_v3/mat/"
const SH := "res://assets/shrine_v3/shaders/"


static func ph(id: String, kind: String, res: String) -> Texture2D:
	return load(PH + "%s_%s_%s.jpg" % [id, kind, res]) as Texture2D


static func terrain() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SH + "s3_terrain.gdshader")
	m.set_shader_parameter("mask_a", load("res://maps/shrine_v3/gen/mask_a.res"))
	m.set_shader_parameter("mask_b", load("res://maps/shrine_v3/gen/mask_b.res"))
	m.set_shader_parameter("grass_d", ph("leafy_grass", "diff", "2k"))
	m.set_shader_parameter("grass_n", ph("leafy_grass", "nor_gl", "2k"))
	m.set_shader_parameter("forest_d", ph("leaves_forest_ground", "diff", "2k"))
	m.set_shader_parameter("forest_n", ph("leaves_forest_ground", "nor_gl", "2k"))
	m.set_shader_parameter("dirt_d", ph("dirt_floor", "diff", "2k"))
	m.set_shader_parameter("dirt_n", ph("dirt_floor", "nor_gl", "2k"))
	m.set_shader_parameter("trail_d", ph("rocky_trail", "diff", "2k"))
	m.set_shader_parameter("trail_n", ph("rocky_trail", "nor_gl", "2k"))
	m.set_shader_parameter("rock_d", ph("rock_face_03", "diff", "2k"))
	m.set_shader_parameter("rock_n", ph("rock_face_03", "nor_gl", "2k"))
	m.set_shader_parameter("moss_d", ph("forest_leaves_02", "diff", "1k"))
	return m


static func vista(inner: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SH + "s3_vista.gdshader")
	m.set_shader_parameter("inner_rect", Vector4(float(inner["x0"]), float(inner["z0"]), float(inner["x1"]), float(inner["z1"])))
	return m


static func _std(id: String, res: String, tile_m: float, tint: Color, rough := 1.0, nrm := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = ph(id, "diff", res)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = ph(id, "nor_gl", res)
	m.normal_scale = nrm
	m.roughness_texture = ph(id, "rough", res)
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = rough
	m.uv1_scale = Vector3(1.0 / tile_m, 1.0 / tile_m, 1.0)
	m.vertex_color_use_as_albedo = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func _flat(c: Color, rough := 0.9, vc := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.vertex_color_use_as_albedo = vc
	return m


## 建築／道具材質（名字＝Blender 端材質名）。
static func asset(name: String) -> Material:
	match name:
		"s3_wood_old":
			return _std("plank_flooring_03", "2k", 1.8, Color(0.74, 0.68, 0.62))
		"s3_wood_new":
			return _std("hinoki_planks", "1k", 1.4, Color(1.0, 0.94, 0.86))
		"s3_wood_dark":
			return _std("dark_wooden_planks", "2k", 1.6, Color(0.80, 0.76, 0.72))
		"s3_roof":
			return _std("grey_roof_tiles", "2k", 2.4, Color(0.58, 0.60, 0.62), 1.0, 1.2)
		"s3_earth":
			return _std("dirt_floor", "2k", 2.2, Color(0.92, 0.88, 0.84))
		"s3_straw":
			return _std("thatch_roof_angled", "1k", 0.6, Color(0.95, 0.88, 0.70))
		"s3_stone", "s3_stone_moss":
			var m := ShaderMaterial.new()
			m.shader = load(SH + "s3_stone.gdshader")
			m.set_shader_parameter("stone_d", ph("rock_boulder_dry", "diff", "2k"))
			m.set_shader_parameter("stone_n", ph("rock_boulder_dry", "nor_gl", "2k"))
			m.set_shader_parameter("moss_d", ph("forest_leaves_02", "diff", "1k"))
			m.set_shader_parameter("moss_amount", 0.75 if name == "s3_stone_moss" else 0.42)
			return m
		"s3_stone_tri":
			var m2 := asset("s3_stone") as ShaderMaterial
			m2.set_shader_parameter("triplanar", true)
			m2.set_shader_parameter("tile", 0.9)
			return m2
		"s3_paint_red", "s3_paint_black":
			var p := ShaderMaterial.new()
			p.shader = load(SH + "s3_paint.gdshader")
			p.set_shader_parameter("wood_d", ph("dark_wooden_planks", "diff", "2k"))
			p.set_shader_parameter("wood_n", ph("dark_wooden_planks", "nor_gl", "2k"))
			if name == "s3_paint_black":
				p.set_shader_parameter("paint_col", Color(0.055, 0.050, 0.048))
				p.set_shader_parameter("fade", 0.10)
				p.set_shader_parameter("wear", 0.12)
				p.set_shader_parameter("paint_rough", 0.55)
			return p
		"s3_paper":
			var pp := _flat(Color(0.93, 0.92, 0.87), 0.9)
			pp.cull_mode = BaseMaterial3D.CULL_DISABLED
			pp.backlight_enabled = true
			pp.backlight = Color(0.5, 0.48, 0.42)
			return pp
		"s3_metal":
			var mm := _flat(Color(0.50, 0.40, 0.22), 0.45, false)
			mm.metallic = 0.85
			return mm
		"s3_interior":
			return _flat(Color(0.025, 0.02, 0.018), 1.0, false)
		"s3_bamboo":
			return _std("hinoki_planks", "1k", 0.8, Color(0.92, 0.88, 0.62))
		"s3_rope_rw":
			var r := StandardMaterial3D.new()
			r.albedo_texture = load(GEN_TEX + "rope_rw.png")
			r.roughness = 0.95
			r.uv1_scale = Vector3(4.0, 4.0, 1.0)
			return r
		"s3_plaque":
			var q := StandardMaterial3D.new()
			q.albedo_texture = load(GEN_TEX + "plaque_hakurei.png")
			q.roughness = 0.6
			return q
		"s3_stone_text":
			var q2 := StandardMaterial3D.new()
			q2.albedo_texture = load(GEN_TEX + "stone_text_hakurei.png")
			q2.roughness = 0.9
			return q2
		"s3_water":
			var w := ShaderMaterial.new()
			w.shader = load(SH + "s3_water.gdshader")
			w.set_shader_parameter("depth_m", 0.35)
			w.set_shader_parameter("clarity", 0.7)
			return w
	push_error("s3mat: 未知材質 %s" % name)
	return _flat(Color(1, 0, 1))


## 取庫裡的材質（第一次建立並存檔；之後直接讀 .tres）。rebuild=true 強制重建。
static func get_mat(name: String, rebuild := false) -> Material:
	var p := MAT + name + ".tres"
	if not rebuild and ResourceLoader.exists(p):
		return load(p) as Material
	var m := asset(name)
	m.resource_name = name
	return save(m, name)


static func save(m: Material, nm: String) -> Material:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAT))
	var p := MAT + nm + ".tres"
	var e := ResourceSaver.save(m, p)
	if e != OK:
		push_error("材質存檔失敗 %s err=%d" % [p, e])
	return load(p) as Material
