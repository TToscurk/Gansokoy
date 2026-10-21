extends SceneTree
## 把 Blender 匯出的小道具（賽錢箱／板倉／掃帚）轉成專案資產：
##   · 網格存成 .res，材質依名稱掛專案貼圖材質（assets/shrine_v2/mat/*.tres，首次執行時產生）
##   · 包成可單獨開啟的 .tscn（Model＋Collision）
##   godot --headless --path godot --script res://tools/shrine_v2/build_props.gd
## 原始檔：assets/shrine_v2/src/make_shrine_props.py ＋ shrine_props_r3.blend（Blender 5.2.1）

const PROPS := "res://assets/shrine_v2/props/"
const MATD := "res://assets/shrine_v2/mat/"
const TEX := "res://assets/textures/"


func _init() -> void:
	_run.call_deferred()


func _tex(n: String) -> Texture2D:
	return load(TEX + n) as Texture2D


func _std(nm: String, albedo := Color.WHITE, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = nm
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	return m


func _textured(m: StandardMaterial3D, diff: String, nor: String, rough_t: String, uv: Vector3) -> StandardMaterial3D:
	m.albedo_texture = _tex(diff)
	if nor != "":
		m.normal_enabled = true
		m.normal_texture = _tex(nor)
		m.normal_scale = 0.8
	if rough_t != "":
		m.roughness_texture = _tex(rough_t)
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.uv1_scale = uv
	return m


func _mats() -> Dictionary:
	var d := {}
	d["wood_dark"] = _textured(_std("wood_dark", Color(0.62, 0.58, 0.56), 0.93), "dark_wood_diff.jpg", "dark_wood_nor_gl.jpg", "dark_wood_rough.jpg", Vector3(1.1, 1.1, 1))
	d["plank"] = _textured(_std("plank", Color(0.92, 0.88, 0.82), 0.92), "planks_diff.jpg", "planks_nor_gl.jpg", "planks_rough.jpg", Vector3(0.9, 0.62, 1))
	d["roof_tile"] = _textured(_std("roof_tile", Color(0.70, 0.72, 0.74), 0.82), "roof_kawara_diff.jpg", "", "", Vector3(0.62, 0.62, 1))
	d["roof_ridge"] = _textured(_std("roof_ridge", Color(0.55, 0.56, 0.58), 0.82), "roof_kawara_diff.jpg", "", "", Vector3(0.9, 0.9, 1))
	d["stone_foot"] = _textured(_std("stone_foot", Color(0.80, 0.78, 0.74), 0.95), "stone_wall_diff.jpg", "", "", Vector3(0.7, 0.7, 1))
	d["iron"] = _std("iron", Color(0.10, 0.10, 0.11), 0.55, 0.7)
	d["bronze"] = _std("bronze", Color(0.36, 0.25, 0.11), 0.62, 0.55)
	d["dark_inside"] = _std("dark_inside", Color(0.02, 0.015, 0.01), 1.0, 0.0)
	d["straw"] = _std("straw", Color(0.72, 0.60, 0.34), 0.95, 0.0)
	d["bamboo"] = _std("bamboo", Color(0.52, 0.45, 0.24), 0.7, 0.0)
	return d


func _mesh_of(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return n
	for c in n.get_children():
		var r := _mesh_of(c)
		if r != null:
			return r
	return null


func _col_box(body: StaticBody3D, owner_n: Node, nm: String, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = nm
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.position = pos
	body.add_child(cs)
	cs.owner = owner_n


func _build(id: String, mats: Dictionary, colliders: Array) -> void:
	var ps := load(PROPS + id + ".glb") as PackedScene
	var inst := ps.instantiate()
	var mi := _mesh_of(inst)
	var mesh := mi.mesh as ArrayMesh
	for s in mesh.get_surface_count():
		var old := mesh.surface_get_material(s)
		var nm := old.resource_name if old != null else ""
		if mats.has(nm):
			mesh.surface_set_material(s, mats[nm])
		elif nm == "hono_engraved" and old is BaseMaterial3D:
			var bm := (old as BaseMaterial3D).duplicate() as BaseMaterial3D
			bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			bm.cull_mode = BaseMaterial3D.CULL_BACK
			bm.roughness = 0.9
			bm.metallic = 0.0
			mesh.surface_set_material(s, bm)
		elif nm == "emblem" and old is BaseMaterial3D:
			var em := (old as BaseMaterial3D).duplicate() as BaseMaterial3D
			em.metallic = 0.15
			em.roughness = 0.6
			mesh.surface_set_material(s, em)
		print("  [%s] surface %d: %s" % [id, s, nm])
	mesh.resource_name = id
	ResourceSaver.save(mesh, PROPS + id + "_mesh.res")
	mesh = load(PROPS + id + "_mesh.res")
	var w := Node3D.new()
	w.name = id.capitalize().replace(" ", "")
	var m2 := MeshInstance3D.new()
	m2.name = "Model"
	m2.mesh = mesh
	m2.transform = mi.transform
	w.add_child(m2)
	m2.owner = w
	if colliders.size() > 0:
		var body := StaticBody3D.new()
		body.name = "Collision"
		w.add_child(body)
		body.owner = w
		for c in colliders:
			_col_box(body, w, c[0], c[1], c[2])
	var bb := mesh.get_aabb()
	w.set_meta("aabb_size", bb.size)
	var pk := PackedScene.new()
	pk.pack(w)
	var e := ResourceSaver.save(pk, PROPS + id + ".tscn")
	print("[PROPS] %s -> .tscn err=%d aabb=%s tris=%d" % [id, e, bb, _tris(mesh)])
	inst.free()
	w.free()


func _build_komainu() -> void:
	## 狛犬：沿用 assets/models/komainu_a.glb 的造型，換成風化灰石材質（GLB 原本近乎純白）。
	var ps := load("res://assets/models/komainu_a.glb") as PackedScene
	var inst := ps.instantiate()
	var mi := _mesh_of(inst)
	var mesh := mi.mesh as ArrayMesh
	var stone := _std("komainu_stone", Color(0.86, 0.84, 0.79), 0.96)
	stone.albedo_texture = _tex("stone_wall_diff.jpg")
	stone.uv1_triplanar = true
	stone.uv1_scale = Vector3(1.1, 1.1, 1.1)
	stone.uv1_world_triplanar = false
	ResourceSaver.save(stone, MATD + "komainu_stone.tres")
	stone = load(MATD + "komainu_stone.tres")
	for s in mesh.get_surface_count():
		mesh.surface_set_material(s, stone)
	mesh.resource_name = "komainu"
	ResourceSaver.save(mesh, PROPS + "komainu_mesh.res")
	mesh = load(PROPS + "komainu_mesh.res")
	var bb := mesh.get_aabb()
	var sc := 1.15 / maxf(bb.size.y, 0.01)
	var w := Node3D.new()
	w.name = "Komainu"
	var m2 := MeshInstance3D.new()
	m2.name = "Model"
	m2.mesh = mesh
	m2.transform = Transform3D(Basis.from_scale(Vector3.ONE * sc), Vector3(-(bb.position.x + bb.size.x * 0.5) * sc, -bb.position.y * sc, -(bb.position.z + bb.size.z * 0.5) * sc))
	w.add_child(m2)
	m2.owner = w
	var body := StaticBody3D.new()
	body.name = "Collision"
	w.add_child(body)
	body.owner = w
	_col_box(body, w, "Box", bb.size * sc * Vector3(0.8, 1.0, 0.8), Vector3(0, bb.size.y * sc * 0.5, 0))
	w.set_meta("aabb_pos", Vector3.ZERO)
	w.set_meta("aabb_size", bb.size * sc)
	var pk := PackedScene.new()
	pk.pack(w)
	var e := ResourceSaver.save(pk, PROPS + "komainu.tscn")
	print("[PROPS] komainu -> .tscn err=%d size=%s scale=%.3f" % [e, bb.size * sc, sc])
	inst.free()
	w.free()


func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		n += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MATD))
	var mats := _mats()
	for k in mats:
		ResourceSaver.save(mats[k], MATD + k + ".tres")
		mats[k] = load(MATD + k + ".tres")
	# 賽錢箱：外框 1.70 × 0.86 × 0.78（x,y,z）；原點在底面中心
	_build("saisen_box", mats, [["Box", Vector3(1.70, 0.86, 0.78), Vector3(0, 0.43, 0)]])
	# 板倉：本體 3.6 × 3.0 × 2.7 ＋ 兩級石階（階頂 0.21 / 0.41）；Blender 的 -Y 前 = Godot +Z
	_build("storehouse", mats, [
		["Body", Vector3(3.6, 2.95, 2.7), Vector3(0, 1.475, 0)],
		["Step1", Vector3(1.8, 0.20, 0.55), Vector3(0, 0.10, 1.35 + 0.60)],
		["Step2", Vector3(1.6, 0.41, 0.42), Vector3(0, 0.205, 1.35 + 0.25)],
	])
	_build("broom", mats, [])
	_build_komainu()
	quit()
