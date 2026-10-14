extends SceneTree
## 診断：mesh の AABB と面数。godot --headless --path . --script res://tools/p13/w9/w9_probe_mesh.gd -- res://…/a.res res://…/b.res
func _init() -> void:
	for p: String in OS.get_cmdline_user_args():
		var m := load(p) as Mesh
		if m == null:
			print("[PM] 読めない ", p)
			continue
		var a := m.get_aabb()
		var tris := 0
		for si in m.get_surface_count():
			var arr := m.surface_get_arrays(si)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			tris += (idx.size() if not idx.is_empty() else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		print("[PM] %s  x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f] tris=%d surf=%d" % [p.get_file(), a.position.x, a.end.x, a.position.y, a.end.y, a.position.z, a.end.z, tris, m.get_surface_count()])
	quit(0)
