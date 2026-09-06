extends SceneTree
## 水車碰撞現況與代理方案評估。
##
##   Godot --headless --path godot --script tools/probe_wheel_collision.gd
##
## 三個問題：
##   1. 水車現在到底有沒有碰撞？（gen_ground_collision 把它烘進 Waterworks 體）
##   2. 它的幾何是什麼形狀？輪子是鏤空的，玩家該從輪輻間穿過還是被擋住？
##   3. 玩家實際走得到它嗎？水車立在水路裡，人可能根本靠不近。

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load("res://maps/slice/slice.tscn")
	var src := packed.instantiate()

	var wheel := src.get_node_or_null("MachiCanal/Waterworks/水車") as Node3D
	if wheel == null:
		print("[WHEEL] 找不到水車節點")
		quit(1)
		return

	print("[WHEEL] === 節點狀態 ===")
	print("[WHEEL] position=%v scale=%v" % [wheel.position, wheel.scale])
	print("[WHEEL] 腳本=%s" % [wheel.get_script().resource_path if wheel.get_script() else "無"])

	for mi in _meshes(wheel):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null:
			continue
		var xf := _global_xform(mi, src)
		var faces := m.get_faces()
		var world := AABB(xf * faces[0], Vector3.ZERO)
		for v in faces:
			world = world.expand(xf * v)
		print("[WHEEL] 網格 %s：%d 三角面" % [mi.name, faces.size() / 3])
		print("[WHEEL]   世界 AABB 中心=%v 尺寸=%v" % [world.get_center(), world.size])
		print("[WHEEL]   x %.2f~%.2f  y %.2f~%.2f  z %.2f~%.2f" % [
			world.position.x, world.end.x, world.position.y, world.end.y,
			world.position.z, world.end.z])

		# 輪子是圓盤：量它在自己平面上的「實心比例」，判斷鏤空程度。
		# 掃一組穿過輪心的射線，數穿過幾層面。
		var c := world.get_center()
		var solid := 0
		var total := 0
		var r := maxf(world.size.x, world.size.y) * 0.5
		for i in 72:
			var ang := TAU * float(i) / 72.0
			for frac in [0.3, 0.5, 0.7, 0.9]:
				total += 1
				var p := c + Vector3(cos(ang), sin(ang), 0.0) * r * float(frac)
				# 沿輪軸（世界 Z 附近）打，看有沒有面
				if _hits(faces, xf, p):
					solid += 1
		print("[WHEEL]   輪面實心比例 %.1f%%（低 = 鏤空，凸包會封死輪輻間隙）" % [
			100.0 * float(solid) / maxf(total, 1)])

	# 玩家構得到嗎：水車周圍的地面高度與水面
	print("[WHEEL] === 可達性 ===")
	print("[WHEEL] （水路底 y≈-3.1、村道 y≈0.36；水車跨 y -2.8~2.8）")
	print("[WHEEL] 玩家身高 1.7m，站在水路底時頭頂 y≈-1.4，站村道時 y≈2.06")

	src.free()
	print("[WHEEL] done")
	quit(0)


## 該點沿 Z 軸方向是否被任一三角面涵蓋（粗略：投影到 XY 後看點在不在三角形內）
func _hits(faces: PackedVector3Array, xf: Transform3D, p: Vector3) -> bool:
	for i in range(0, faces.size(), 3):
		var a := xf * faces[i]
		var b := xf * faces[i + 1]
		var c := xf * faces[i + 2]
		if _in_tri_xy(p, a, b, c):
			return true
	return false


func _in_tri_xy(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var d1 := (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
	var d2 := (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y)
	var d3 := (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)
	var neg := (d1 < 0.0) or (d2 < 0.0) or (d3 < 0.0)
	var pos := (d1 > 0.0) or (d2 > 0.0) or (d3 > 0.0)
	return not (neg and pos)


func _global_xform(node: Node3D, scene_root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != scene_root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
