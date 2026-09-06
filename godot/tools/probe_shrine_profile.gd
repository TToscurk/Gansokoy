extends SceneTree
## 神社 blockout 的三個問題量化：邊坡高度、地形梯度、主軸沿線剖面。
##
##   Godot --headless --path godot --script tools/probe_shrine_profile.gd
##
## 實拍看到「參道像戰壕」「山坡有梯田紋」，但截圖不是量測來源（憲法第 5 條）。
## 這支從實際地形網格取數字。

const GEN := preload("res://tools/gen_shrine_blockout.gd")


func _init() -> void:
	var ps := load("res://maps/shrine/shrine.tscn") as PackedScene
	var root := ps.instantiate() as Node3D
	var terr := root.get_node_or_null("Terrain") as MeshInstance3D
	if terr == null:
		print("[PROF] 找不到 Terrain")
		root.free(); quit(1); return
	var arr: Array = terr.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var res := int(round(sqrt(float(vs.size()))))
	var half := 75.0
	var step := 2.0 * half / float(res - 1)
	print("[PROF] 地形 %d×%d，格距 %.2f m，範圍 ±%.0f" % [res, res, step, half])

	# ── 1. 主軸縱剖面（x=0，由南到北）──
	print("[PROF] ── 主軸縱剖面 x=0 ──")
	print("[PROF] %8s %8s %8s" % ["z", "高度", "與前一點落差"])
	var prev := INF
	for i in range(0, 23):
		var z: float = 55.0 - float(i) * 5.0
		var y := _y(vs, res, half, step, 0.0, z)
		var d: String = "%+.2f" % (y - prev) if prev != INF else "-"
		print("[PROF] %+8.1f %8.2f %8s" % [z, y, d])
		prev = y

	# ── 2. 參道橫剖面：邊坡到底多高 ──
	print("[PROF] ── 參道橫剖面（量兩側邊坡）──")
	print("[PROF] %8s %10s %10s %10s" % ["z", "路心高", "±6m 高", "邊坡落差"])
	for z in [40.0, 30.0, 20.0, 10.0, 0.0]:
		var c := _y(vs, res, half, step, 0.0, z)
		var l := _y(vs, res, half, step, -6.0, z)
		var r := _y(vs, res, half, step, 6.0, z)
		var side := (l + r) * 0.5
		print("[PROF] %+8.1f %10.2f %10.2f %10.2f" % [z, c, side, side - c])

	# ── 3. 地形梯度：找最陡的相鄰格點落差（梯田紋的量化）──
	var max_d := 0.0
	var mx := 0.0
	var mz := 0.0
	var steep := 0
	for j in range(res - 1):
		for i in range(res - 1):
			var a := vs[j * res + i].y
			var b := vs[j * res + i + 1].y
			var c2 := vs[(j + 1) * res + i].y
			var d1: float = absf(b - a)
			var d2: float = absf(c2 - a)
			var d: float = maxf(d1, d2)
			if d > 0.6:      # 格距 0.94 m，落差 >0.6 m 即 >32° 且肉眼可見階梯
				steep += 1
			if d > max_d:
				max_d = d
				mx = -half + float(i) * step
				mz = -half + float(j) * step
	print("[PROF] ── 地形梯度 ──")
	print("[PROF] 最大相鄰落差 %.2f m @ (%.0f, %.0f)（格距 %.2f m → 坡度 %.0f°）"
		% [max_d, mx, mz, step, rad_to_deg(atan(max_d / step))])
	print("[PROF] 落差 >0.6 m 的格點對：%d / %d（%.1f%%）"
		% [steep, (res - 1) * (res - 1), float(steep) / float((res - 1) * (res - 1)) * 100.0])

	# ── 4. 鳥居實際位置與尺寸 ──
	var torii := root.get_node_or_null("主鳥居") as Node3D
	if torii != null:
		var box: Variant = null
		for m in _mesh_nodes(torii):
			var b: AABB = _rel(m, root) * (m as MeshInstance3D).get_aabb()
			box = b if box == null else (box as AABB).merge(b)
		var bb := box as AABB
		print("[PROF] ── 鳥居 ──")
		print("[PROF] 世界 AABB 寬 %.2f 高 %.2f 深 %.2f，底 y=%.2f，中心 z=%.1f"
			% [bb.size.x, bb.size.y, bb.size.z, bb.position.y, bb.get_center().z])
		var gy := _y(vs, res, half, step, 0.0, bb.get_center().z)
		print("[PROF] 該處地面 %.2f → 鳥居底離地 %+.2f m" % [gy, bb.position.y - gy])
	root.free()
	quit(0)


func _y(vs: PackedVector3Array, res: int, half: float, step: float, x: float, z: float) -> float:
	var fi := clampf((x + half) / step, 0.0, float(res - 1))
	var fj := clampf((z + half) / step, 0.0, float(res - 1))
	var i0 := int(floor(fi)); var j0 := int(floor(fj))
	var i1 := mini(i0 + 1, res - 1); var j1 := mini(j0 + 1, res - 1)
	var tx := fi - float(i0); var tz := fj - float(j0)
	return lerpf(lerpf(vs[j0 * res + i0].y, vs[j0 * res + i1].y, tx),
		lerpf(vs[j1 * res + i0].y, vs[j1 * res + i1].y, tx), tz)


func _mesh_nodes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		o.append(n)
	for c in n.get_children():
		o.append_array(_mesh_nodes(c))
	return o


func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
