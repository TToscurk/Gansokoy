extends SceneTree
## 博麗神社 v3：把 Blender 匯出的 models/*.glb（＋同名 .json 碰撞／標記）轉成
##   assets/shrine_v3/mesh/<name>.res      ArrayMesh（材質換成 assets/shrine_v3/mat/<材質名>.tres；保留匯入時產生的 LOD）
##   assets/shrine_v3/scenes/<name>.tscn   Node3D 根＋MeshInstance3D＋StaticBody3D（簡化碰撞）＋Marker3D
## 先 godot --headless --path godot --import（讓新 GLB 有匯入結果），再：
##   godot --headless --path godot --script res://tools/shrine_v3/build_assets.gd [-- --only=haiden,torii]

const M := preload("res://tools/shrine_v3/s3mat.gd")
const MODELS := "res://assets/shrine_v3/models/"
const MESH_DIR := "res://assets/shrine_v3/mesh/"
const SCN_DIR := "res://assets/shrine_v3/scenes/"
## 個別資產的材質替換（雕像用三向投影石材）
const OVERRIDE := {"komainu_a": {"s3_stone": "s3_stone_tri"}, "komainu_un": {"s3_stone": "s3_stone_tri"}}
const ZH := {
	"haiden": "拜殿", "saisen": "賽錢箱", "torii": "鳥居", "temizuya": "手水舍", "storehouse": "倉庫",
	"lantern_l": "石燈籠_大", "lantern_s": "石燈籠_小", "komainu_base": "狛犬台座", "komainu_a": "狛犬_阿",
	"komainu_un": "狛犬_吽", "crate": "木箱", "broom": "竹箒", "bucket": "木桶", "shagohyo": "社號標",
}


func _init() -> void:
	_run.call_deferred()


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.substr(k.length() + 3)
	return d


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r != null:
			return r
	return null


func _xf(a: Array) -> Transform3D:
	var b := Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]))
	return Transform3D(b, Vector3(a[9], a[10], a[11]))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MESH_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCN_DIR))
	var only := _arg("only", "")
	var rebuilt := {}
	var fails := 0
	var names: Array[String] = []
	for f in DirAccess.get_files_at(MODELS):
		if f.ends_with(".json"):
			names.append(f.get_basename())
	names.sort()
	for nm in names:
		if only != "" and not (nm in only.split(",")):
			continue
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MODELS + nm + ".json"))
		if not ResourceLoader.exists(MODELS + nm + ".glb"):
			push_error("缺 %s.glb 的匯入結果（先 --import）" % nm)
			fails += 1
			continue
		var ps := load(MODELS + nm + ".glb") as PackedScene
		var inst := ps.instantiate()
		var mi := _first_mesh(inst)
		if mi == null:
			push_error("%s.glb 裡沒有網格" % nm)
			fails += 1
			continue
		var mesh := (mi.mesh as ArrayMesh).duplicate() as ArrayMesh
		var ov: Dictionary = OVERRIDE.get(nm, {})
		var used := []
		for i in mesh.get_surface_count():
			var sm := mesh.surface_get_material(i)
			var mname := sm.resource_name if sm != null else mesh.surface_get_name(i)
			if mname == "":
				mname = "s3_stone"     # 體素重網格的雕像會丟失材質名：一律當石材（再由 OVERRIDE 換三向投影）
			mname = String(ov.get(mname, mname))
			if not rebuilt.has(mname):
				M.get_mat(mname, true)
				rebuilt[mname] = true
			mesh.surface_set_material(i, M.get_mat(mname))
			used.append(mname)
		mesh.resource_name = "shrine_v3_" + nm
		var mp := MESH_DIR + nm + ".res"
		var e := ResourceSaver.save(mesh, mp)
		inst.free()
		# 場景
		var root := Node3D.new()
		root.name = String(ZH.get(nm, nm))
		root.set_meta("s3_asset", nm)
		var mi2 := MeshInstance3D.new()
		mi2.name = "模型"
		mi2.mesh = load(mp)
		root.add_child(mi2)
		mi2.owner = root
		var cols: Array = meta.get("collision", [])
		if cols.size() > 0:
			var body := StaticBody3D.new()
			body.name = "碰撞"
			root.add_child(body)
			body.owner = root
			var k := 0
			for c in cols:
				var cs := CollisionShape3D.new()
				cs.name = "%02d_%s" % [k, String(c.get("note", "shape"))]
				if String(c["type"]) == "box":
					var bx := BoxShape3D.new()
					bx.size = Vector3(c["size"][0], c["size"][1], c["size"][2])
					cs.shape = bx
				else:
					var cy := CylinderShape3D.new()
					cy.radius = float(c["r"])
					cy.height = float(c["h"])
					cs.shape = cy
				cs.transform = _xf(c["xf"])
				body.add_child(cs)
				cs.owner = root
				k += 1
		var marks: Dictionary = meta.get("markers", {})
		for mk in marks:
			var m3 := Marker3D.new()
			m3.name = "標記_" + String(mk)
			var v: Array = marks[mk]
			m3.position = Vector3(v[0], v[1], v[2])
			root.add_child(m3)
			m3.owner = root
		var pk := PackedScene.new()
		pk.pack(root)
		var e2 := ResourceSaver.save(pk, SCN_DIR + nm + ".tscn")
		var aabb := mesh.get_aabb()
		print("[ASSET] %-13s mesh=%d scene=%d surfaces=%d lods0=%d cols=%d aabb.pos=%s size=%s mats=%s" % [
			nm, e, e2, mesh.get_surface_count(), mesh.surface_get_array_index_len(0), cols.size(), aabb.position, aabb.size, used])
		root.free()
	print("[ASSET] done fails=%d" % fails)
	fails += _site_meshes(rebuilt)
	quit(1 if fails > 0 else 0)


## models/site/*.glb → mesh/site/<name>.res（世界座標構件與岩石；岩石另存凸包碰撞 <name>_col.res）
func _site_meshes(rebuilt: Dictionary) -> int:
	var src := MODELS + "site/"
	var dst := "res://assets/shrine_v3/mesh/site/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dst))
	var fails := 0
	for f in DirAccess.get_files_at(src):
		if not f.ends_with(".glb"):
			continue
		var nm := f.get_basename()
		var ps := load(src + f) as PackedScene
		if ps == null:
			push_error("讀不到 %s（先 --import）" % f)
			fails += 1
			continue
		var inst := ps.instantiate()
		var mi := _first_mesh(inst)
		var mesh := (mi.mesh as ArrayMesh).duplicate() as ArrayMesh
		inst.free()
		for i in mesh.get_surface_count():
			var sm := mesh.surface_get_material(i)
			var mname := sm.resource_name if sm != null else "s3_stone"
			if not rebuilt.has(mname):
				M.get_mat(mname, true)
				rebuilt[mname] = true
			mesh.surface_set_material(i, M.get_mat(mname))
		mesh.resource_name = "shrine_v3_site_" + nm
		var e := ResourceSaver.save(mesh, dst + nm + ".res")
		var extra := ""
		if nm.begins_with("rock_"):
			var cv := mesh.create_convex_shape(true, true)
			ResourceSaver.save(cv, dst + nm + "_col.res")
			extra = " convex_pts=%d" % cv.points.size()
		print("[SITE] %-15s save=%d aabb=%s%s" % [nm, e, mesh.get_aabb(), extra])
	return fails
