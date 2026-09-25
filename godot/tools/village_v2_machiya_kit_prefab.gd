extends SceneTree
## 人間之里 V2 P6 R1：模組化町家 Kit 構件庫 prefab。
##   godot --headless --path . --script res://tools/village_v2_machiya_kit_prefab.gd
## 讀 Blender 匯出的 assets/village_v2/machiya_kit/src/machiya_kit.glb（build_machiya_kit.py），
## 依 src/modules_blender.json 逐一轉成 ArrayMesh（材質＝共享材質庫 _matlib／Kit atlas），每個構件存一個外部檔：
##   assets/village_v2/machiya_kit/mesh/<構件名>.res（構件只存一次；village_v2.tscn 只存 ext_resource 路徑＋transform）
## 並寫 machiya_kit_manifest.json（Kit 的 gate entry）：構件庫、組裝腳本、材質、atlas 的 sha256。
##   任何一檔改動 → manifest 雜湊變 → gate.json／registry 失效 → 產生器維持灰盒（與 Hero .scn 雜湊同一規則）。
## 同時比對 Blender 端三角面數，任何構件缺漏、材質不在白名單、transform 不是 identity → 失敗。

const DIR := "res://assets/village_v2/machiya_kit"
const MATS := {
	"V2_Wood": "res://assets/village_v2/_matlib/V2_Wood.tres",
	"V2_Plaster": "res://assets/village_v2/_matlib/V2_Plaster.tres",
	"V2_Kawara": "res://assets/village_v2/_matlib/V2_Kawara.tres",
	"V2_KitStoneTri": "res://assets/village_v2/machiya_kit/V2_KitStoneTri.tres",
	"V2_MachiyaKit": "res://assets/village_v2/machiya_kit/V2_MachiyaKit.tres",
}

var fails := 0


func _fail(s: String) -> void:
	fails += 1
	printerr("[kit-prefab] FAIL ", s)


func _init() -> void:
	var man: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/src/modules_blender.json"))
	if not man is Dictionary:
		_fail("讀不到 modules_blender.json")
		quit(1)
		return
	var mods: Dictionary = man["modules"]
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(DIR + "/src/machiya_kit.glb"), st)
	if err != OK:
		_fail("GLTF 讀取失敗：%s" % error_string(err))
		quit(1)
		return
	var gl_root: Node = doc.generate_scene(st)
	var found := {}
	for n in gl_root.find_children("*", "", true, false):
		var m: Mesh = null
		if n is MeshInstance3D:
			m = (n as MeshInstance3D).mesh
		elif n is ImporterMeshInstance3D:
			m = (n as ImporterMeshInstance3D).mesh.get_mesh()
		if m != null:
			found[String(n.name)] = [m, (n as Node3D).transform]
	var mats := {}
	for k: String in MATS:
		mats[k] = load(MATS[k])
		if mats[k] == null:
			_fail("材質讀不到 %s" % MATS[k])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "/mesh"))
	for old in DirAccess.get_files_at(DIR + "/mesh"):
		if old.ends_with(".res") and not mods.has(old.get_basename()):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/mesh/" + old))
	var mesh_paths: Array = []
	var total := 0
	var id := 0
	for name: String in mods:
		if not found.has(name):
			_fail("GLB 缺構件 %s" % name)
			continue
		var src: Mesh = found[name][0]
		if not (found[name][1] as Transform3D).is_equal_approx(Transform3D.IDENTITY):
			_fail("%s transform 不是 identity" % name)
		var am := ArrayMesh.new()
		var tris := 0
		for si in src.get_surface_count():
			var arr := src.surface_get_arrays(si)
			var mat: Material = src.surface_get_material(si)
			var mname := mat.resource_name if mat != null else ""
			if not mats.has(mname):
				_fail("%s surface %d 材質「%s」不在白名單" % [name, si, mname])
				continue
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			tris += (idx.size() if not idx.is_empty() else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			am.surface_set_name(am.get_surface_count() - 1, mname)
			am.surface_set_material(am.get_surface_count() - 1, mats[mname])
		am.resource_name = "kit_" + name
		var bt := int(mods[name]["tris"])
		if tris != bt:
			_fail("%s 三角面 Godot %d ≠ Blender %d" % [name, tris, bt])
		total += tris
		var mp := DIR + "/mesh/%s.res" % name
		var e2 := ResourceSaver.save(am, mp, ResourceSaver.FLAG_COMPRESS)
		if e2 != OK:
			_fail("存 %s：%s" % [mp, error_string(e2)])
		mesh_paths.append(mp)
		id += 1
	for extra: String in found:
		if not mods.has(extra):
			_fail("GLB 多出未登記構件 %s" % extra)
	print("[kit-prefab] %d 構件、%d 三角面（Blender %d）→ %s/mesh/" % [id, total, int(man["total_tris"]), DIR])
	var deps := mesh_paths + ["res://tools/village_v2_machiya_kit_lib.gd", DIR + "/machiya_kit_atlas.png", DIR + "/machiya_kit_emit.png",
		DIR + "/atlas.json", DIR + "/src/modules_blender.json"]
	for k: String in MATS:
		deps.append(MATS[k])
	var dsha := {}
	for dp: String in deps:
		dsha[dp] = FileAccess.get_sha256(dp)
		if String(dsha[dp]) == "":
			_fail("manifest 依賴讀不到 %s" % dp)
	var mf := FileAccess.open(DIR + "/machiya_kit_manifest.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify({"asset": "machiya_kit", "modules": id, "tris_total": total,
		"assembler": "res://tools/village_v2_machiya_kit_lib.gd", "mesh_dir": DIR + "/mesh", "deps": dsha}, " ", true) + "\n")
	mf.close()
	print("[kit-prefab] manifest %d 依賴 → %s/machiya_kit_manifest.json" % [deps.size(), DIR])
	gl_root.free()
	print("[kit-prefab] 結果：%d 項失敗" % fails)
	quit(fails)
