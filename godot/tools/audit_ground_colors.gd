extends SceneTree
func _init() -> void:
	var m: ArrayMesh = load("res://maps/slice/gen/slice_unified_ground.res")
	if m == null:
		print("LOAD_FAIL"); quit(); return
	var arr: Array = m.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols = arr[Mesh.ARRAY_COLOR]
	print("surfaces=%d verts=%d has_color=%s" % [m.get_surface_count(), verts.size(), str(cols != null)])
	if cols == null:
		quit(); return
	# 取樣村台區域 (|x|,|z| < 300) 的 COLOR.r 分布
	var buckets: Array = [0, 0, 0, 0, 0]
	var n: int = 0
	for i in range(verts.size()):
		var v: Vector3 = verts[i]
		if absf(v.x) < 300.0 and absf(v.z) < 300.0:
			var r: float = cols[i].r
			var b: int = clampi(int(r * 5.0), 0, 4)
			buckets[b] += 1
			n += 1
	print("village verts=%d  COLOR.r buckets [0-.2,.2-.4,.4-.6,.6-.8,.8-1]=%s" % [n, str(buckets)])
	quit()
