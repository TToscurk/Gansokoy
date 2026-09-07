extends SceneTree
## 任意頂層節點的面數歸屬：依來源 mesh 資源路徑歸戶，找出該砍誰。
##   Godot --headless --path godot --script tools/audit_group_meshes.gd -- <節點名> [<節點名>...]
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
			var il := am.surface_get_array_index_len(s)
			t += (il / 3) if il > 0 else (am.surface_get_array_len(s) / 3)
	_cache[key] = t
	return t


func _audit(g: Node) -> void:
	var by_mesh: Dictionary = {}
	var total := 0
	var hidden := 0
	var stack: Array[Node] = [g]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		var per := 0
		var count := 1
		var mesh: Mesh = null
		if n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			mesh = mm.mesh
			per = _mesh_tris(mesh)
			count = mm.instance_count
		elif n is MeshInstance3D:
			mesh = (n as MeshInstance3D).mesh
			per = _mesh_tris(mesh)
		else:
			continue
		if per == 0:
			continue
		var tris := per * count
		var vis: bool = (n as Node3D).is_visible_in_tree()
		if vis:
			total += tris
		else:
			hidden += tris
		var path := mesh.resource_path
		var key := path if path != "" else "（內嵌 %s）" % mesh.get_class()
		var e: Dictionary = by_mesh.get(key, {"nodes": 0, "inst": 0, "vis": 0, "hid": 0, "per": per})
		e["nodes"] = int(e["nodes"]) + 1
		e["inst"] = int(e["inst"]) + count
		if vis:
			e["vis"] = int(e["vis"]) + tris
		else:
			e["hid"] = int(e["hid"]) + tris
		by_mesh[key] = e
	var rows := []
	for k in by_mesh.keys():
		rows.append([k, by_mesh[k]])
	rows.sort_custom(func(a, b): return int(a[1]["vis"]) > int(b[1]["vis"]))
	print("[GRP] ══ %s ══ 可見 %s ／ 隱藏 %s" % [g.name, _fmt(total), _fmt(hidden)])
	for r in rows:
		var e: Dictionary = r[1]
		if int(e["vis"]) + int(e["hid"]) < 30000:
			continue
		print("[GRP] %-52s 節點=%-4d 實例=%-6d 每個=%-7d 可見=%-11s 隱藏=%-11s %5.1f%%"
			% [String(r[0]).replace("res://", ""), e["nodes"], e["inst"], e["per"],
			_fmt(e["vis"]), _fmt(e["hid"]),
			100.0 * float(e["vis"]) / maxf(1.0, float(total))])


func _run() -> void:
	var names: Array = []
	for a in OS.get_cmdline_user_args():
		names.append(a)
	if names.is_empty():
		names = ["B1_Street", "MachiCanal"]
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	main.load_map("slice", "")
	await _settle(40)
	for nm in names:
		var g: Node = main.map_root.get_node_or_null(String(nm))
		if g == null:
			print("[GRP] 找不到節點 %s" % nm)
			continue
		_audit(g)
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
