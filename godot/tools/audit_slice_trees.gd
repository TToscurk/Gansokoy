extends SceneTree
## slice 樹木／植被面數盤點：哪些資產、幾棵、各佔多少三角形。
##   Godot --headless --path godot --script tools/audit_slice_trees.gd
##
## ⚠ 不要用 surface_get_arrays() 數面：它會把每個 surface 的頂點資料整包複製到
##   GDScript（slice 有數千個 MeshInstance），實測跑超過 8 分鐘還沒完。
##   ArrayMesh 有 surface_get_array_index_len() / surface_get_array_len()，
##   是純查詢，不搬資料。
var main: Node
var _cache: Dictionary = {}     # mesh RID → tris


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
		# PrimitiveMesh（BoxMesh、QuadMesh…）數量少，用慢路徑無妨
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


## 這個節點屬於哪個來源資產（往上找到第一個 scene_file_path）
func _asset_of(n: Node, root: Node) -> String:
	var cur := n
	var last := String(n.name)
	while cur != null and cur != root:
		if cur.scene_file_path != "":
			return cur.scene_file_path
		last = String(cur.name)
		cur = cur.get_parent()
	return last


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	main.load_map("slice", "")
	await _settle(40)
	var mr: Node = main.map_root
	var per_asset: Dictionary = {}
	var mm_info: Array = []
	var total := 0
	var mm_total := 0
	var stack: Array[Node] = [mr]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm != null and mm.mesh != null:
				var per := _mesh_tris(mm.mesh)
				mm_info.append([String(n.name), mm.instance_count, per, per * mm.instance_count])
				mm_total += per * mm.instance_count
			continue
		if n is MeshInstance3D:
			if not (n as Node3D).is_visible_in_tree():
				continue
			var t := _mesh_tris((n as MeshInstance3D).mesh)
			if t == 0:
				continue
			total += t
			var key := _asset_of(n, mr)
			var e: Dictionary = per_asset.get(key, {"n": 0, "tris": 0})
			e["n"] = int(e["n"]) + 1
			e["tris"] = int(e["tris"]) + t
			per_asset[key] = e
	var rows := []
	for k in per_asset.keys():
		rows.append([k, per_asset[k]["n"], per_asset[k]["tris"]])
	rows.sort_custom(func(a, b): return a[2] > b[2])
	print("[TREE] 單體 MeshInstance 合計 %s 三角形；MultiMesh 合計 %s；全場 %s"
		% [_fmt(total), _fmt(mm_total), _fmt(total + mm_total)])
	print("[TREE] ── MultiMesh 植被 ──")
	for m in mm_info:
		print("[TREE] MM %-18s inst=%-6d 每株=%-6d 合計=%s" % [m[0], m[1], m[2], _fmt(m[3])])
	print("[TREE] ── 單體資產（依總面數排序，前 35）──")
	for i in mini(35, rows.size()):
		var r: Array = rows[i]
		var path := String(r[0])
		var pct := 100.0 * float(r[2]) / float(total + mm_total)
		var lod_path := path.replace(".glb", "_lod.glb").replace(".gltf", "_lod.gltf")
		var has_lod: bool = lod_path != path and ResourceLoader.exists(lod_path)
		print("[TREE] %-56s n=%-5d 合計=%-11s 每個=%-7d %5.1f%% lod=%s"
			% [path.replace("res://", ""), r[1], _fmt(r[2]),
			int(r[2]) / maxi(1, int(r[1])), pct, "有" if has_lod else "無"])
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
