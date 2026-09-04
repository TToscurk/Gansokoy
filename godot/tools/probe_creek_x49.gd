extends SceneTree
## x≈-49 附近的溪谷斷面：check_map 每次都指這裡。到底怎麼回事？
##   Godot --headless --path godot --script tools/probe_creek_x49.gd

func _init() -> void:
	var ps := load("res://maps/trail/trail.tscn") as PackedScene
	var root := ps.instantiate() as Node3D
	var terrain := root.get_node_or_null("Terrain") as MeshInstance3D
	var water := root.get_node_or_null("小溪水面") as MeshInstance3D

	var ta: Array = terrain.mesh.surface_get_arrays(0)
	var tv: PackedVector3Array = ta[Mesh.ARRAY_VERTEX]
	# 地形是規則網格：res × res，直接反推索引
	var res := int(round(sqrt(float(tv.size()))))
	var half := 340.0
	var step := 2.0 * half / float(res - 1)
	print("[X49] 地形 %d×%d 格距 %.2f" % [res, res, step])

	var wa: Array = water.mesh.surface_get_arrays(0)
	var wv: PackedVector3Array = wa[Mesh.ARRAY_VERTEX]
	# 找 x 最接近 -49 的水面頂點
	var wy := 0.0
	var wz := 0.0
	var bd := INF
	for v in wv:
		var d := absf(v.x - (-49.0))
		if d < bd:
			bd = d
			wy = v.y
			wz = v.z
	print("[X49] 水面 @ x=-49：y=%.2f  z=%.2f" % [wy, wz])

	# 沿 z 掃地形斷面
	print("[X49] %8s %8s   %s" % ["z", "地形y", "相對水面"])
	var i := int(round((-49.0 + half) / step))
	for j in range(maxi(0, int(round((wz - 20.0 + half) / step))), mini(res, int(round((wz + 20.0 + half) / step)))):
		var v := tv[j * res + i]
		var rel := v.y - wy
		var mark := ""
		if rel < 0.0:
			mark = "  ← 地形低於水面（水在上，OK）"
		elif rel > 0.05:
			mark = "  ← 地形高於水面（水被埋）"
		print("[X49] %8.1f %8.2f   %+7.2f%s" % [v.z, v.y, rel, mark])
	root.free()
	quit(0)
