extends SceneTree
## 唯読：w9r2 L0 メッシュの『面ごと』の AABB と、ローカル z>しきい値 に載る三角形の統計。
func _init() -> void:
	var id := "B_P_RSW_061"
	var zmin := 5.9
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--id="): id = a.substr(5)
		if a.begins_with("--z="): zmin = float(a.substr(4))
	var m := load("res://assets/village_v2/w9r2_arch/mesh/%s_L0.res" % id) as ArrayMesh
	print("[PM] %s surfaces=%d" % [id, m.get_surface_count()])
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var mat := m.surface_get_material(si)
		var ab := AABB(v[0], Vector3.ZERO)
		for p in v: ab = ab.expand(p)
		print("[PM] surf %d  mat=%s  tris=%d  aabb=%s..%s" % [si, mat.resource_name if mat else "-", idx.size() / 3, ab.position, ab.end])
		var n := 0
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		var downfacing := 0
		for t in idx.size() / 3:
			var p0 := v[idx[t * 3]]; var p1 := v[idx[t * 3 + 1]]; var p2 := v[idx[t * 3 + 2]]
			var c := (p0 + p1 + p2) / 3.0
			if c.z > zmin:
				n += 1
				for p in [p0, p1, p2]:
					lo = lo.min(p); hi = hi.max(p)
		if n > 0:
			print("[PM]    z>%.1f: %d tris  box %s..%s" % [zmin, n, lo, hi])
	quit(0)
