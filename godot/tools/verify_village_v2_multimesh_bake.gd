extends SceneTree
## 人間之里 V2 永久 build rule 稽核（tag MMBAKE）：village_v2 場景中全部 MultiMesh（各 overlay 的 MultiMeshInstance3D）
## instance transform 非零。必須非 headless 跑（headless 讀不到 MultiMesh 資料 → 直接 FAIL，不當 PASS）。
##   Godot --path . --script res://tools/verify_village_v2_multimesh_bake.gd
## 內建反向：記憶體中造一個含零矩陣 instance 的 MultiMesh → audit 必須數到 1；空場景 → 不得 PASS（非空保證）。
## 每項一行 [MMBAKE] PASS/FAIL；結尾 quit(失敗項數)。

const MMG := preload("res://tools/village_v2_mm_bake_guard.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"

var fails := 0


func check(label: String, ok: bool) -> void:
	print("[MMBAKE] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	check("rendering display（%s；headless 讀不到 MultiMesh 資料）" % DisplayServer.get_name(), MMG.display_ok())
	if not MMG.display_ok():
		print("[MMBAKE] 結果：%d 項失敗" % fails)
		quit(fails)
		return
	# 反向 1：零矩陣 instance 必須被數到
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = 3
	mm.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(6, 2, 2))   # 零矩陣で AABB 再計算の警告を出さない
	mm.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3(0.3, 0.3, 0.3)), Vector3(1, 0, 0)))
	mm.set_instance_transform(1, Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3(2, 0, 0)))
	mm.set_instance_transform(2, Transform3D(Basis(Vector3.UP, 0.7), Vector3(3, 0, 0)))
	var neg := Node3D.new()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	neg.add_child(mmi)
	var rn := MMG.audit_node(neg)
	check("反向：含 1 個零矩陣的 MultiMesh → audit 數到 %d（必須 1）且判定不通過" % int(rn["zero"]), int(rn["zero"]) == 1 and not MMG.ok(rn))
	neg.free()
	# 反向 2：沒有 MultiMesh 的樹不得 PASS
	var empty := Node3D.new()
	check("反向：無 MultiMesh 的節點樹不得判定通過", not MMG.ok(MMG.audit_node(empty)))
	empty.free()
	# 本體：整個場景，按來源（instanced overlay 的 scene_file_path）分組
	var v: Node = (ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var by_src := {}
	for n in v.find_children("*", "MultiMeshInstance3D", true, false):
		var src := "village_v2.tscn"
		var a: Node = n
		while a != null and a != v:
			if a.scene_file_path != "":
				src = a.scene_file_path.get_file()
				break
			a = a.get_parent()
		if not by_src.has(src):
			by_src[src] = [0, 0, 0]
		var r := MMG.zero_instances((n as MultiMeshInstance3D).multimesh) if (n as MultiMeshInstance3D).multimesh else PackedInt32Array([0, 0])
		by_src[src][0] += 1
		by_src[src][1] += r[0]
		by_src[src][2] += r[1]
	var tot := [0, 0, 0]
	var keys := by_src.keys()
	keys.sort()
	for k: String in keys:
		print("[MMBAKE] INFO %s：MultiMesh 節點 %d、instance %d、零矩陣 %d" % [k, by_src[k][0], by_src[k][1], by_src[k][2]])
		for i in 3:
			tot[i] += by_src[k][i]
		check("%s 的 MultiMesh instance transform 全部非零（零矩陣 %d / %d）" % [k, by_src[k][2], by_src[k][1]], by_src[k][2] == 0)
	check("非空：場景 MultiMesh 節點 %d、instance %d（> 0）" % [tot[0], tot[1]], tot[0] > 0 and tot[1] > 0)
	v.free()
	print("[MMBAKE] 結果：%d 項失敗" % fails)
	quit(fails)
