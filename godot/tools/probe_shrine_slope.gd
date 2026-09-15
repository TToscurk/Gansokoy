extends SceneTree
## 探針：地形坡度 ASCII 圖（5 m 格，每格取最陡三角形）＋ 陡格清單（唯讀）
const SCENE := "res://maps/shrine/shrine.tscn"
const HALF := 75.0
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var scn: Node3D = load(SCENE).instantiate()
	root.add_child(scn)
	await process_frame
	var mi: MeshInstance3D = scn.get_node("Terrain")
	var v0: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var res := int(round(sqrt(float(v0.size()))))
	var stp := 2.0 * HALF / float(res - 1)
	var v := PackedVector3Array()
	v.resize(v0.size())
	for p in v0:
		v[int(round((p.z + HALF) / stp)) * res + int(round((p.x + HALF) / stp))] = p
	var cell := 5.0
	var nc := int(2.0 * HALF / cell)
	var worst := []
	worst.resize(nc * nc)
	worst.fill(0.0)
	var steep := []
	for j in res - 1:
		for i in res - 1:
			var a := v[j * res + i]; var b := v[j * res + i + 1]; var c := v[(j + 1) * res + i]; var d := v[(j + 1) * res + i + 1]
			for tri in [[a, b, c], [b, d, c]]:
				var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				var deg := rad_to_deg(acos(clampf(absf(n.y), 0.0, 1.0)))
				var ci := clampi(int((a.x + HALF) / cell), 0, nc - 1)
				var cj := clampi(int((a.z + HALF) / cell), 0, nc - 1)
				worst[cj * nc + ci] = maxf(worst[cj * nc + ci], deg)
				if deg > 60.0:
					steep.append([deg, a, b, c, d])
	print("[S] 5 m 格最陡坡度（.<20 -<35 +<45 #<60 @>=60）  左=x-75 右=x+75，上=z-75(北) 下=z+75(南)")
	for cj in nc:
		var line := ""
		for ci in nc:
			var w: float = worst[cj * nc + ci]
			line += "." if w < 20 else ("-" if w < 35 else ("+" if w < 45 else ("#" if w < 60 else "@")))
		print("[S] z%+4d %s" % [int(-HALF + cj * cell), line])
	steep.sort_custom(func(p, q): return p[0] > q[0])
	print("[S] >60° 三角形 %d 個，前 12：" % steep.size())
	for s in steep.slice(0, 12):
		print("[S]   %.1f°  a=%s b=%s c=%s d=%s" % [s[0], s[1], s[2], s[3], s[4]])
	quit(0)
