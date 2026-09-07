extends SceneTree
## slice 面數歸屬：只算「實際會畫出來的」（is_visible_in_tree），依頂層節點分組。
##   Godot --headless --path godot --script tools/audit_slice_budget.gd
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
	else:
		for s in m.get_surface_count():
			var a := m.surface_get_arrays(s)
			if a.is_empty():
				continue
			var ix: Variant = a[Mesh.ARRAY_INDEX]
			if ix != null and (ix as PackedInt32Array).size() > 0:
				t += (ix as PackedInt32Array).size() / 3
			else:
				var v: Variant = a[Mesh.ARRAY_VERTEX]
				if v != null:
					t += (v as PackedVector3Array).size() / 3
	_cache[key] = t
	return t


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	main.load_map("slice", "")
	await _settle(40)
	var mr: Node = main.map_root
	var vis: Dictionary = {}
	var hid: Dictionary = {}
	var vt := 0
	var ht := 0
	for top in mr.get_children():
		var stack: Array[Node] = [top]
		var v := 0
		var h := 0
		while stack.size() > 0:
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.push_back(c)
			var t := 0
			if n is MultiMeshInstance3D:
				var mm := (n as MultiMeshInstance3D).multimesh
				if mm != null and mm.mesh != null:
					t = _mesh_tris(mm.mesh) * mm.instance_count
			elif n is MeshInstance3D:
				t = _mesh_tris((n as MeshInstance3D).mesh)
			if t == 0:
				continue
			if (n as Node3D).is_visible_in_tree():
				v += t
			else:
				h += t
		if v > 0:
			vis[String(top.name)] = v
			vt += v
		if h > 0:
			hid[String(top.name)] = h
			ht += h
	print("[BUDGET] 可見合計 %s ／ 隱藏合計 %s" % [_fmt(vt), _fmt(ht)])
	print("[BUDGET] ── 可見（依面數排序）──")
	var rows := []
	for k in vis.keys():
		rows.append([k, vis[k]])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	for r in rows:
		if int(r[1]) < 20000:
			continue
		print("[BUDGET] %-30s %-12s %5.1f%%" % [r[0], _fmt(r[1]), 100.0 * float(r[1]) / float(vt)])
	print("[BUDGET] ── 隱藏（白吃記憶體，不畫）──")
	var rows2 := []
	for k in hid.keys():
		rows2.append([k, hid[k]])
	rows2.sort_custom(func(a, b): return a[1] > b[1])
	for r in rows2:
		if int(r[1]) < 20000:
			continue
		print("[BUDGET] %-30s %s" % [r[0], _fmt(r[1])])
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
