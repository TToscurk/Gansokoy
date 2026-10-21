extends SceneTree
## Blender↔Godot 座標實測（唯讀）：GLTFDocument 直接讀 GLB（不經專案匯入、不寫檔），逐節點與
## Blender 端 arch_check.py --godot-expect（或 test_arch_spatial.py --glb-out）的期望值比對：
## 緊 AABB、原點、旋轉、每軸縮放、行列式（負縮放）＋正面標記在 +Z 側。比對邏輯在 arch_spatial_lib.gd。
## 用法：godot --headless --path godot --script res://tools/arch_glb_probe.gd -- --glb=<abs.glb> [--expect=<abs.json>] [--out=<json>]
##   無 --expect：只印 JSON。有 --expect：任何 FAIL／缺節點 exit 1。
##   headless 讀 ImporterMesh（CPU 端陣列）可靠；不要改用 MeshInstance3D.mesh（dummy RenderingServer 會是空的）。
const ARCH := preload("res://tools/arch_spatial_lib.gd")


func _initialize() -> void:
	var glb := ""
	var expect := ""
	var outp := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--glb="): glb = a.trim_prefix("--glb=")
		elif a.begins_with("--expect="): expect = a.trim_prefix("--expect=")
		elif a.begins_with("--out="): outp = a.trim_prefix("--out=")
	var got := ARCH.gltf_mesh_nodes(glb)
	if got.has("_error"):
		printerr("[ARCH-GLB] ", got["_error"], " ", glb)
		quit(2)
		return
	if expect == "":
		var dump := {}
		for nm: String in got.keys():
			dump[nm] = {"min": ARCH._v(got[nm]["lo"]), "max": ARCH._v(got[nm]["hi"]), "det": (got[nm]["xform"] as Transform3D).basis.determinant()}
		print("[ARCH-GLB] ", JSON.stringify(dump))
		quit(0)
		return
	var ref := ARCH.load_expect(expect)
	if ref.has("_error"):
		printerr("[ARCH-GLB] ", ref["_error"])
		quit(2)
		return
	var rows := ARCH.compare_nodes(glb.get_file(), ref, got, "blender_vs_glb")
	if ref.has("_front_node"):
		rows.append(ARCH.front_check(glb.get_file(), got, ref["_front_node"], "glb"))
	for r: Dictionary in rows:
		print("[ARCH-GLB] %s %s %s %s" % [r["status"], r["rule_id"], JSON.stringify(r["actual"]), r["suggestion"]])
	var s := ARCH.summarize(rows)
	print("[ARCH-GLB] PASS %d / WARN %d / FAIL %d / UNKNOWN %d" % [s["PASS"], s["WARN"], s["FAIL"], s["UNKNOWN"]])
	if outp != "":
		var f := FileAccess.open(outp, FileAccess.WRITE)
		f.store_string(JSON.stringify({"tool": ARCH.TOOL, "summary": s, "results": rows}, " "))
		f.close()
	quit(1 if s["FAIL"] > 0 else 0)
