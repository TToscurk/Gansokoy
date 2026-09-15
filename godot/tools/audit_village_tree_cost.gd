extends SceneTree
## 量村緣樹群現況面數（每株 × 株數）。

func _init() -> void:
	_run.call_deferred()

func _tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		if m.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var il: int = m.surface_get_array_index_len(s)
		var al: int = m.surface_get_array_len(s)
		t += (il / 3) if il > 0 else (al / 3)
	return t

func _run() -> void:
	print("=== 村緣樹群 每株面數 x 株數 ===")
	var names := ["普通樹", "大衫", "2大衫", "針葉樹1",
		"針葉林樹3", "針葉林樹4", "盆樹"]
	var total := 0
	for n in names:
		var mm := ResourceLoader.load("res://maps/slice/gen/treemm_%s.res" % n,
			"", ResourceLoader.CACHE_MODE_IGNORE) as MultiMesh
		if mm == null:
			print("  缺 %s" % n)
			continue
		var per: int = _tris(mm.mesh) if mm.mesh != null else 0
		var cnt: int = mm.instance_count
		total += per * cnt
		print("  %-12s 每株 %6d  x %3d = %8d" % [n, per, cnt, per * cnt])
	print("  村緣樹群合計 %d 面" % total)
	quit(0)
