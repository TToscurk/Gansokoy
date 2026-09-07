extends SceneTree
## RiverVegetation 面數歸屬：Proton Scatter 在 runtime 生的 MultiMesh 是哪些來源網格。
##   Godot --headless --path godot --script tools/audit_river_veg.gd
var main: Node
var _cache: Dictionary = {}


func _init() -> void:
	_run.call_deferred()


func _settle(n: int = 4) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _mesh_tris(m: Mesh) -> int:
	if m == null:
		return 0
	var key := m.get_rid()
	if _cache.has(key):
		return _cache[key]
	var t := 0
	if m is ArrayMesh:
		var am := m as ArrayMesh
		for s in am.get_surface_count():
			if am.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var ilen := am.surface_get_array_index_len(s)
			t += (ilen / 3) if ilen > 0 else (am.surface_get_array_len(s) / 3)
	_cache[key] = t
	return t


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	main.load_map("slice", "")
	await _settle(40)
	var rv: Node = main.map_root.get_node_or_null("RiverVegetation")
	if rv == null:
		print("[RIVER] 找不到 RiverVegetation")
		quit(1)
		return
	# 依「來源 mesh RID + 資源路徑」歸戶
	var by_mesh: Dictionary = {}
	var stack: Array[Node] = [rv]
	var total := 0
	var n_mmi := 0
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if not (n is MultiMeshInstance3D):
			continue
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null:
			continue
		n_mmi += 1
		var per := _mesh_tris(mm.mesh)
		var tris := per * mm.instance_count
		total += tris
		var path := mm.mesh.resource_path
		var key := path if path != "" else "（內嵌）%s surf=%d" % [mm.mesh.get_class(), mm.mesh.get_surface_count()]
		var e: Dictionary = by_mesh.get(key, {"nodes": 0, "inst": 0, "tris": 0, "per": per,
			"parent": String(n.get_parent().name)})
		e["nodes"] = int(e["nodes"]) + 1
		e["inst"] = int(e["inst"]) + mm.instance_count
		e["tris"] = int(e["tris"]) + tris
		by_mesh[key] = e
	var rows := []
	for k in by_mesh.keys():
		rows.append([k, by_mesh[k]])
	rows.sort_custom(func(a, b): return int(a[1]["tris"]) > int(b[1]["tris"]))
	print("[RIVER] MultiMeshInstance3D %d 個，合計 %s 三角形" % [n_mmi, _fmt(total)])
	for r in rows:
		var e: Dictionary = r[1]
		print("[RIVER] %-46s 節點=%-4d 實例=%-6d 每株=%-6d 合計=%-11s %5.1f%%  例:%s"
			% [String(r[0]).replace("res://", ""), e["nodes"], e["inst"], e["per"],
			_fmt(e["tris"]), 100.0 * float(e["tris"]) / float(total), e["parent"]])
	quit(0)


func _fmt(v: int) -> String:
	var s := str(v)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
