extends SceneTree
## Rank individual mesh assets by per-copy triangle cost and total draw cost.
##
## Why: the census showed 71.6M triangles, but that number alone does not say
## what to fix. A 1M-triangle building drawn once and a 500-triangle bush drawn
## 2700 times are both "expensive" for completely different reasons and need
## opposite treatments (decimate vs merge). This lists both axes so the fix
## matches the cause.
##
## Run: godot --headless --path godot --script tools/audit_mesh_hotspots.gd

const SCENE := "res://maps/slice/slice.tscn"


func _init() -> void:
	var packed: PackedScene = load(SCENE)
	var root: Node = packed.instantiate()

	# mesh resource path -> {tris, copies, mm_instances}
	var by_mesh := {}
	_walk(root, by_mesh)

	var rows: Array = []
	for k in by_mesh:
		var e = by_mesh[k]
		var copies: int = e["copies"] + e["mm"]
		rows.append({
			"name": k,
			"tris": e["tris"],
			"copies": copies,
			"total": e["tris"] * copies,
		})

	rows.sort_custom(func(a, b): return a["total"] > b["total"])

	print("=== 三角面總量排行（單體面數 x 份數）===\n")
	print("%-42s %10s %8s %12s" % ["網格", "單體面數", "份數", "總面數"])
	var shown := 0
	for r in rows:
		if shown >= 24:
			break
		print("%-42s %10s %8d %12s" % [
			_short(r["name"]), _fmt(r["tris"]), r["copies"], _fmt(r["total"])])
		shown += 1

	print("\n=== 單體最重的網格（適合減面/LOD）===\n")
	rows.sort_custom(func(a, b): return a["tris"] > b["tris"])
	print("%-42s %10s %8s" % ["網格", "單體面數", "份數"])
	for i in min(14, rows.size()):
		var r = rows[i]
		print("%-42s %10s %8d" % [_short(r["name"]), _fmt(r["tris"]), r["copies"]])

	print("\n=== 份數最多的網格（適合合併/MultiMesh）===\n")
	rows.sort_custom(func(a, b): return a["copies"] > b["copies"])
	print("%-42s %8s %10s %12s" % ["網格", "份數", "單體面數", "總面數"])
	for i in min(14, rows.size()):
		var r = rows[i]
		if r["copies"] < 5:
			break
		print("%-42s %8d %10s %12s" % [
			_short(r["name"]), r["copies"], _fmt(r["tris"]), _fmt(r["total"])])

	root.free()
	quit(0)


func _short(p: String) -> String:
	var s := p.get_file()
	if s.is_empty():
		s = p
	return s.substr(0, 42)


func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


func _walk(node: Node, acc: Dictionary) -> void:
	if node is MultiMeshInstance3D:
		var mi := node as MultiMeshInstance3D
		var mm := mi.multimesh
		if mm != null and mm.mesh != null:
			var key := _key(mm.mesh)
			if not acc.has(key):
				acc[key] = {"tris": _tris(mm.mesh), "copies": 0, "mm": 0}
			acc[key]["mm"] += mm.instance_count
	elif node is MeshInstance3D:
		var m := node as MeshInstance3D
		if m.mesh != null:
			var key := _key(m.mesh)
			if not acc.has(key):
				acc[key] = {"tris": _tris(m.mesh), "copies": 0, "mm": 0}
			acc[key]["copies"] += 1
	for c in node.get_children():
		_walk(c, acc)


func _key(mesh: Mesh) -> String:
	if not mesh.resource_path.is_empty():
		return mesh.resource_path
	if not mesh.resource_name.is_empty():
		return "<內嵌> " + mesh.resource_name
	return "<內嵌> %d" % mesh.get_instance_id()


func _tris(mesh: Mesh) -> int:
	var t := 0
	for i in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(i)
		if arr.is_empty():
			continue
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx != null and idx.size() > 0:
			t += idx.size() / 3
		else:
			var v = arr[Mesh.ARRAY_VERTEX]
			if v != null:
				t += v.size() / 3
	return t
