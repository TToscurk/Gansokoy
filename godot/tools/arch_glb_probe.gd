extends SceneTree
## Blender↔Godot 座標實測（唯讀）：用 GLTFDocument 直接讀 GLB（不經專案匯入、不寫檔），
## 由節點 xform 鏈＋ImporterMesh 頂點算每個網格節點的「緊」世界 AABB，與 Blender 端換算的預期值比對。
## 用法：godot --headless --script res://tools/arch_glb_probe.gd -- --glb=<abs.glb> [--expect=<abs.json>] [--tol=0.0005]
##   無 --expect：只印 JSON。有 --expect：逐節點比 min/max，任何超差 exit 1。
##   headless 讀 ImporterMesh（CPU 端陣列）可靠；不要改用 MeshInstance3D.mesh（dummy RenderingServer 會是空的）。

func _initialize() -> void:
	var glb := ""
	var expect := ""
	var tol := 0.0005
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--glb="): glb = a.trim_prefix("--glb=")
		elif a.begins_with("--expect="): expect = a.trim_prefix("--expect=")
		elif a.begins_with("--tol="): tol = float(a.trim_prefix("--tol="))
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(glb, st)
	if err != OK:
		printerr("[ARCH-GLB] 讀取失敗 ", glb, " err=", err)
		quit(2)
		return
	var nodes: Array = st.get_nodes()
	var meshes: Array = st.get_meshes()
	var out := {}
	for i in nodes.size():
		var n: GLTFNode = nodes[i]
		if n.mesh < 0:
			continue
		var xf := Transform3D.IDENTITY
		var k := i
		while k >= 0:
			xf = (nodes[k] as GLTFNode).xform * xf
			k = (nodes[k] as GLTFNode).parent
		var im: ImporterMesh = (meshes[n.mesh] as GLTFMesh).mesh
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for s in im.get_surface_count():
			var verts: PackedVector3Array = im.get_surface_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var w := xf * v
				lo = lo.min(w)
				hi = hi.max(w)
		var nm := n.original_name if n.original_name != "" else String(n.resource_name)
		out[nm] = {"min": [lo.x, lo.y, lo.z], "max": [hi.x, hi.y, hi.z], "det": xf.basis.determinant()}
	print("[ARCH-GLB] ", JSON.stringify(out))
	if expect == "":
		quit(0)
		return
	var exp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expect))
	var bad := 0
	for nm in exp.keys():
		if not out.has(nm):
			print("[ARCH-GLB] MISSING ", nm)
			bad += 1
			continue
		var dev := 0.0
		for key in ["min", "max"]:
			for ax in 3:
				dev = maxf(dev, absf(float(exp[nm][key][ax]) - float(out[nm][key][ax])))
		var ok := dev <= tol
		if not ok: bad += 1
		print("[ARCH-GLB] %s %s max_dev=%.6f m det=%.3f" % ["PASS" if ok else "FAIL", nm, dev, out[nm]["det"]])
	print("[ARCH-GLB] %d/%d nodes within %.4f m" % [exp.size() - bad, exp.size(), tol])
	quit(1 if bad else 0)
