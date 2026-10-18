extends SceneTree
## P13 W9 R2：w9r2_arch の GLB → mesh/<名>.res（独立版；建築サンプル 10 棟の LOD0／LOD1 メッシュ）。
## 封存済み tools/village_v2_machiya_kit_prefab.gd（P10 R4／R4b seal に雜湊が入っている）は一字も触らず、同じ手順をこの場所で実行する。
##   godot --headless --path . --script res://tools/p13/w9/w9r2_prefab.gd
## 2026-10-18：重產 mesh/*.res 後自動呼叫 tools/p13/w9/w9r2_dedup_coplanar.gd（去重到收斂＋--check；失敗＝prefab 失敗）。刪掉與保留 Kit 構件共面的重複三角形，否則閃爍回來。--no-dedup 跳過（僅診斷用）。
## 材質は町家 Kit で使用中の承認済み 5 種だけ（白名單外の surface は FAIL）：V2_Wood／V2_Plaster／V2_Kawara／V2_KitStoneTri／V2_MachiyaKit。
const DIR := "res://assets/village_v2/w9r2_arch"
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
	printerr("[w9r2-prefab] FAIL ", s)


func _init() -> void:
	var man: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/src/modules_blender.json"))
	if not man is Dictionary:
		_fail("讀不到 modules_blender.json")
		quit(1)
		return
	var mods: Dictionary = man["modules"]
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(DIR + "/src/w9r2_arch.glb"), st)
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
	var total := 0
	var count := 0
	var paths: Array = []
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
		am.resource_name = "w9r2_" + name
		if tris != int(mods[name]["tris"]):
			_fail("%s 三角面 Godot %d ≠ Blender %d" % [name, tris, int(mods[name]["tris"])])
		total += tris
		var mp := DIR + "/mesh/%s.res" % name
		var e2 := ResourceSaver.save(am, mp, ResourceSaver.FLAG_COMPRESS)
		if e2 != OK:
			_fail("存 %s：%s" % [mp, error_string(e2)])
		paths.append(mp)
		count += 1
	for extra: String in found:
		if not mods.has(extra):
			_fail("GLB 多出未登記構件 %s" % extra)
	var deps: Array = paths + [DIR + "/src/modules_blender.json", DIR + "/src/w9r2_arch.glb"]
	for k: String in MATS:
		deps.append(MATS[k])
	var dsha := {}
	for dp: String in deps:
		dsha[dp] = FileAccess.get_sha256(dp)
		if String(dsha[dp]) == "":
			_fail("manifest 依賴讀不到 %s" % dp)
	var mf := FileAccess.open(DIR + "/w9r2_arch_manifest.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify({"asset": "w9r2_arch", "modules": count, "tris_total": total, "mesh_dir": DIR + "/mesh", "deps": dsha}, " ", true) + "\n")
	mf.close()
	print("[w9r2-prefab] %d 構件、%d 三角面（Blender %d）→ %s/mesh/" % [count, total, int(man["total_tris"]), DIR])
	gl_root.free()
	if fails == 0 and not OS.get_cmdline_user_args().has("--no-dedup"):
		# 2026-10-18：重產的網格會帶回與保留 Kit 構件共面的重複三角形（W9 閃爍）→ 立刻去重，再 --check 確認。任一步失敗都算 prefab 失敗。
		var exe := OS.get_executable_path()
		var proj := ProjectSettings.globalize_path("res://")
		for mode in [[], ["--", "--check"]]:
			var out: Array = []
			var code := OS.execute(exe, ["--headless", "--path", proj, "--script", "res://tools/p13/w9/w9r2_dedup_coplanar.gd"] + mode, out, true)
			for ln: String in String("".join(out)).split("\n"):
				if ln.begins_with("[dedup] SUMMARY") or ln.contains("PASS") or ln.contains("FAIL"):
					print(ln)
			if code != 0:
				_fail("去重%s 失敗（exit %d）" % ["檢查" if not mode.is_empty() else "", code])
	print("[w9r2-prefab] 結果：%d 項失敗" % fails)
	quit(fails)
