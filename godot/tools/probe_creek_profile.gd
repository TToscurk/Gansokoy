extends SceneTree
## 小溪斷面實測：沿溪心量「地形網格的實際高度」與目前水面高度的差。
##
##   Godot --headless --path godot --script tools/probe_creek_profile.gd
##
## 為什麼不能用產生器的 height_at()：地形網格是 201×201（格距 3.4 m），
## 解析函式的細節在取樣時被抹平。check_map 打的是網格，我得打同一個東西。

func _init() -> void:
	var ps := load("res://maps/trail/trail.tscn") as PackedScene
	var root := ps.instantiate() as Node3D
	var terrain := root.get_node_or_null("Terrain") as MeshInstance3D
	var water := root.get_node_or_null("小溪水面") as MeshInstance3D
	if terrain == null or water == null:
		print("[CREEK] 找不到 Terrain 或 小溪水面")
		root.free(); quit(1); return

	# 地形三角形 → 以 xz 網格查最高面（和 check_map 的 _ground_min_at 同義）
	var ta: Array = terrain.mesh.surface_get_arrays(0)
	var tv: PackedVector3Array = ta[Mesh.ARRAY_VERTEX]
	var ti: PackedInt32Array = ta[Mesh.ARRAY_INDEX]
	print("[CREEK] 地形頂點 %d 面 %d" % [tv.size(), ti.size() / 3])

	var wa: Array = water.mesh.surface_get_arrays(0)
	var wv: PackedVector3Array = wa[Mesh.ARRAY_VERTEX]
	print("[CREEK] 水面頂點 %d" % wv.size())

	# 對每個水面頂點，找地形上同 xz 的高度（掃描最近的地形三角形）
	print("[CREEK] %8s %8s %9s %9s %8s" % ["x", "z", "水面y", "地形y", "差"])
	var buried := 0
	var worst := -INF
	var wx := 0.0
	for k in range(0, wv.size(), maxi(1, wv.size() / 30)):
		var p: Vector3 = wv[k]
		var gy := _ground_at(tv, ti, p.x, p.z)
		if gy == -INF:
			continue
		var diff := gy - p.y
		if diff > 0.05:
			buried += 1
		if diff > worst:
			worst = diff
			wx = p.x
		print("[CREEK] %8.1f %8.1f %9.2f %9.2f %8.2f%s" % [p.x, p.z, p.y, gy, diff, "  ← 埋" if diff > 0.05 else ""])
	print("[CREEK] 取樣中 %d 個埋在地下，最深 %.2f m @ x=%.0f" % [buried, worst, wx])
	root.free()
	quit(0)


## 回傳 (x,z) 落在的地形三角形的內插高度；找不到回 -INF
func _ground_at(tv: PackedVector3Array, ti: PackedInt32Array, x: float, z: float) -> float:
	var best := -INF
	for f in range(0, ti.size(), 3):
		var a := tv[ti[f]]
		var b := tv[ti[f + 1]]
		var c := tv[ti[f + 2]]
		# 快速排除
		var minx := minf(a.x, minf(b.x, c.x))
		var maxx := maxf(a.x, maxf(b.x, c.x))
		if x < minx or x > maxx:
			continue
		var minz := minf(a.z, minf(b.z, c.z))
		var maxz := maxf(a.z, maxf(b.z, c.z))
		if z < minz or z > maxz:
			continue
		var y := _bary_y(a, b, c, x, z)
		if y != -INF and y > best:
			best = y
	return best


func _bary_y(a: Vector3, b: Vector3, c: Vector3, x: float, z: float) -> float:
	var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if absf(d) < 0.00001:
		return -INF
	var w1 := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d
	var w2 := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d
	var w3 := 1.0 - w1 - w2
	if w1 < -0.001 or w2 < -0.001 or w3 < -0.001:
		return -INF
	return a.y * w1 + b.y * w2 + c.y * w3
